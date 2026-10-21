import Foundation

/// 轻量日志：写入 ~/.balancebar/last-run.log，便于命令行核对 App 内部状态
enum Log {
    static let url = AppConfig.configDir.appendingPathComponent("last-run.log")

    static func write(_ line: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm:ss"
        let text = "[\(fmt.string(from: Date()))] \(line)\n"
        try? FileManager.default.createDirectory(at: AppConfig.configDir, withIntermediateDirectories: true)
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        existing += text
        // 只保留最近 400 行
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > 400 {
            existing = lines.suffix(400).joined(separator: "\n") + "\n"
        }
        try? existing.write(to: url, atomically: true, encoding: .utf8)
    }
}
