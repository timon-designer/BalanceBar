import Cocoa

// ── 无界面自检模式：./BalanceBar --probe
// 直接打印各平台余额与用量，用于命令行验证 / 排查接口
if CommandLine.arguments.contains("--probe") {
    let cfg = AppConfig.load()
    let sem = DispatchSemaphore(value: 0)
    let only = CommandLine.arguments.firstIndex(of: "--only").flatMap { i -> String? in
        CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : nil
    }
    Task {
        var lines: [String] = []
        for p in cfg.providers where p.enabled && (only == nil || p.id == only) {
            let r = await Providers.fetch(p)
            let state: String
            switch r.state {
            case .ok: state = "OK"
            case .linkOnly: state = "LINK"
            case .needKey: state = "NO_KEY"
            case .error: state = "ERR"
            }
            let extra = r.detail ?? r.error ?? ""
            lines.append(String(format: "%-12@ %-8@ %10@ %-4@ %@",
                                r.id as NSString, state as NSString,
                                r.displayAmount as NSString, (r.currency ?? "") as NSString,
                                extra as NSString))
            // 副行：智谱 GLM 的资源包 token（现金余额 + token 两行都要能看到）
            if let note = r.tokenNote { lines.append("             副行: \(note)") }
            if let u = r.usage { lines.append("             用量: \(u)") }
            // 峰谷定价平台（DeepSeek）：标签值按当前时刻算，与接口数据无关
            if r.showsPeakPricing { lines.append("             峰谷: \(PeakPricing.summary(at: Date()))") }
            if let u = r.rechargeURL, !u.isEmpty { lines.append("             充值: \(u)") }
        }
        print(lines.joined(separator: "\n"))
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// ── 无界面菜单自检：./BalanceBar --menu-test
// 验证主菜单已建立、⌘V 等键等价物已注册（没有主菜单，设置页就粘不进 key）
if CommandLine.arguments.contains("--menu-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    AppMenus.install()
    var lines: [String] = []
    for top in NSApp.mainMenu?.items ?? [] {
        guard let sub = top.submenu else { continue }
        for it in sub.items {
            if it.isSeparatorItem { lines.append("[\(sub.title)] ──"); continue }
            let m = it.keyEquivalentModifierMask
            var keys = ""
            if m.contains(.control) { keys += "⌃" }
            if m.contains(.option) { keys += "⌥" }
            // 大写 keyEquivalent 本身就代表 ⇧（AppKit 约定），别在显示时丢了
            if m.contains(.shift) || (it.keyEquivalent.first?.isUppercase == true) { keys += "⇧" }
            if m.contains(.command) { keys += "⌘" }
            let key = it.keyEquivalent.isEmpty ? "—" : keys + it.keyEquivalent.uppercased()
            lines.append(String(format: "[%@] %-14@ 快捷键 %@", sub.title, it.title as NSString, key as NSString))
        }
    }
    let hasPaste = lines.contains { $0.contains("粘贴") && $0.contains("⌘V") }
    let hasCopy = lines.contains { $0.contains("拷贝") && $0.contains("⌘C") }
    let hasQuit = lines.contains { $0.contains("退出") && $0.contains("⌘Q") }
    let ok = hasPaste && hasCopy && hasQuit
    lines.append(ok ? "MENU-TEST PASS（粘贴 ⌘V / 拷贝 ⌘C / 退出 ⌘Q 已注册）" : "MENU-TEST FAIL")
    print(lines.joined(separator: "\n"))
    exit(ok ? 0 : 1)
}

// ── 无界面写盘自检：./BalanceBar --env-test
// 在临时文件上验证 writeEnv 的 upsert 与落盘权限，不碰任何真实配置
if CommandLine.arguments.contains("--env-test") {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("balancebar-env-test-\(UUID().uuidString)/.env")
    KeyStore.writeEnv(["DEEPSEEK_API_KEY": "sk-old", "KEEP_ME": "1"], to: tmp)
    let first = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
    KeyStore.writeEnv(["DEEPSEEK_API_KEY": "sk-new", "GLM_API_KEY": "new-key"], to: tmp)
    let second = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
    let parsed = KeyStore.parseEnvFile(tmp)
    let perms = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.posixPermissions]) as? Int
    print("── 首次写入\n\(first)")
    print("── upsert 后（注释与 KEEP_ME 必须还在，DEEPSEEK 必须被替换）\n\(second)")
    print("── 解析结果: \(parsed.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
    print("── 落盘权限: \(perms.map { String(format: "%o", $0) } ?? "未知")（期望 600）")
    let ok = parsed["DEEPSEEK_API_KEY"] == "sk-new"
        && parsed["GLM_API_KEY"] == "new-key"
        && parsed["KEEP_ME"] == "1"
        && second.contains("# BalanceBar")
        && perms == 0o600
    print(ok ? "ENV-TEST PASS" : "ENV-TEST FAIL")
    try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())
    exit(ok ? 0 : 1)
}

