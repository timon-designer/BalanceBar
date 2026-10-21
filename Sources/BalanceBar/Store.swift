import Cocoa

// MARK: - 数据仓库

final class BalanceStore {
    static let shared = BalanceStore()

    private(set) var config = AppConfig.load()
    private(set) var results: [BalanceResult] = []
    private(set) var lastUpdate: Date? = nil
    private(set) var isRefreshing = false

    /// 多观察者：面板和菜单栏各自订阅，不能共用一个闭包（会互相覆盖）
    private var observers: [ObjectIdentifier: () -> Void] = [:]

    func observe(_ owner: AnyObject, _ block: @escaping () -> Void) {
        observers[ObjectIdentifier(owner)] = block
    }

    func unobserve(_ owner: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(owner))
    }

    func notify() {
        let callbacks = Array(observers.values)
        DispatchQueue.main.async { callbacks.forEach { $0() } }
    }

    private var generation = 0

    func reloadConfig() {
        KeyStore.reload()
        config = AppConfig.load()
        notify()
    }

    func openConfigFile() {
        let url = AppConfig.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: AppConfig.configDir, withIntermediateDirectories: true)
            config.save()
        }
        NSWorkspace.shared.open(url)
    }

    func refresh() {
        generation += 1
        let gen = generation
        let providers = config.providers.filter { $0.enabled }
        isRefreshing = true
        notify()
        Task {
            var collected: [BalanceResult] = []
            await withTaskGroup(of: BalanceResult.self) { group in
                for p in providers {
                    group.addTask { await Providers.fetch(p) }
                }
                for await r in group { collected.append(r) }
            }
            let order = providers.map { $0.id }
            collected.sort { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
            await MainActor.run {
                guard gen == self.generation else { return }
                self.results = collected
                self.lastUpdate = Date()
                self.isRefreshing = false
                Log.write("刷新完成 | 标题=\(self.statusTitle()) | " + collected.map { r in
                    let s: String
                    switch r.state {
                    case .ok: s = r.statusDisplay
                    case .linkOnly: s = "LINK"
                    case .needKey: s = "NO_KEY"
                    case .error: s = "ERR:\(r.error ?? "")"
                    }
                    // 智谱这类双行平台把副行（资源包 token）也写进日志，方便 tail 核对
                    let tail = r.tokenNote.map { "(\($0))" } ?? ""
                    return "\(r.id)=\(s)\(tail)"
                }.joined(separator: " "))
                self.notify()
            }
        }
    }

    // MARK: 菜单栏标题
    func statusTitle() -> String {
        let mode = config.menuTitle
        let ok = results.filter { $0.state == .ok && $0.amount != nil }
        if let id = results.first(where: { $0.id == mode }) {
            // 现金可用显示 ¥，现金取不到但 token 可用时 statusDisplay 退回缩写值
            return id.state == .ok ? id.statusDisplay : id.displayAmount
        }
        if mode == "min", let m = ok.min(by: { ($0.amount ?? 0) < ($1.amount ?? 0) }) {
            return m.statusDisplay
        }
        var parts: [String] = []
        for cur in ["CNY", "USD"] {
            let sum = ok.filter { $0.currency == cur }.reduce(0.0) { $0 + ($1.amount ?? 0) }
            let n = ok.filter { $0.currency == cur }.count
            if n > 0 {
                let sym = cur == "USD" ? "$" : "¥"
                parts.append(sym + String(format: "%.2f", sum))
            }
        }
        let unknown = ok.filter { $0.currency == nil }.count
        if unknown > 0 { parts.append("?") }
        // 合计里没有现金、但有 token 资源包的平台（智谱现金为 0 时也走这里）：单独列出缩写值
        let tokenOnly = results.filter { $0.state == .ok && $0.amount == nil && $0.tokenAmount != nil }
        parts.append(contentsOf: tokenOnly.map { "\($0.name) \(Fmt.tokens($0.tokenAmount!))" })
        if parts.isEmpty { return results.isEmpty ? "余额" : "—" }
        return parts.joined(separator: " ")
    }

    func summaryLine() -> String {
        let ok = results.filter { $0.state == .ok }.count
        let bad = results.filter { $0.state == .error || $0.state == .needKey }.count
        var s = "\(ok)/\(results.count) 个平台已获取"
        if bad > 0 { s += " · \(bad) 个异常" }
        return s
    }
}
