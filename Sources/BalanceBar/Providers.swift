import Foundation
import CryptoKit

// MARK: - 结果模型

enum BalanceState {
    case ok          // 有余额数字
    case linkOnly    // 只能点开看（无接口）
    case needKey     // 缺 key
    case error       // 请求失败
}

struct BalanceResult {
    var id: String
    var name: String
    var amount: Double? = nil
    var currency: String? = nil
    var detail: String? = nil
    /// 用量信息（30 天已用 / 累计已用）。没有用量接口的平台保持 nil，行内不渲染
    var usage: String? = nil
    var error: String? = nil
    var rechargeURL: String? = nil
    var consoleURL: String? = nil
    var lowWarn: Double? = nil
    var state: BalanceState = .error
    var updatedAt: Date = Date()
    // ↓ 新增字段一律追加在末尾：成员初始化参数顺序（detail 在 rechargeURL 前）不能被破坏
    /// 副行：资源包 token 余量（单位 tokens）。nil = 该平台不渲染副行
    var tokenAmount: Double? = nil
    /// 副行标题（如 `glm-5.3-flash`）
    var tokenLabel: String? = nil
    /// 副行接口失败原因（token 接口失败时显示，现金行照常）
    var tokenError: String? = nil
    /// 主行（现金）接口失败原因（token 行照常时显示）
    var cashError: String? = nil
    /// 该平台有峰谷分时定价 → 面板行名称旁挂「峰时 / 非峰时」标签。
    /// 由 `ProviderMeta.peakPricing` 在这里统一带上，标签**值**在渲染时按当前时刻算
    /// （见 PeakPricing），所以不随刷新才更新，也不会过期。
    var showsPeakPricing: Bool = false

    var isLow: Bool {
        guard let amount, let lowWarn else { return false }
        return amount <= lowWarn
    }

    var displayAmount: String {
        guard let amount else { return "—" }
        let sym = currency == "USD" ? "$" : (currency == "CNY" ? "¥" : "")
        return sym + String(format: "%.2f", amount)
    }

    /// 副行里的 token 段（`glm-5.3-flash 39.7m`）。没有 token 资源包时为 nil。
    var tokenLine: String? {
        guard let t = tokenAmount else { return nil }
        let name = (tokenLabel?.isEmpty == false) ? tokenLabel! : "token"
        return name + " " + Fmt.tokens(t)
    }