// ── 无界面保存链路自检：./BalanceBar --settings-save-test
// 真实走一遍「设置页字段 → collect → ConfigWriter.save → 读回 config.json」，
// 改的是 DeepSeek 的低余额阈值；跑完立刻恢复原文件字节，不留下任何改动
if CommandLine.arguments.contains("--settings-save-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let vc = PanelViewController()
    _ = vc.view
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        let url = AppConfig.configURL
        let original = try? Data(contentsOf: url)
        vc.debugShowSettings()
        guard let shell = vc.settingsPane.debugExtraShell(key: "lowWarn") else {
            print("SAVE-TEST FAIL：找不到低余额阈值输入框")
            exit(1)
        }
        shell.field.stringValue = "7"
        let (msg, count, warns) = vc.settingsPane.debugCollectAndSave()
        print("保存返回: \(msg) | 平台=\(count) 警告=\(warns)")
        // 读回磁盘上的配置，确认阈值已生效
        KeyStore.reload()
        let reloaded = AppConfig.load()
        let lw = reloaded.providers.first(where: { $0.type == "deepseek" })?.lowWarn
        print("读回 deepseek.lowWarn: \(lw.map { String(describing: $0) } ?? "nil")（期望 7.0）")
        // 恢复原文件
        if let original {
            try? original.write(to: url)
            print("已恢复原 config.json（\(original.count) 字节）")
        }
        let ok = lw == 7
        print(ok ? "SAVE-TEST PASS" : "SAVE-TEST FAIL")
        exit(ok ? 0 : 1)
    }
    app.run()
}

