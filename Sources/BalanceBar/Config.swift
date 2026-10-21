import Foundation

// MARK: - 平台元数据表（平台即数据）
// 加平台 = 在 table 里加一行 + 在 Providers 里加一个适配器函数；
// 设置页字段、默认地址、额外参数全部由这张表派生，不许再写按 type 的 UI 分支。

/// 额外参数：设置页自动渲染的行
struct ExtraParam {
    /// ProviderConfig 上的字段名（value(forKey:) / setValue(forKey:) 里要有对应分支）
    var key: String
    /// 输入框左侧的标签
    var label: String
    /// 未配置时的占位文案
    var placeholder: String
    /// 密文输入框
    var secure: Bool = false
    /// 非 nil → 这是凭据，写进 ~/.balancebar/.env；nil → 普通参数，写进 config.json
    var envName: String? = nil
}

struct ProviderMeta {
    /// 设置页类型徽标旁边的人话说明
    var label: String
    /// 需要 API Key（走 apiKeyEnv）
    var needsKey: Bool
    /// 需要站点地址
    var needsBaseURL: Bool
    /// 设置页只保留「控制台」入口（阿里云百炼 / 小米 MiMo：无按 key 的公开余额接口）
    var consoleOnly: Bool = false
    /// 该平台有峰谷分时定价，面板行要在名称旁挂「峰时 / 非峰时」标签（当前只有 DeepSeek）。
    /// 判定规则在 `PeakPricing`，与余额接口无关，所以标签在每次渲染时按当前时刻重算。
    var peakPricing: Bool = false
    /// 站点地址输入框的占位文案（nil 用默认）
    var basePlaceholder: String? = nil
    /// 额外参数（按顺序渲染）
    var extras: [ExtraParam] = []
    /// 余额适配器。参数：(配置, 站点地址, key, 半成品结果)。nil = 无接口（link 型，面板只给跳转）
    var fetch: ((ProviderConfig, String, String, BalanceResult) async throws -> BalanceResult)? = nil

    static func of(_ type: String) -> ProviderMeta? { table[type.lowercased()] }

    /// 设置页白名单（按显示顺序）。不在这里的类型：设置页不渲染、保存时从 config.json 移除。
    /// moonshot / siliconflow / openrouter / relay 已按需求下架（适配器保留在 Providers.swift 备用）。
    static let settingsWhitelist = ["deepseek", "zhipu", "aliyun", "mimo"]

    /// 各平台通用：低余额阈值（余额低于它时状态点变黄）
    static let lowWarnParam = ExtraParam(key: "lowWarn", label: "低余额阈值",
                                         placeholder: "低于该值变黄，可留空")

    static let table: [String: ProviderMeta] = [
        "deepseek": .init(
            label: "DeepSeek 开放平台", needsKey: true, needsBaseURL: true,
            peakPricing: true,
            extras: [lowWarnParam],
            fetch: { try await Providers.deepseek($0, $1, $2, $3) }
        ),
        "zhipu": .init(
            label: "智谱开放平台", needsKey: true, needsBaseURL: true,
            extras: [lowWarnParam],
            fetch: { try await Providers.zhipu($0, $1, $2, $3) }
        ),
        "aliyun": .init(
            label: "阿里云百炼（无按 key 余额接口）", needsKey: false, needsBaseURL: false,
            consoleOnly: true
            // 如需恢复自动查余额：把 fetch 接回 Providers.aliyun 并在设置页恢复 AccessKey 字段
        ),
        "mimo": .init(
            label: "小米 MiMo API 开放平台", needsKey: false, needsBaseURL: false,
            consoleOnly: true
        ),
        "link": .init(label: "纯链接（无余额接口）", needsKey: false, needsBaseURL: false)
    ]
}

extension ProviderConfig {
    /// 设置页按 meta.extras 自动读写用（字段名 → 字符串）
    func value(forKey k: String) -> String? {
        switch k {
        case "relayUnit":       return relayUnit
        case "relayDivisor":    return relayDivisor.map(Self.numStr)
        case "lowWarn":         return lowWarn.map(Self.numStr)
        case "accessKeyId":     return accessKeyId
        case "accessKeySecret": return accessKeySecret
        case "note":            return note
        default:                return nil
        }
    }

