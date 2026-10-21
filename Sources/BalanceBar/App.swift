import Cocoa

// MARK: - 主菜单
// LSUIElement 菜单栏 App 不显示主菜单，但 ⌘C/⌘V/⌘A/⌘X/⌘Z/⌘Q 是靠菜单项的
// keyEquivalent 分发的：没有 NSApp.mainMenu 就没有分发目标，设置页里 ⌘V 完全无效。
// 这个菜单永远不显示，纯粹用来承载键等价物；action 全部为 nil target，
// 由 AppKit 沿 responder chain 交给 first responder（输入框的字段编辑器）。

enum AppMenus {
    static func install() {
        let main = NSMenu()

        // 应用菜单（⌘Q 退出）
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "余额看板")
        appMenu.addItem(withTitle: "关于余额看板",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出余额看板",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // 编辑菜单（⌘V 粘贴就在这里）
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        // keyEquivalent 用大写字母即代表 ⌘⇧
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}

/// 无边框窗口默认不能成为 key window，粘贴的 action 分发需要 keyWindow，
/// 所以测试/预览用这个子类。
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppConfig.load()   // 首次运行写出默认配置
        AppMenus.install()     // 没有 it ⌘V/⌘C/⌘A/⌘Q 全部失效
        KeyStore.enforcePermissions()   // 顺手把旧的 644 凭据文件收紧
        let c = StatusBarController()
        c.start()
        controller = c
    }

    // 菜单栏应用无窗口，双击 App 时把面板叫回来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showPopover()
        return true
    }
}

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store = BalanceStore.shared
    private var timer: Timer?
    /// 峰谷时段切换用的一次性定时器（与网络刷新定时器无关）
    private var peakTimer: Timer?
    /// Esc 关闭面板的事件监听（behavior 改为 .applicationDefined 后需要手动收口）
    private var escMonitor: Any?
    /// 全局点击监听：面板开着时，单击面板外空白 → 收起（补回原生 popover 手感）
    private var outsideClickMonitor: Any?
    /// 面板外 mouseDown 的落点（nil = 这个 down 不参与收起判定，比如落在截图遮罩上）
    private var outsideDownPoint: CGPoint?
    /// 「单击空白」判定阈值（点）：小于它视为点击空白收起，大于等于视为拖拽/框选
    private static let outsideClickThreshold: CGFloat = 3

    func start() {
        popover.contentViewController = PanelViewController()
        // .applicationDefined：AppKit 不再自动收面板（transient 会在任何外部交互时关掉）。
        // 之前用 .transient，截图工具一激活（⌘⇧4 / 微信截图）面板就被 AppKit 自动收掉，
        // 用户永远截不到面板内容。退出路径：点面板外空白 / 再点一次状态栏 / 按 Esc /
        // 跳转充值页控制台时主动关 —— 「点外收起」由下面的全局监听负责。
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.appearance = NSAppearance(named: .aqua)

        // Esc 关闭：本地事件监听，仅在本 App 是 active app 时收到事件
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.popover.isShown == true {
                self?.closePanel()
                return nil   // 吞掉事件，避免面板里其它控件再处理
            }
            return event
        }

        // 「点面板外空白收起」：全局监听其它 App 收到的左键事件。
        // 三重防误触，保证「面板打开时可以截图」不被破坏：
        //   ① mouseUp 才判定 + 位移阈值 —— 截图框选是拖拽（位移大），不会收起面板；
        //   ② 点击点落在截图/录屏工具的全屏遮罩（窗口 level ≥ 1000）上时不参与判定；
        //   ③ 系统截图会话（screencaptureui 前台）期间不参与判定。
        // 自家窗口（面板、状态项）的事件不会进全局监听，天然不误触。
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, self.popover.isShown else { return }
            let loc = NSEvent.mouseLocation   // 全局监听回调里取全局坐标最稳
            switch event.type {
            case .leftMouseDown: self.handleOutsideMouseDown(at: loc)
            case .leftMouseUp:   self.handleOutsideMouseUp(at: loc)
            default: break
            }
        }

        if let button = statusItem.button {
            button.title = "余额"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            // 状态项只显示金额文字，不挂图标：标记本身就是「¥」，会和标题里的 ¥ 叠成「¥¥5.95」
            button.image = nil
            button.imagePosition = .noImage
        }

        store.observe(self) { [weak self] in self?.updateTitle() }
        updateTitle()
        store.refresh()

        // 定时自动刷新
        scheduleTimer()
        // 峰谷时段切换：不跟网络刷新周期走，直接排到真正的切换时刻
        schedulePeakTimer()
        // 配置变化时重排定时器
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.scheduleTimer()
            self?.schedulePeakTimer()
        }
        // 设置页保存后立刻应用新的刷新间隔
        NotificationCenter.default.addObserver(forName: .init("balancebar.configSaved"),
                                               object: nil, queue: .main) { [weak self] _ in
            self?.scheduleTimer()
        }
        // 点「充值」「控制台」跳转浏览器后主动收起面板
        NotificationCenter.default.addObserver(forName: .init("balancebar.closePanel"),
                                               object: nil, queue: .main) { [weak self] _ in
            self?.closePanel()
        }
    }

    // MARK: - 面板外点击收起

    /// 统一收口：所有主动关闭路径都走这里，顺带清掉进行中的外点判定
    private func closePanel() {
        outsideDownPoint = nil
        popover.performClose(nil)
    }

    /// 全局监听回调：面板外左键按下
    func handleOutsideMouseDown(at loc: CGPoint) {
        outsideDownPoint = isScreenshotOverlayClick(at: loc) ? nil : loc
    }

    /// 全局监听回调：面板外左键抬起 —— 位移小于阈值视为「单击空白」→ 收起面板；
    /// 有位移（截图框选、拖窗口、划词选中）不收，保证截图等交互不被打扰
    func handleOutsideMouseUp(at loc: CGPoint) {
        guard let down = outsideDownPoint else { return }
        outsideDownPoint = nil
        let dist = hypot(loc.x - down.x, loc.y - down.y)
        guard dist < Self.outsideClickThreshold else {
            Log.write("面板 | 面板外拖拽（位移 \(String(format: "%.1f", dist))pt）→ 不收起")
            return
        }
        Log.write("面板 | 单击面板外空白（位移 \(String(format: "%.1f", dist))pt）→ 收起")
        closePanel()
    }

    /// 这个点击是否落在截图/录屏工具的全屏遮罩上，或系统截图会话正在进行 ——
    /// 是则不参与「点外收起」（上一轮修复「面板打开时可以截图」的配套防线）。
    func isScreenshotOverlayClick(at point: CGPoint) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        return Self.hitsScreenshotOverlay(point: point,
                                          myPID: Int(ProcessInfo.processInfo.processIdentifier),
                                          frontBundle: front,
                                          windowList: list,
                                          primaryHeight: primaryHeight)
    }

    /// 纯判定（可测）：按 Quartz 窗口列表从前往后找点击点命中的第一扇「别人家的窗」，
    /// 命中 level ≥ 1000 的遮罩层（微信截图 / SnipShot 遮罩 / 系统截图 UI 都在这个量级）
    /// 判定为截图遮罩；系统截图进程前台时直接判定为截图会话。
    static func hitsScreenshotOverlay(point: CGPoint, myPID: Int, frontBundle: String?,
                                      windowList: [[String: Any]], primaryHeight: CGFloat) -> Bool {
        if let frontBundle,
           frontBundle.contains("screencapture") || frontBundle.contains("screenshot") {
            return true
        }
        for w in windowList {
            guard let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.intValue, pid != myPID,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let x = (b["X"] as? NSNumber)?.doubleValue,
                  let y = (b["Y"] as? NSNumber)?.doubleValue,
                  let wd = (b["Width"] as? NSNumber)?.doubleValue,
                  let ht = (b["Height"] as? NSNumber)?.doubleValue
            else { continue }
            // Quartz 窗口 bounds 是主屏左上原点、y 向下；转成 NSScreen 的左下原点坐标
            let rect = CGRect(x: x, y: primaryHeight - y - ht, width: wd, height: ht)
            if rect.contains(point) {
                return layer >= 1000
            }
        }
        return false
    }

    deinit {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(60, store.config.refreshSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
    }

    /// 峰谷切换定时器：一次性排到下一个「状态真的会变」的时刻（09:00 / 12:00 / 14:00 / 18:00
    /// 或跨日），到点只做 `notify()`（不发网络请求），让面板行与菜单栏按新时刻重算标签，排下一次。
    /// 定时器只是「准时」的保障，不是正确性的依赖：任何一次渲染都会用当前时刻重算，
    /// 所以休眠错过定时器、或系统延迟触发，下一帧自然会对齐。
    private func schedulePeakTimer() {
        peakTimer?.invalidate()
        let next = PeakPricing.nextChange(after: Date())
        let delay = max(1, next.timeIntervalSinceNow)
        peakTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Log.write("峰谷切换 | \(PeakPricing.summary(at: Date()))")
            self.store.notify()
            self.schedulePeakTimer()
        }
    }

    /// 状态项只显示金额文字（原样来自 statusTitle()，自带 ¥ 符号），不挂任何图标。
    /// 面板头部与 App 图标的标记不受影响，仍走 BalanceIcon。
    private func updateTitle() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.title = store.statusTitle()
    }

    /// 无头自检用：暴露状态项按钮（同 PanelViewController 的 debug* 约定）
    var debugStatusButton: NSStatusBarButton? { statusItem.button }

    /// 无头自检用：popover 的宿主窗口（screencapture / 层级诊断用）
    var debugPanelWindow: NSWindow? { popover.contentViewController?.view.window }

    var debugIsShown: Bool { popover.isShown }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        store.refresh()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePanel()
        } else {
            showPopover()
        }
    }
}