// ── 无界面 UI 自检：./BalanceBar --ui-test
// 真实构建面板并强制布局，按序 dump 列表页 → 设置页（含白名单断言）→ 回列表页，
// 最后走一遍真实粘贴链路（假 key 经 粘贴⌘V 的 action 分发打进设置页密文框）
if CommandLine.arguments.contains("--ui-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    AppMenus.install()
    let vc = PanelViewController()
    _ = vc.view
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        vc.view.layoutSubtreeIfNeeded()
        print("UI 列表页 首帧 | size=\(vc.debugSize()) | \(vc.debugDump())")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
        vc.view.layoutSubtreeIfNeeded()
        let listDump = vc.debugDump()
        print("UI 列表页 刷新后 | size=\(vc.debugSize()) | \(listDump)")

        // ── 智谱双行断言：智谱区块必须同时出现「现金 ¥ 行」与「token 缩写行」
        let tokenHit = listDump.range(of: #"glm-5\.3-flash\s+[\d.]+[mk]"#, options: .regularExpression) != nil
        let cashHit = listDump.range(of: #"¥\d+\.\d{2}"#, options: .regularExpression) != nil
        print("UI 智谱双行 | 现金行=\(cashHit) token行=\(tokenHit) → \(cashHit && tokenHit ? "ZHIPU-2LINE PASS" : "ZHIPU-2LINE FAIL")")

        // ── 峰谷标签断言：DeepSeek 行必须挂上「峰时 / 非峰时」，且全列表只有一个
        //    「非峰时」含「峰时」子串，所以统计"独立峰时"必须用负向后顾排除「非峰时」
        let offPeakCount = listDump.components(separatedBy: "非峰时").count - 1
        let peakOnly = try? NSRegularExpression(pattern: "(?<!非)峰时")
        let peakOnlyCount = peakOnly?.numberOfMatches(
            in: listDump, range: NSRange(listDump.startIndex..<listDump.endIndex, in: listDump)) ?? 0
        let chipCount = offPeakCount + peakOnlyCount
        let chipText = offPeakCount > 0 ? "非峰时" : (peakOnlyCount > 0 ? "峰时" : "无")
        print("UI 峰谷标签 | deepseek 标签数=\(chipCount) 文案=\(chipText) → \(chipCount == 1 ? "PEAK-CHIP PASS" : "PEAK-CHIP FAIL")")

        // ── 图标断言：面板头部必须挂上 14pt 的应用标记（模板图）
        func findHeaderIcon(_ v: NSView) -> NSImageView? {
            if let iv = v as? NSImageView, iv.image != nil, iv.image!.isTemplate,
               abs(iv.image!.size.width - 14) < 0.5 { return iv }
            for sub in v.subviews { if let hit = findHeaderIcon(sub) { return hit } }
            return nil
        }
        let headerIcon = findHeaderIcon(vc.view)
        print("UI 头部图标 | 找到=\(headerIcon != nil) 尺寸=\(headerIcon.map { "\($0.image!.size)" } ?? "无") → \(headerIcon != nil ? "ICON-VIEW PASS" : "ICON-VIEW FAIL")")

        vc.debugShowSettings()
        print("UI 设置页 | size=\(vc.debugSize()) | \(vc.settingsMetrics())")
        let settingsDump = vc.debugDump()
        print("UI 设置页字段 | \(settingsDump)")

        // ── 白名单断言：设置页只能有 deepseek/zhipu/aliyun/mimo 四个区块；
        //    下架平台与 AccessKey 行不得出现；aliyun/mimo 只渲染「控制台」入口
        let banned = ["moonshot", "siliconflow", "openrouter", "relay", "AccessKey", "中转站"]
            .filter { settingsDump.contains($0) }
        let hasMimo = settingsDump.contains("mimo")
        let consoleCount = settingsDump.components(separatedBy: "控制台").count - 1
        let wlOK = banned.isEmpty && hasMimo && consoleCount >= 2
        print("UI 设置页白名单 | 违规=\(banned.isEmpty ? "无" : banned.joined(separator: ",")) mimo=\(hasMimo) 控制台行=\(consoleCount) → \(wlOK ? "WHITELIST-TEST PASS" : "WHITELIST-TEST FAIL")")

        vc.debugShowList()
        print("UI 回到列表页 | size=\(vc.debugSize()) | \(vc.debugLayoutState())")
        print("UI 回到列表页 字段 | \(vc.debugDump())")

        // ── 真实粘贴链路：把面板装进真窗口 → 聚焦密文框 → 假 key 上剪贴板 →
        //    用「粘贴 ⌘V 注册的那个 action」走 responder chain 分发 → 断言字段非空
        let fake = "sk-paste-\(UUID().uuidString.prefix(8))"
        let win = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: D.panelWidth, height: 700),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .aqua)
        vc.debugShowSettings()
        win.contentView = vc.view
        win.makeKeyAndOrderFront(nil)
        if let shell = vc.settingsPane.debugApiKeyShell() {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            win.makeKey()
            let becameFR = win.makeFirstResponder(shell.field)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fake, forType: .string)
            // 和「粘贴 ⌘V」菜单项同一条分发路径：nil target → keyWindow → firstResponder
            let sel = #selector(NSText.paste(_:))
            var delivered = NSApp.sendAction(sel, to: nil, from: nil)
            var route = "keyWindow 链"
            if !delivered {
                // 无头环境里 borderless 窗口可能成不了 key window，兜底：同一个 action
                // 直接递给字段编辑器（responder chain 里真正处理粘贴的就是它）
                delivered = NSApp.sendAction(sel, to: win.firstResponder, from: nil)
                route = "直递 firstResponder"
            }
            let len = shell.field.stringValue.count
            let secure = shell.field is NSSecureTextField
            let ok = delivered && secure && len > 0
            print("UI 粘贴链路 | winKey=\(win.isKeyWindow) firstResponder=\(win.firstResponder.map { "\(type(of: $0))" } ?? "nil") makeFR=\(becameFR) 路径=\(route)")
            print("UI 粘贴链路 | paste: 分发=\(delivered) 密文框=\(secure) 字段长度=\(len) → \(ok ? "PASTE-TEST PASS" : "PASTE-TEST FAIL")")
        } else {
            print("UI 粘贴链路 | 找不到 API Key 输入框 → PASTE-TEST FAIL")
            exit(1)
        }
        exit(0)
    }
    app.run()
}