    /// token 段 + 两路的失败原因（不含现金构成）。--probe 的「副行」用这个。
    var tokenNote: String? {
        var parts: [String] = []
        if let t = tokenLine { parts.append(t) }
        if let e = tokenError, !e.isEmpty { parts.append(e) }
        if let e = cashError, !e.isEmpty { parts.append(e) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 面板副行文本：token 资源包优先，后面跟现金构成（充值/已用）与两路的失败原因。
    /// 换算只走 Fmt.tokens，provider / 面板 / 日志都不再自行拼字符串。
    var subLine: String? {
        var parts: [String] = []
        if let t = tokenLine { parts.append(t) }
        if let e = tokenError, !e.isEmpty { parts.append(e) }
        if let d = detail, !d.isEmpty { parts.append(d) }
        if let e = cashError, !e.isEmpty { parts.append(e) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 副行里是否含失败原因（决定副行是否走错误色）
    var subLineHasError: Bool {
        (tokenError?.isEmpty == false) || (cashError?.isEmpty == false)
    }

    /// 菜单栏/合计口径的展示值：现金优先，现金不可用时退回 token 缩写
    var statusDisplay: String {
        if amount != nil { return displayAmount }
        if let t = tokenAmount { return Fmt.tokens(t) }
        return displayAmount
    }
}

// MARK: - HTTP

enum HTTPError: Error {
    case badURL
    case status(Int, String)
    case badBody
}

struct HTTPResponse {
    var status: Int
    var data: Data
    var headers: [String: String]

    var json: Any? { try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
    /// 错误/成功信息里常见的文本字段
    var message: String? {
        guard let obj = json as? [String: Any] else {
            return String(data: data.prefix(200), encoding: .utf8)
        }
        for k in ["msg", "message", "error_message", "detail"] {
            if let s = obj[k] as? String { return s }
        }
        if let err = obj["error"] as? [String: Any] {
            if let s = err["message"] as? String { return s }
        }
        return nil
    }
}

enum HTTP {
    static func get(_ urlString: String, headers: [String: String] = [:], timeout: Double = 15) async throws -> HTTPResponse {
        guard let url = URL(string: urlString) else { throw HTTPError.badURL }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        var hs: [String: String] = [:]
        http?.allHeaderFields.forEach { k, v in hs["\(k)".lowercased()] = "\(v)" }
        return HTTPResponse(status: status, data: data, headers: hs)
    }
}

// MARK: - 容错 JSON 取值

enum JSONPick {
    /// 在任意层级里按 key 优先级找第一个数值/数字字符串
    static func number(_ obj: Any?, keys: [String]) -> Double? {
        var found: Double? = nil
        func walk(_ node: Any) {
            if found != nil { return }
            if let dict = node as? [String: Any] {
                for k in keys {
                    if let v = dict[k], let d = toDouble(v) { found = d; return }
                }
                // 大小写不敏感兜底
                let lower = keys.map { $0.lowercased() }
                for (k, v) in dict where lower.contains(k.lowercased()) {
                    if let d = toDouble(v) { found = d; return }
                }
                for (_, v) in dict { walk(v) }
            } else if let arr = node as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(obj ?? NSNull())
        return found
    }

    static func string(_ obj: Any?, keys: [String]) -> String? {
        var found: String? = nil
        func walk(_ node: Any) {
            if found != nil { return }
            if let dict = node as? [String: Any] {
                for k in keys {
                    if let v = dict[k] as? String, !v.isEmpty { found = v; return }
                }
                for (_, v) in dict { walk(v) }
            } else if let arr = node as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(obj ?? NSNull())
        return found
    }

    static func toDouble(_ v: Any) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
}

// MARK: - 数值格式化（token 缩写规则的唯一出口）

enum Fmt {
    /// token 数缩写：≥1,000,000 → `xx.xm`；≥1,000 → `xx.xk`；以下原样。
    /// provider 不硬拼字符串，面板渲染处也不再自行换算，都走这里。
    static func tokens(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 {
            let m = v / 1_000_000
            return String(format: m == m.rounded() ? "%.0fm" : "%.1fm", m)
        }
        if a >= 1_000 {
            let k = v / 1_000
            return String(format: k == k.rounded() ? "%.0fk" : "%.1fk", k)
        }
        return String(format: "%.0f", v)
    }
}

// MARK: - 适配器

enum Providers {
    /// 统一入口：查 meta 表派发，不再写按 type 的 if/elif 长分支
    static func fetch(_ cfg: ProviderConfig) async -> BalanceResult {
        var r = BalanceResult(id: cfg.id, name: cfg.name,
                              rechargeURL: cfg.rechargeURL, consoleURL: cfg.consoleURL,
                              lowWarn: cfg.lowWarn)
        guard let meta = ProviderMeta.of(cfg.type) else {
            r.state = .error
            r.error = "未知类型 \(cfg.type)"
            return r
        }
        r.showsPeakPricing = meta.peakPricing   // 峰谷标签与余额接口无关，缺 key / 失败也照挂
        guard let fn = meta.fetch else {          // link 型：无接口，只给跳转
            r.state = .linkOnly
            r.detail = cfg.note ?? "点开控制台查看"
            return r
        }
        var key = ""
        if meta.needsKey {
            guard let k = KeyStore.value(env: cfg.apiKeyEnv, inline: cfg.apiKey), !k.isEmpty else {
                r.state = .needKey
                r.error = "缺少 key" + (cfg.apiKeyEnv.map { "（\($0)）" } ?? "")
                return r
            }
            key = k
        }
        var base = ""
        if meta.needsBaseURL {
            base = (cfg.baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard !base.isEmpty else {
                r.state = .needKey
                r.error = "未填写站点地址"
                return r
            }
        }
        do {
            return try await fn(cfg, base, key, r)
        } catch {
            r.state = .error
            r.error = shortError(error)
            return r
        }
    }

    static func shortError(_ error: Error) -> String {
        if let e = error as? HTTPError {
            switch e {
            case .badURL: return "URL 无效"
            case .status(let code, let msg): return msg.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(msg)"
            case .badBody: return "返回格式异常"
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "域名解析失败"
            case NSURLErrorCannotConnectToHost: return "无法连接"
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorNotConnectedToInternet: return "网络不可用"
            default: return "网络错误 \(ns.code)"
            }
        }
        return ns.localizedDescription
    }

    private static func check(_ resp: HTTPResponse) throws -> Any {
        guard (200..<300).contains(resp.status) else {
            throw HTTPError.status(resp.status, resp.message ?? "")
        }
        return resp.json ?? NSNull()
    }

    // MARK: DeepSeek
    static func deepseek(_ cfg: ProviderConfig, _ base: String, _ key: String, _ r0: BalanceResult) async throws -> BalanceResult {
        var r = r0
        let resp = try await HTTP.get("\(base)/user/balance", headers: ["Authorization": "Bearer \(key)"])
        let obj = try check(resp)
        guard let dict = obj as? [String: Any], let infos = dict["balance_infos"] as? [[String: Any]], !infos.isEmpty else {
            throw HTTPError.badBody
        }
        let preferred = ["CNY", "USD"]
        let picked = infos.first { preferred.contains(($0["currency"] as? String) ?? "") } ?? infos[0]
        r.amount = JSONPick.toDouble(picked["total_balance"] ?? 0)
        r.currency = (picked["currency"] as? String) ?? "CNY"
        let granted = JSONPick.toDouble(picked["granted_balance"] ?? 0) ?? 0
        let topped = JSONPick.toDouble(picked["topped_up_balance"] ?? 0) ?? 0
        r.detail = String(format: "充值 %.2f · 赠送 %.2f", topped, granted)
        r.state = .ok
        return r
    }

    // MARK: 智谱 GLM（两行：现金余额 + 资源包 token）
    // 两接口都调、互不影响：任一失败另一行照常显示；两者都失败才整体报错。
    static func zhipu(_ cfg: ProviderConfig, _ base: String, _ key: String, _ r0: BalanceResult) async throws -> BalanceResult {
        var r = r0
        let headers = ["Authorization": "Bearer \(key)", "Accept": "application/json"]

        async let cashTask = zhipuCash(headers: headers)
        async let packTask = zhipuTokenPacks(headers: headers)
        let (cash, packs) = await (cashTask, packTask)

        // 第一行：账户现金余额
        switch cash {
        case .ok(let amount, let detail):
            r.amount = amount
            r.currency = "CNY"
            r.detail = detail
        case .fail(let msg):
            r.cashError = msg
        }

        // 第二行：资源包 token 余量
        switch packs {
        case .ok(let total, let label):
            r.tokenAmount = total
            r.tokenLabel = label
        case .fail(let msg):
            r.tokenError = msg
        }

        let cashOK = r.amount != nil
        let packOK = r.tokenAmount != nil
        if cashOK || packOK {
            r.state = .ok
            return r
        }
        throw HTTPError.status(0, [r.cashError, r.tokenError].compactMap { $0 }.first ?? "现金与资源包接口均无数据")
    }

    private enum ZhipuLine {
        case ok(Double, String)     // 数值 + 说明
        case fail(String)            // 失败原因
    }

    /// 现金余额：www.bigmodel.cn 控制台主机的账户报表接口。
    /// HTTP 200 但 body 可能 `code:401`，判成功必须同时看 body code + success。
    private static func zhipuCash(headers: [String: String]) async -> ZhipuLine {
        let url = "https://www.bigmodel.cn/api/biz/account/query-customer-account-report"
        guard let resp = try? await HTTP.get(url, headers: headers),
              (200..<300).contains(resp.status), let obj = resp.json else {
            return .fail("现金接口不可用")
        }
        let codeOK = (JSONPick.number(obj, keys: ["code"]) ?? 200) < 400
            && (JSONPick.string(obj, keys: ["success"]) ?? "true") != "false"
        guard codeOK, let amount = JSONPick.number(obj, keys: ["availableBalance", "balance"]) else {
            let msg = JSONPick.string(obj, keys: ["msg", "message"]) ?? "现金接口无余额字段"
            return .fail(msg)
        }
        var parts: [String] = []
        if let topped = JSONPick.number(obj, keys: ["rechargeAmount"]) {
            parts.append(String(format: "充值 %.2f", topped))
        }
        if let spent = JSONPick.number(obj, keys: ["totalSpendAmount"]) {
            parts.append(String(format: "已用 %.2f", spent))
        }
        if let given = JSONPick.number(obj, keys: ["giveAmount"]), given > 0 {
            parts.append(String(format: "赠送 %.2f", given))
        }
        return .ok(amount, parts.isEmpty ? "现金余额" : parts.joined(separator: " · "))
    }

    /// 资源包 token 余量：bigmodel.cn 的 tokenAccounts/list/my。
    /// Bearer 直接用 GLM_API_KEY，不需要网页 cookie（2026-10-08 实测）。
    private static func zhipuTokenPacks(headers: [String: String]) async -> ZhipuLine {
        let url = "https://bigmodel.cn/api/biz/tokenAccounts/list/my?pageNum=1&pageSize=20&filterEnabled=false"
        guard let resp = try? await HTTP.get(url, headers: headers),
              (200..<300).contains(resp.status),
              let pobj = resp.json as? [String: Any],
              (JSONPick.number(pobj, keys: ["code"]) ?? 500) == 200 else {
            return .fail("资源包接口不可用")
        }
        let rows = (pobj["rows"] as? [[String: Any]]) ?? []
        let active = rows.filter {
            ($0["status"] as? String) == "EFFECTIVE"
                && ((($0["suitableModel"] as? String) ?? "").contains("glm-5.3-flash"))
        }
        guard !active.isEmpty else { return .fail("无生效的 glm-5.3-flash 资源包") }
        let total = active.reduce(0.0) { $0 + (JSONPick.toDouble($1["availableBalance"] ?? 0) ?? 0) }
        let label = ((active.first?["suitableModel"] as? String) ?? "glm-5.3-flash")
        return .ok(total, label)
    }

    // MARK: Kimi / Moonshot
    static func moonshot(_ cfg: ProviderConfig, _ base: String, _ key: String, _ r0: BalanceResult) async throws -> BalanceResult {
        var r = r0
        let resp = try await HTTP.get("\(base)/v1/users/me/balance", headers: ["Authorization": "Bearer \(key)"])
        let obj = try check(resp)
        guard let amount = JSONPick.number(obj, keys: ["available_balance", "balance"]) else { throw HTTPError.badBody }
        r.amount = amount
        r.currency = "CNY"
        if let voucher = JSONPick.number(obj, keys: ["voucher_balance"]),
           let cash = JSONPick.number(obj, keys: ["cash_balance"]) {
            r.detail = String(format: "现金 %.2f · 代金券 %.2f", cash, voucher)
        }
        r.state = .ok
        return r
    }

    // MARK: 硅基流动
    static func siliconflow(_ cfg: ProviderConfig, _ base: String, _ key: String, _ r0: BalanceResult) async throws -> BalanceResult {
        var r = r0
        let resp = try await HTTP.get("\(base)/v1/user/info", headers: ["Authorization": "Bearer \(key)"])
        let obj = try check(resp)
        guard let amount = JSONPick.number(obj, keys: ["totalBalance", "balance"]) else { throw HTTPError.badBody }
        r.amount = amount
        r.currency = "CNY"
        if let charge = JSONPick.number(obj, keys: ["chargeBalance"]),
           let gift = JSONPick.number(obj, keys: ["balance"]) {
            r.detail = String(format: "现金 %.2f · 赠送 %.2f", charge, gift)
        }
        r.state = .ok
        return r
    }

    // MARK: OpenRouter
    static func openrouter(_ cfg: ProviderConfig, _ base: String, _ key: String, _ r0: BalanceResult) async throws -> BalanceResult {
        var r = r0
        let resp = try await HTTP.get("\(base)/api/v1/credits", headers: ["Authorization": "Bearer \(key)"])
        let obj = try check(resp)
        guard let total = JSONPick.number(obj, keys: ["total_credits"]),
              let used = JSONPick.number(obj, keys: ["total_usage"]) else { throw HTTPError.badBody }
        r.amount = total - used
        r.currency = "USD"
        r.detail = String(format: "额度总额 %.2f", total)
        r.usage = String(format: "已用 $%.2f（累计）", used)
        r.state = .ok
        return r
    }

    // MARK: 第三方中转站（OpenAI 兼容，new-api / one-api 系）
    static func relay(_ cfg: ProviderConfig, _ base: String, _ key: String, _ r0: BalanceResult) async throws -> BalanceResult {
        var r = r0
        let headers = ["Authorization": "Bearer \(key)", "Accept": "application/json"]
        let divisor = cfg.relayDivisor ?? 500_000
        let unit = (cfg.relayUnit ?? "auto").uppercased()

        // ① OpenAI 兼容 billing 接口（one-api / new-api 默认实现）
        var usd: Double? = nil
        var usage: String? = nil
        var hit = ""
        if let sub = try? await HTTP.get("\(base)/v1/dashboard/billing/subscription", headers: headers),
           (200..<300).contains(sub.status) {
            let hard = JSONPick.number(sub.json, keys: ["hard_limit_usd", "system_hard_limit_usd"]) ?? 0
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let start = fmt.string(from: Date().addingTimeInterval(-30 * 86400))
            let end = fmt.string(from: Date().addingTimeInterval(86400))
            usd = hard
            hit = "billing/subscription · one-api/new-api 系"
            if let use = try? await HTTP.get("\(base)/v1/dashboard/billing/usage?start_date=\(start)&end_date=\(end)", headers: headers),
               (200..<300).contains(use.status) {
                let usedRaw = JSONPick.number(use.json, keys: ["total_usage"]) ?? 0
                let cents = usedRaw / 100.0        // one-api 口径：total_usage 单位是美分
                let a = hard - cents
                let b = hard - usedRaw
                usd = a >= 0 ? a : b
                usage = String(format: "30 天已用 $%.2f", a >= 0 ? cents : usedRaw)
            }
        }

        // ② /api/user/self（new-api 站点，余额以 quota 计）
        var quota: Double? = nil
        var usedQuota: Double? = nil
        if usd == nil,
           let selfResp = try? await HTTP.get("\(base)/api/user/self", headers: headers),
           (200..<300).contains(selfResp.status) {
            let obj = selfResp.json
            quota = JSONPick.number(obj, keys: ["quota", "remain_quota"])
            usedQuota = JSONPick.number(obj, keys: ["used_quota"])
            if quota != nil { hit = "api/user/self · new-api 系" }
        }

        if let usd {
            r.amount = usd
            r.currency = unit == "CNY" ? "CNY" : "USD"
            r.detail = hit
            r.usage = usage
            r.state = .ok
            return r
        }
        if let quota {
            r.amount = quota / divisor
            r.currency = unit == "QUOTA" ? nil : (unit == "USD" ? "USD" : "CNY")
            r.detail = hit + String(format: " · quota %.0f ÷ %.0f", quota, divisor)
            if let u = usedQuota { r.usage = String(format: "已用 %.2f（按当前除数）", u / divisor) }
            r.state = .ok
            return r
        }
        throw HTTPError.status(0, "站点未提供余额接口")
    }

    // MARK: 阿里云百炼（无按 key 余额接口 → 账户余额 BSS，需 AccessKey）
    static func aliyun(_ cfg: ProviderConfig, _ base: String, _ key: String, _ r0: BalanceResult) async -> BalanceResult {
        let ak = KeyStore.value(env: "ALIYUN_ACCESS_KEY_ID", inline: cfg.accessKeyId)
        let sk = KeyStore.value(env: "ALIYUN_ACCESS_KEY_SECRET", inline: cfg.accessKeySecret)
        guard let ak, let sk else {
            var r = r0
            r.state = .linkOnly
            r.detail = "需登录控制台查看（填 AccessKey 可自动查）"
            return r
        }
        return await aliyunBSS(cfg, result: r0, ak: ak, sk: sk)
    }

    // MARK: 阿里云账户余额（BSS OpenAPI，需 AccessKey）
    static func aliyunBSS(_ cfg: ProviderConfig, result r0: BalanceResult, ak: String, sk: String) async -> BalanceResult {
        var r = r0
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let params: [String: String] = [
            "Action": "QueryAccountBalance",
            "Version": "2017-12-14",
            "Format": "JSON",
            "AccessKeyId": ak,
            "SignatureMethod": "HMAC-SHA1",
            "SignatureVersion": "1.0",
            "SignatureNonce": UUID().uuidString,
            "Timestamp": fmt.string(from: Date())
        ]
        let canonical = params.keys.sorted().map { "\(pe($0))=\(pe(params[$0]!))" }.joined(separator: "&")
        let stringToSign = "GET&%2F&" + pe(canonical)
        let key = SymmetricKey(data: Data((sk + "&").utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        let signature = Data(mac).base64EncodedString()
        let url = "https://business.aliyuncs.com/?Signature=\(pe(signature))&" + canonical
        do {
            let resp = try await HTTP.get(url)
            let obj = try check(resp)
            if let amount = JSONPick.number(obj, keys: ["AvailableAmount", "AvailableCashAmount"]) {
                r.amount = amount
                r.currency = JSONPick.string(obj, keys: ["Currency"]) ?? "CNY"
                r.detail = "阿里云账户可用余额"
                r.state = .ok
                return r
            }
            r.state = .error
            r.error = JSONPick.string(obj, keys: ["Message", "Code"]) ?? "返回中无余额字段"
            return r
        } catch {
            r.state = .error
            r.error = shortError(error)
            return r
        }
    }

    /// 阿里云要求的 RFC3986 编码
    static func pe(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
