import Cocoa

// MARK: - DeepSeek 峰谷定价（全项目唯一判定出口）
//
// 规则来源（2026-10-08 核对）：
//   ① 官方价目表脚注 2 —— api-docs.deepseek.com/quick_start/pricing
//      "Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday,
//       excluding Chinese public holidays. All other hours are off-peak,
//       including weekends and Chinese public holidays in full."
//      谷时价 = 峰时价的一半。
//   ② 国务院办公厅关于 2026 年部分节假日安排的通知（国办发明电〔2025〕7号，2025-11-04）
//      —— 法定节假日日期表见下方 holidays。
//
// 换算成北京时间（UTC+8）：峰时 = 工作日 09:00–12:00、14:00–18:00。
// 区间取**左闭右开**：09:00 起算峰时，12:00 整即转谷时；14:00 起算，18:00 整转谷时。
//
// 两点刻意的口径选择（都与官方字面一致，别凭感觉改）：
// - 调休假期的**周六/周日按谷时**：官方写的是 Monday through Friday，且明确
//   "including weekends"。所以 2/14、2/28、5/9、10/10 这类调休上班的周六仍是谷时。
// - 法定节假日**整天**谷时，不只是落在工作日的那几天。

enum PeakPricing {

    /// 判定用的时区：北京时间。中国大陆无夏令时，固定 +8，不会出现跳变。
    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }()

    /// 仅 `--preview` 用：把标签"定格"到某个时刻，好在任意时间出峰时/非峰时两种成图。
    /// 生产路径恒为 nil（走真实 `Date()`），判定函数本身始终接收显式时刻，保持纯函数。
    static var frozenNow: Date? = nil

    static func displayDate() -> Date { frozenNow ?? Date() }

    /// 峰时窗口（北京时间，左闭右开）
    static let windows: [(startHour: Int, endHour: Int)] = [(9, 12), (14, 18)]

    /// 法定节假日（按年分组，"MM-dd"）。**每年国务院发通知后更新这里**，
    /// 缺失的年份不报错，只是不再豁免节假日（周末仍照常按谷时）。
    static let holidays: [Int: Set<String>] = [
        // 国办发明电〔2025〕7号
        2026: [
            "01-01", "01-02", "01-03",                                     // 元旦
            "02-15", "02-16", "02-17", "02-18", "02-19", "02-20",
            "02-21", "02-22", "02-23",                                     // 春节
            "04-04", "04-05", "04-06",                                     // 清明节
            "05-01", "05-02", "05-03", "05-04", "05-05",                   // 劳动节
            "06-19", "06-20", "06-21",                                     // 端午节
            "09-25", "09-26", "09-27",                                     // 中秋节
            "10-01", "10-02", "10-03", "10-04", "10-05", "10-06", "10-07"  // 国庆节
        ]
    ]

    // MARK: 判定

    static func isHoliday(_ date: Date) -> Bool {
        let c = calendar
        let comp = c.dateComponents([.year, .month, .day], from: date)
        guard let y = comp.year, let m = comp.month, let d = comp.day else { return false }
        return holidays[y]?.contains(String(format: "%02d-%02d", m, d)) ?? false
    }

    static func isWeekend(_ date: Date) -> Bool {
        let wd = calendar.component(.weekday, from: date)
        return wd == 1 || wd == 7     // 1 = 周日，7 = 周六
    }

    static func isPeak(_ date: Date) -> Bool {
        if isWeekend(date) || isHoliday(date) { return false }
        let comp = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (comp.hour ?? 0) * 60 + (comp.minute ?? 0)
        return windows.contains { w in
            minutes >= w.startHour * 60 && minutes < w.endHour * 60
        }
    }

    /// 为什么当前是谷时 —— 用于 tooltip，让「周末」「节假日」这类豁免可追溯
    static func offPeakReason(_ date: Date) -> String? {
        if isHoliday(date) { return "法定节假日" }
        if isWeekend(date) { return "周末" }
        return nil
    }

    // MARK: 展示

    /// 标签文案 + 提示（面板 chip 与 --probe 共用，避免两处各写一套）
    struct State {
        var isPeak: Bool
        /// 标签文案：峰时 / 非峰时
        var text: String
        /// 鼠标悬停提示：时段规则 + 下次切换时刻
        var tooltip: String
    }

    static func state(at date: Date) -> State {
        state(at: date, nextChange: nextChange(after: date))
    }

    static func state(at date: Date, nextChange: Date) -> State {
        let peak = isPeak(date)
        let text = peak ? "峰时" : "非峰时"
        var tip: [String] = []
        if peak {
            tip.append("高峰时段：工作日 09:00–12:00、14:00–18:00（北京时间）")
            tip.append("当前按高峰价计费")
        } else {
            tip.append("低谷时段：非高峰时段、周末、法定节假日全天")
            tip.append("当前按低谷价计费（高峰价的一半）")
            if let why = offPeakReason(date) { tip.append("今天原因：\(why)") }
        }
        tip.append("下次切换：" + clock(nextChange))
        return State(isPeak: peak, text: text, tooltip: tip.joined(separator: "\n"))
    }

    /// 一行摘要，给 --probe 用
    static func summary(at date: Date) -> String {
        let s = state(at: date)
        let next = nextChange(after: date)
        let rule = "工作日 09:00–12:00 / 14:00–18:00 为峰时"
        return "\(s.text)（\(rule)）· 下次切换 \(clock(next))"
    }

    static func clock(_ date: Date) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute, .weekday], from: date)
        let hour = String(format: "%02d", c.hour ?? 0)
        let minute = String(format: "%02d", c.minute ?? 0)
        let wd = ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, (c.weekday ?? 1) - 1))]
        return "\(c.month ?? 0)/\(c.day ?? 0)（周\(wd)）\(hour):\(minute)"
    }

    // MARK: 下一次切换时刻

    /// 下一个「状态真的会变」的时刻。候选点只可能是：每天 00:00（跨日改变周末/节假日属性）
    /// 以及各窗口的起止（09:00 / 12:00 / 14:00 / 18:00）。
    /// 向后扫描 15 天足以跨过任意一个周末 + 连着周末的长假。
    static func nextChange(after date: Date) -> Date {
        let c = calendar
        let current = isPeak(date)
        let day0 = c.startOfDay(for: date)
        let candidates: [(Int, Int)] = [(0, 0), (9, 0), (12, 0), (14, 0), (18, 0)]
        for offset in 0...15 {
            guard let day = c.date(byAdding: .day, value: offset, to: day0) else { break }
            for (h, m) in candidates {
                guard let t = c.date(bySettingHour: h, minute: m, second: 0, of: day) else { continue }
                if t > date && isPeak(t) != current { return t }
            }
        }
        return date.addingTimeInterval(12 * 3600)   // 理论到不了，兜底
    }
}