// ── 截图链路诊断：./BalanceBar --capture-test
// 起真实 StatusBarController 并打开面板（popover），打印面板窗口的层级 / 共享类型 /
// CGWindowList 可见性，保持打开若干秒供外部 screencapture 实测，退出前汇报面板是否还开着。
if CommandLine.arguments.contains("--capture-test") {
    setbuf(stdout, nil)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    AppMenus.install()
    let c = StatusBarController()
    c.start()

    func dumpPanel(_ tag: String) {
        guard let w = c.debugPanelWindow else {
            print("CAPTURE [\(tag)] 面板窗口=nil（popover.isShown=\(c.debugIsShown)）")
            return
        }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = info.filter { ($0["kCGWindowOwnerPID"] as? Int) == Int(ProcessInfo.processInfo.processIdentifier) }
        let listed = mine.contains { ($0["kCGWindowNumber"] as? Int) == w.windowNumber }
        print("CAPTURE [\(tag)] winNumber=\(w.windowNumber) sharing=\(w.sharingType.rawValue) level=\(w.level.rawValue) visible=\(w.isVisible) key=\(w.isKeyWindow) hidesOnDeactivate=\(w.hidesOnDeactivate) 在屏CGList=\(listed) frame=\(w.frame)")
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        c.showPopover()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
        dumpPanel("打开后")
    }
    // T+6s / T+9s：留给外部脚本在这两个点跑 screencapture（-x 全屏 与 -l 窗口），之后再查面板状态
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
        dumpPanel("全屏截图后")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
        dumpPanel("窗口截图后")
        print("CAPTURE 最终 | popover.isShown=\(c.debugIsShown)")
        exit(0)
    }
    app.run()
}

// ── 面板外点击收起自检：./BalanceBar --outside-click-test
// 真实打开面板，直接驱动全局监听的判定函数：
//   A 单击空白 → 面板收起    B 拖拽（截图框选路径）→ 面板不收
//   C 遮罩判定：level≥1000 遮罩 / 系统截图会话 → 判定为截图，不参与收起
if CommandLine.arguments.contains("--outside-click-test") {
    setbuf(stdout, nil)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    AppMenus.install()
    let c = StatusBarController()
    c.start()

    let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
    let p = CGPoint(x: screen.midX, y: screen.midY)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.showPopover() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        print("OUTSIDE-CLICK A0 | 打开面板 isShown=\(c.debugIsShown)（应 true）")
        // A：单击空白（down 与 up 同一点）→ 收起
        c.handleOutsideMouseDown(at: p)
        c.handleOutsideMouseUp(at: p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let a = c.debugIsShown == false
            print("OUTSIDE-CLICK A | 单击空白后 isShown=\(c.debugIsShown) → \(a ? "PASS" : "FAIL")")

            // B：拖拽（模拟截图框选）→ 不收
            c.showPopover()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                c.handleOutsideMouseDown(at: p)
                c.handleOutsideMouseUp(at: CGPoint(x: p.x + 80, y: p.y + 40))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let b = c.debugIsShown == true
                    print("OUTSIDE-CLICK B | 拖拽(80,40)后 isShown=\(c.debugIsShown) → \(b ? "PASS" : "FAIL")")

                    // C：遮罩判定（合成 Quartz 窗口表，不依赖机器上真实在跑什么）
                    let overlayList: [[String: Any]] = [
                        ["kCGWindowOwnerPID": 99999, "kCGWindowLayer": 1000,
                         "kCGWindowBounds": ["X": 0.0, "Y": 0.0, "Width": 3000.0, "Height": 2000.0]]
                    ]
                    let normalList: [[String: Any]] = [
                        ["kCGWindowOwnerPID": 99999, "kCGWindowLayer": 0,
                         "kCGWindowBounds": ["X": 0.0, "Y": 0.0, "Width": 3000.0, "Height": 2000.0]]
                    ]
                    let c1 = StatusBarController.hitsScreenshotOverlay(point: p, myPID: 1, frontBundle: "com.tencent.xinWeChat", windowList: overlayList, primaryHeight: 2000)
                    let c2 = StatusBarController.hitsScreenshotOverlay(point: p, myPID: 1, frontBundle: "com.apple.finder", windowList: normalList, primaryHeight: 2000)
                    let c3 = StatusBarController.hitsScreenshotOverlay(point: p, myPID: 1, frontBundle: "com.apple.screencaptureui", windowList: [], primaryHeight: 2000)
                    let c4 = StatusBarController.hitsScreenshotOverlay(point: p, myPID: 99999, frontBundle: "com.tencent.xinWeChat", windowList: overlayList, primaryHeight: 2000)
                    let cOK = c1 && !c2 && c3 && !c4
                    print("OUTSIDE-CLICK C | 遮罩命中=\(c1) 普通窗=\(!c2) 系统截图会话=\(c3) 自家窗排除=\(!c4) → \(cOK ? "PASS" : "FAIL")")

                    let ok = a && b && cOK
                    print(ok ? "OUTSIDE-CLICK-TEST PASS" : "OUTSIDE-CLICK-TEST FAIL")
                    exit(ok ? 0 : 1)
                }
            }
        }
    }
    app.run()
}

