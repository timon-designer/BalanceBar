import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}

// MARK: - 把设置页填的值写回磁盘

enum ConfigWriter {
    /// secrets 以「环境变量名 → 值」写进 ~/.balancebar/.env（upsert，不动注释和其它行）
    @discardableResult
    static func save(config: AppConfig, secrets: [String: String]) -> String {
        config.save()
        var written: [String] = ["config.json"]
        let clean = secrets.filter { !$0.value.trimmed.isEmpty }
        if !clean.isEmpty {
            KeyStore.writeEnv(clean)
            written.append("key 文件（\(clean.keys.sorted().joined(separator: ", "))）")
        }
        return "已保存：" + written.joined(separator: " + ")
    }
}

// MARK: - Key 解析：进程环境 → ~/.balancebar/.env → ~/.hermes/.env

enum KeyStore {
    /// 读缓存的线程安全：BalanceStore.refresh() 是并发拉多个平台的，
    /// 曾经因为先把 loaded 置位、再填缓存，导致并发的第二个线程拿到空缓存，
    /// 面板随机出现「缺少 key（DEEPSEEK_API_KEY）」。别再改成无锁。
    private static let lock = NSLock()
    private static var envFileCache: [String: String] = [:]
    private static var loaded = false

    static var userEnvURL: URL { AppConfig.configDir.appendingPathComponent(".env") }

    static func parseEnvFile(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return out }
        for rawLine in text.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    /// 必须在持锁状态下调用；缓存填完整之后才置 loaded
    private static func buildCacheLocked() {
        guard !loaded else { return }
        var cache: [String: String] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser
        for url in [userEnvURL, home.appendingPathComponent(".hermes/.env")] {
            for (k, v) in parseEnvFile(url) where cache[k] == nil {
                cache[k] = v
            }
        }
        envFileCache = cache
        loaded = true
    }

    static func value(env: String?, inline: String?) -> String? {
        if let v = inline?.trimmed.nonEmpty { return v }
        guard let env, !env.isEmpty else { return nil }
        if let v = ProcessInfo.processInfo.environment[env]?.trimmed.nonEmpty { return v }
        lock.lock()
        defer { lock.unlock() }
        buildCacheLocked()
        return envFileCache[env]?.trimmed.nonEmpty
    }

    /// 该环境变量名是否已有值（设置页用来显示「已配置 / 未配置」）
    static func has(env: String?) -> Bool { value(env: env, inline: nil) != nil }

    /// 凭据落盘权限：目录 700、.env 600。644 意味着任何本地进程都能读 key。
    static func enforcePermissions() {
        let fm = FileManager.default
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: AppConfig.configDir.path)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: userEnvURL.path)
    }

    /// upsert 写入 key 文件，保留注释与其它行
    static func writeEnv(_ pairs: [String: String], to url: URL? = nil) {
        let target = url ?? userEnvURL
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        var lines: [String]
        if let text = try? String(contentsOf: target, encoding: .utf8) {
            lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } else {
            lines = ["# BalanceBar 的 key 文件（由面板设置页写入，请勿提交到任何仓库）", ""]
        }
        var remaining = pairs
        for (i, line) in lines.enumerated() {
            var body = line.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("export ") { body = String(body.dropFirst(7)) }
            guard !body.hasPrefix("#"), let eq = body.firstIndex(of: "=") else { continue }
            let key = String(body[body.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            if let v = remaining[key] {
                lines[i] = "\(key)=\(v)"
                remaining.removeValue(forKey: key)
            }
        }
        for (k, v) in remaining.sorted(by: { $0.key < $1.key }) {
            if lines.last?.trimmed.isEmpty == false { lines.append("") }
            lines.append("\(k)=\(v)")
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: target, atomically: true, encoding: .utf8)
        // 写完立刻收紧：.env 一律 600，任何本地进程都能读的 644 不允许出现
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        if target == userEnvURL { enforcePermissions() }
        reload()
    }

    static func reload() {
        lock.lock()
        defer { lock.unlock() }
        loaded = false
        envFileCache = [:]
    }
}