    mutating func setValue(_ v: String?, forKey k: String) {
        switch k {
        case "relayUnit":       relayUnit = v?.trimmed.nonEmpty
        case "relayDivisor":    relayDivisor = v?.trimmed.nonEmpty.flatMap(Double.init)
        case "lowWarn":         lowWarn = v?.trimmed.nonEmpty.flatMap(Double.init)
        case "accessKeyId":     accessKeyId = v?.trimmed.nonEmpty
        case "accessKeySecret": accessKeySecret = v?.trimmed.nonEmpty
        case "note":            note = v?.trimmed.nonEmpty
        default:                break
        }
    }

    static func numStr(_ d: Double) -> String {
        (d == d.rounded() && abs(d) < 1e15) ? String(Int(d)) : "\(d)"
    }
}

// MARK: - 配置模型

struct ProviderConfig: Codable {
    var id: String
    var name: String
    /// deepseek | zhipu | aliyun | mimo | link（moonshot/siliconflow/openrouter/relay 已下架，字段保留兼容旧配置）
    var type: String
    var enabled: Bool = true
    /// 直接写 key（不推荐）
    var apiKey: String? = nil
    /// 从环境变量取 key；会依次查找：进程环境 → ~/.hermes/.env → ~/.balancebar/.env
    var apiKeyEnv: String? = nil
    var baseURL: String? = nil
    /// 充值页
    var rechargeURL: String? = nil
    /// 控制台/账单页
    var consoleURL: String? = nil
    /// 阿里云 BSS 专用
    var accessKeyId: String? = nil
    var accessKeySecret: String? = nil
    /// 余额低于该值时状态点变红（与余额同币种）
    var lowWarn: Double? = nil
    /// relay 专用：CNY | USD | quota
    var relayUnit: String? = nil
    /// relay 专用：raw quota → 货币的除数（默认 500000）
    var relayDivisor: Double? = nil
    var note: String? = nil
}

struct AppConfig: Codable {
    var refreshSeconds: Double = 600
    /// auto | total | min | <provider id>
    var menuTitle: String = "auto"
    var showCurrencySymbol: Bool = true
    var providers: [ProviderConfig] = []

    static let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".balancebar", isDirectory: true)
    }()
    static var configURL: URL { configDir.appendingPathComponent("config.json") }

    static func load() -> AppConfig {
        if let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return cfg
        }
        let cfg = AppConfig.makeDefault()
        cfg.save()
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(self) {
            try? FileManager.default.createDirectory(at: AppConfig.configDir, withIntermediateDirectories: true)
            try? data.write(to: AppConfig.configURL)
        }
    }

    static func makeDefault() -> AppConfig {
        var cfg = AppConfig()
        cfg.providers = [
            ProviderConfig(
                id: "deepseek", name: "DeepSeek", type: "deepseek", enabled: true,
                apiKeyEnv: "DEEPSEEK_API_KEY",
                baseURL: "https://api.deepseek.com",
                rechargeURL: "https://platform.deepseek.com/top_up",
                consoleURL: "https://platform.deepseek.com/usage",
                lowWarn: 10, note: "官方余额接口"
            ),
            ProviderConfig(
                id: "zhipu", name: "智谱 GLM", type: "zhipu", enabled: true,
                apiKeyEnv: "GLM_API_KEY",
                baseURL: "https://open.bigmodel.cn",
                rechargeURL: "https://open.bigmodel.cn/finance/personal",
                consoleURL: "https://open.bigmodel.cn/console/overview",
                lowWarn: 10, note: "需要 GLM_API_KEY（open.bigmodel.cn 的 API Key）"
            ),
            ProviderConfig(
                id: "bailian", name: "阿里云百炼", type: "aliyun", enabled: false,
                consoleURL: "https://bailian.console.aliyun.com/",
                note: "无按 key 的公开余额接口，点开控制台查看"
            ),
            ProviderConfig(
                id: "mimo", name: "小米 MiMo", type: "mimo", enabled: true,
                consoleURL: "https://platform.xiaomimimo.com/console/balance",
                note: "MiMo API 开放平台，无公开余额接口，点开控制台查看用量与余额"
            )
        ]
        return cfg
    }
}