// ── 成图预览：./BalanceBar --preview [settings|list]
// 把面板放进一个无边框真窗口（强制浅色外观），供 screencapture -l<windowNumber> 出图。
if CommandLine.arguments.contains("--preview") {
    setbuf(stdout, nil)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    AppMenus.install()
    let idx = CommandLine.arguments.firstIndex(of: "--preview")
    let pane = (idx.flatMap { CommandLine.arguments.count > $0 + 1 ? CommandLine.arguments[$0 + 1] : nil }) ?? "settings"

    // 可选：把峰谷标签定格到某个时刻出图，例如 --peak-now "2026-10-14 10:00"（峰时）
    if let i = CommandLine.arguments.firstIndex(of: "--peak-now"), CommandLine.arguments.count > i + 1 {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = PeakPricing.calendar
        f.timeZone = PeakPricing.calendar.timeZone
        if let d = f.date(from: CommandLine.arguments[i + 1]) {
            PeakPricing.frozenNow = d
            print("PREVIEW_PEAK_NOW \(PeakPricing.summary(at: d))")
        }
    }

    let vc = PanelViewController()
    _ = vc.view
    if pane == "list" { vc.debugShowList() } else { vc.debugShowSettings() }
    vc.view.layoutSubtreeIfNeeded()

    let h = max(vc.preferredContentSize.height, 120)
    let w = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: D.panelWidth, height: h),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .aqua)   // 面板恒为浅色，不跟随系统深色
    w.backgroundColor = D.white
    w.isOpaque = true
    w.hasShadow = false
    w.contentViewController = vc
    w.setFrameTopLeftPoint(NSPoint(x: 80, y: (NSScreen.main?.frame.maxY ?? 900) - 60))
    w.makeKeyAndOrderFront(nil)
    w.contentView?.layoutSubtreeIfNeeded()

    print("PREVIEW_PANE \(pane)")
    print("PREVIEW_WINDOW \(w.windowNumber)")
    print("PREVIEW_FRAME \(w.frame)")
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { exit(0) }
    app.run()
}

// ── 图标导出：./BalanceBar --export-icon <输出目录>
// 生成 <目录>/AppIcon.iconset 的 10 个尺寸 PNG（由 make-icon.sh 调 iconutil 打成 .icns）
if CommandLine.arguments.contains("--export-icon") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let idx = CommandLine.arguments.firstIndex(of: "--export-icon")!
    guard CommandLine.arguments.count > idx + 1 else {
        print("用法：BalanceBar --export-icon <输出目录>")
        exit(1)
    }
    let out = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
    let set = out.appendingPathComponent("AppIcon.iconset")
    do {
        let files = try BalanceIcon.exportIconSet(to: set)
        for f in files { print("  \(set.appendingPathComponent(f).path)") }
        print("ICON-EXPORT OK（\(files.count) 个尺寸 → \(set.path)）")
        exit(0)
    } catch {
        print("ICON-EXPORT FAIL：\(error.localizedDescription)")
        exit(1)
    }
}

// ── 峰谷时段自检：./BalanceBar --peak-test
// 纯规则断言（不起 UI、不发请求）。所有时刻按北京时间构造，不允许依赖机器时区。
// 期望周几一并断言：如果日期算错了，测试会直接指出来，而不是悄悄给个"通过"。
if CommandLine.arguments.contains("--peak-test") {
    func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = PeakPricing.calendar
        f.timeZone = PeakPricing.calendar.timeZone
        return f.date(from: s)!
    }
    func weekday(_ d: Date) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][PeakPricing.calendar.component(.weekday, from: d) - 1]
    }

    // (时刻, 期望周几, 期望是否峰时, 备注)
    let cases: [(String, String, Bool, String)] = [
        // ── 窗口边界（工作日，左闭右开）
        ("2026-10-14 08:59", "三", false, "09:00 前一分钟"),
        ("2026-10-14 09:00", "三", true,  "峰时起点"),
        ("2026-10-14 11:59", "三", true,  "午间窗口末尾"),
        ("2026-10-14 12:00", "三", false, "12:00 整即转谷时"),
        ("2026-10-14 13:59", "三", false, "14:00 前一分钟"),
        ("2026-10-14 14:00", "三", true,  "下午峰时起点"),
        ("2026-10-14 17:59", "三", true,  "18:00 前一分钟"),
        ("2026-10-14 18:00", "三", false, "18:00 整即转谷时"),
        ("2026-10-14 23:30", "三", false, "夜间"),
        ("2026-10-14 00:10", "三", false, "凌晨"),
        // ── 普通工作日 vs 周末
        ("2026-10-12 10:00", "一", true,  "周一上午"),
        ("2026-10-16 15:00", "五", true,  "周五下午"),
        ("2026-10-10 10:00", "六", false, "周六（且是国庆调休上班日，官方口径仍算谷时）"),
        ("2026-10-11 15:00", "日", false, "周日下午"),
        // ── 法定节假日整天谷时（国办发明电〔2025〕7号）
        ("2026-01-01 10:00", "四", false, "元旦"),
        ("2026-02-20 15:00", "五", false, "春节（9 天假期中段）"),
        ("2026-04-06 10:00", "一", false, "清明节最后一天"),
        ("2026-05-04 10:00", "一", false, "劳动节"),
        ("2026-06-19 10:00", "五", false, "端午节首日"),
        ("2026-09-25 10:00", "五", false, "中秋节首日"),
        ("2026-10-01 10:00", "四", false, "国庆节首日"),
        ("2026-10-07 15:00", "三", false, "国庆节末日（周三，平时这个点是峰时）"),
        // ── 节假日边界：前后一天要回到正常规则
        ("2026-09-24 10:00", "四", true,  "中秋前一天（工作日，正常峰时）"),
        ("2026-09-28 10:00", "一", true,  "中秋后一天（工作日，正常峰时）"),
        ("2026-10-08 10:00", "四", true,  "国庆后第一天"),
        ("2026-04-03 10:00", "五", true,  "清明前一天"),
        ("2026-02-14 10:00", "六", false, "春节调休上班的周六"),
        ("2026-02-24 10:00", "二", true,  "春节假期后第一天")
    ]
    var bad: [String] = []
    var badDay: [String] = []
    for (t, wantDay, wantPeak, note) in cases {
        let d = at(t)
        if weekday(d) != wantDay { badDay.append("\(t) 实际周\(weekday(d))，用了周\(wantDay)") }
        let got = PeakPricing.isPeak(d)
        if got != wantPeak { bad.append("\(t) → \(got ? "峰时" : "非峰时")，期望 \(wantPeak ? "峰时" : "非峰时")（\(note)）") }
    }
    print("PEAK-TEST | 峰谷判定 \(cases.count) 例 → \(bad.isEmpty ? "全部符合" : "不符：\n  " + bad.joined(separator: "\n  "))")
    if !badDay.isEmpty {
        print("PEAK-TEST | ⚠️ 用例日期与标注的星期不符（测试数据本身有问题）：\n  " + badDay.joined(separator: "\n  "))
    }

    // ── 下一次切换时刻
    let nextCases: [(String, String, String)] = [
        ("2026-10-14 08:30", "2026-10-14 09:00", "当天入峰"),
        ("2026-10-14 12:30", "2026-10-14 14:00", "午休后入峰"),
        ("2026-10-14 18:30", "2026-10-15 09:00", "收工后跨夜到次日 09:00"),
        ("2026-10-16 18:30", "2026-10-19 09:00", "周五收工 → 跳过整个周末到周一 09:00"),
        ("2026-10-10 10:00", "2026-10-12 09:00", "周六 → 周一 09:00"),
        ("2026-10-07 15:00", "2026-10-08 09:00", "国庆末日 → 节后首个工作日 09:00"),
        ("2026-10-14 23:30", "2026-10-15 09:00", "跨过 00:00（状态未变，不算切换）")
    ]
    var badNext: [String] = []
    for (from, want, note) in nextCases {
        let got = PeakPricing.nextChange(after: at(from))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = PeakPricing.calendar
        f.timeZone = PeakPricing.calendar.timeZone
        let gotStr = f.string(from: got)
        if gotStr != want { badNext.append("\(from) → \(gotStr)，期望 \(want)（\(note)）") }
    }
    print("PEAK-TEST | 下次切换 \(nextCases.count) 例 → \(badNext.isEmpty ? "全部符合" : "不符：\n  " + badNext.joined(separator: "\n  "))")

    // ── 文案与实时状态
    let now = Date()
    let s = PeakPricing.state(at: now)
    print("PEAK-TEST | 当前（\(PeakPricing.clock(now))）= \(s.text)")
    print("PEAK-TEST | 提示 =\n" + s.tooltip.split(separator: "\n").map { "           " + $0 }.joined(separator: "\n"))
    print("PEAK-TEST | 摘要 = \(PeakPricing.summary(at: now))")
    let textOK = (s.text == "峰时" || s.text == "非峰时") && s.text == (s.isPeak ? "峰时" : "非峰时")
    if !textOK { bad.append("标签文案=\(s.text) 与判定 \(s.isPeak) 不一致") }

    let ok = bad.isEmpty && badDay.isEmpty && badNext.isEmpty && textOK
    print(ok ? "PEAK-TEST PASS" : "PEAK-TEST FAIL")
    exit(ok ? 0 : 1)
}

// ── 时段切换的更新链路自检：./BalanceBar --peak-switch-test
// 起真实列表页，把标签定格到谷时 → store.notify() → 再定格到峰时 → store.notify()，
// 断言标签跟着翻。notify() 正是峰谷定时器到点走的那条路径，
// 所以这条用例覆盖「定时器 → notify → render → chip 按当前时刻重算」的完整链路。
if CommandLine.arguments.contains("--peak-switch-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    AppMenus.install()

    func freeze(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = PeakPricing.calendar
        f.timeZone = PeakPricing.calendar.timeZone
        PeakPricing.frozenNow = f.date(from: s)
    }
    func chipText(_ dump: String) -> String {
        if dump.contains("非峰时") { return "非峰时" }
        if dump.range(of: "(?<!非)峰时", options: .regularExpression) != nil { return "峰时" }
        return "无"
    }

    freeze("2026-10-14 22:00")   // 周三 22:00 → 谷时
    let vc = PanelViewController()
    _ = vc.view
    vc.debugShowList()
    vc.view.layoutSubtreeIfNeeded()
    let before = chipText(vc.debugDump())
    print("PEAK-SWITCH | 定格周三 22:00（谷时）→ 标签=\(before)")

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        freeze("2026-10-14 10:00")   // 周三 10:00 → 峰时
        BalanceStore.shared.notify()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let after = chipText(vc.debugDump())
            print("PEAK-SWITCH | 定格周三 10:00（峰时）+ notify() → 标签=\(after)")

            // 反向再切一次，确认是双向的、不是单向粘住
            freeze("2026-10-17 09:00")   // 周六 09:00 → 谷时
            BalanceStore.shared.notify()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let back = chipText(vc.debugDump())
                print("PEAK-SWITCH | 定格周六 09:00（周末谷时）+ notify() → 标签=\(back)")
                PeakPricing.frozenNow = nil   // 别把定格状态漏给后面的流程
                let ok = before == "非峰时" && after == "峰时" && back == "非峰时"
                print(ok ? "PEAK-SWITCH PASS（切换时 notify 即可刷新标签，无需重新请求接口）"
                         : "PEAK-SWITCH FAIL（期望 非峰时 → 峰时 → 非峰时，实际 \(before) → \(after) → \(back)）")
                exit(ok ? 0 : 1)
            }
        }
    }
    app.run()
}

// ── 图标自检：./BalanceBar --icon-test
// 断言 .icns 已被 Info.plist 引用且真实存在于 bundle、App 能解析出图标、
// 面板头部的模板小标记可用（从 .app 内运行才有意义）。
// 菜单栏不再挂标记，那条不变式改由 --statusbar-test 断言。
if CommandLine.arguments.contains("--icon-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let info = Bundle.main.infoDictionary ?? [:]
    let declared = (info["CFBundleIconFile"] as? String) ?? "(未声明)"
    let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
    let exists = icnsURL != nil
    var icnsSizes = "—"
    if let u = icnsURL,
       let img = NSImage(contentsOf: u) {
        icnsSizes = img.representations
            .map { "\(Int($0.pixelsWide))x\(Int($0.pixelsHigh))" }
            .sorted().joined(separator: ",")
    }
    let appIcon = NSApp.applicationIconImage
    let appIconOK = (appIcon?.size.width ?? 0) > 0
    let bundlePath = Bundle.main.bundlePath
    let runFromApp = bundlePath.hasSuffix(".app")

    let glyph = BalanceIcon.glyphImage(pt: 14)
    let glyphOK = glyph.isTemplate && glyph.size.width == 14 && !glyph.representations.isEmpty
    let glyphBig = BalanceIcon.glyphImage(pt: 18)
    let glyphBigOK = glyphBig.isTemplate && glyphBig.size.width == 18

    print("ICON-TEST | 运行位置=\(bundlePath)")
    print("ICON-TEST | CFBundleIconFile=\(declared) 文件存在=\(exists) (\(icnsURL?.lastPathComponent ?? "无"))")
    print("ICON-TEST | .icns 内含尺寸=\(icnsSizes)")
    print("ICON-TEST | applicationIconImage=\(appIconOK ? "\(appIcon!.size)" : "nil")")
    print("ICON-TEST | 模板小标记 14pt=\(glyphOK) 18pt=\(glyphBigOK)")

    // 系统解析比对：NSWorkspace 走的就是 Finder 那条取图标的路。
    // 把系统给这张 .app 的图标与自绘图标缩到 64×64 逐像素比，确认不是系统兜底的通用图标。
    var sysDiff = 255.0
    var sysSize = "nil"
    let wsIcon: NSImage? = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    if let wsIcon {
        sysSize = "\(wsIcon.size)"
        let mine = NSImage(size: NSSize(width: 512, height: 512))
        mine.addRepresentation(BalanceIcon.raster(size: 512) { S in BalanceIcon.drawAppIcon(S) })
        sysDiff = BalanceIcon.meanPixelDiff(wsIcon, mine)
    }
    let sysOK = sysDiff < 12
    print("ICON-TEST | 系统解析图标=\(sysSize) 与自绘像素差=\(String(format: "%.2f", sysDiff))/255 → \(sysOK ? "一致" : "不一致（可能仍是通用图标）")")

    // 可选：把系统解析出的图标落成 PNG（肉眼复核 Finder / 可执行文件位置实际显示的图）
    if let i = CommandLine.arguments.firstIndex(of: "--icon-test"),
       CommandLine.arguments.count > i + 1 {
        let wsIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        let rep = BalanceIcon.raster(size: 512) { S in
            wsIcon.draw(in: NSRect(x: 0, y: 0, width: S, height: S),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: out)
            print("ICON-TEST | 系统解析图标已落盘：\(out.path)")
        }
    }

    let ok = runFromApp && declared == "AppIcon" && exists && appIconOK && glyphOK && glyphBigOK && sysOK
    print(ok ? "ICON-TEST PASS" : "ICON-TEST FAIL（需从 /Applications/余额看板.app 内运行）")
    exit(ok ? 0 : 1)
}

// ── 状态栏自检：./BalanceBar --statusbar-test
// 断言菜单栏状态项「只有金额文字、没有图标」，且文字原样来自 statusTitle()
// （带 ¥ 符号、不出现「¥¥」、刷新后确实变成真实金额）
if CommandLine.arguments.contains("--statusbar-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let controller = StatusBarController()
    controller.start()
    var bad: [String] = []

    guard let button = controller.debugStatusButton else {
        print("STATUSBAR-TEST FAIL（拿不到状态项按钮）")
        exit(1)
    }
    if button.image != nil { bad.append("首帧仍挂着图标") }
    print("STATUSBAR-TEST | 首帧 标题=「\(button.title)」 图标=\(button.image == nil ? "无" : "有")")

    // 等真实刷新回来，再断言显示的是余额本身而不是占位文案
    DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
        let expected = BalanceStore.shared.statusTitle()
        let title = button.title
        if button.image != nil { bad.append("刷新后仍挂着图标 \(button.image!.size)") }
        if button.imagePosition != .noImage { bad.append("imagePosition=\(button.imagePosition.rawValue)（0 才是 noImage）") }
        if title != expected { bad.append("标题「\(title)」≠ statusTitle()「\(expected)」") }
        if title.hasPrefix("¥¥") { bad.append("货币符号重复：「\(title)」") }
        if title.isEmpty { bad.append("标题为空（应回落到「余额」/「—」）") }

        print("STATUSBAR-TEST | 刷新后 标题=「\(title)」 statusTitle()=「\(expected)」 图标=\(button.image == nil ? "无" : "有") imagePosition=\(button.imagePosition.rawValue)")
        print("STATUSBAR-TEST | 头部件 14pt 标记仍可用=\(BalanceIcon.glyphImage(pt: 14).isTemplate)（面板头部不受影响）")
        let ok = bad.isEmpty
        print(ok ? "STATUSBAR-TEST PASS（顶部状态栏只显示金额、无图标）" : "STATUSBAR-TEST FAIL：" + bad.joined(separator: " / "))
        exit(ok ? 0 : 1)
    }
    app.run()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// 单实例保护：LaunchAgent 与手动启动并存时会重复出现菜单栏图标
if !CommandLine.arguments.contains("--probe"),
   !CommandLine.arguments.contains("--ui-test"),
   !CommandLine.arguments.contains("--menu-test"),
   !CommandLine.arguments.contains("--capture-test"),
   !CommandLine.arguments.contains("--outside-click-test"),
   !CommandLine.arguments.contains("--settings-save-test"),
   !CommandLine.arguments.contains("--peak-test"),
   !CommandLine.arguments.contains("--peak-switch-test"),
   !CommandLine.arguments.contains("--statusbar-test"),
   !CommandLine.arguments.contains("--icon-test"),
   NSRunningApplication.runningApplications(withBundleIdentifier: "com.timon.balancebar").count > 1 {
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
