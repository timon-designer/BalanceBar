import Cocoa

// MARK: - 设计常量（4px 网格，黑白灰，纯白背景）

enum D {
    static let white      = NSColor.white
    static let ink        = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    static let inkSoft    = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.45, alpha: 1)
    static let inkFaint   = NSColor(srgbRed: 0.62, green: 0.62, blue: 0.65, alpha: 1)
    static let line       = NSColor(srgbRed: 0.925, green: 0.925, blue: 0.933, alpha: 1)
    static let ok         = NSColor(srgbRed: 0.20, green: 0.65, blue: 0.35, alpha: 1)
    static let warn       = NSColor(srgbRed: 0.85, green: 0.55, blue: 0.10, alpha: 1)
    static let bad        = NSColor(srgbRed: 0.82, green: 0.24, blue: 0.22, alpha: 1)
    static let track      = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.975, alpha: 1)

    static let pad: CGFloat = 16
    static let panelWidth: CGFloat = 400
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
           color: NSColor = D.ink, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                  : NSFont.systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.alignment = .left
    l.lineBreakMode = .byTruncatingTail
    l.setContentHuggingPriority(.defaultLow, for: .horizontal)
    l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return l
}

/// 吸收剩余横向空间用的占位 view。hugging / compression 压到最低，
/// 保证所有余量都被它吃掉（否则多个同优先级的 view 会互相争抢，排版不确定）。
func spacer() -> NSView {
    let v = NSView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
    v.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
    return v
}

/// 1px 分隔线
func hairline(_ color: NSColor = D.line) -> NSBox {
    let b = NSBox()
    b.boxType = .custom
    b.borderType = .noBorder
    b.fillColor = color
    b.translatesAutoresizingMaskIntoConstraints = false
    b.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return b
}

/// 无边框文字按钮，hover 变深
final class TextButton: NSButton {
    private var hover = false { didSet { refresh() } }
    private let base: NSColor
    private let hoverColor: NSColor

    init(title: String, size: CGFloat = 11, color: NSColor = D.inkSoft, hover: NSColor = D.ink,
         target: AnyObject?, action: Selector) {
        self.base = color
        self.hoverColor = hover
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.bezelStyle = .inline
        self.focusRingType = .none
        self.setButtonType(.momentaryChange)
        self.font = NSFont.systemFont(ofSize: size, weight: .medium)
        self.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color
        ])
        self.setContentHuggingPriority(.required, for: .horizontal)
        self.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }

    private func refresh() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: font?.pointSize ?? 11, weight: .medium),
            .foregroundColor: hover ? hoverColor : base,
            .underlineStyle: hover ? NSUnderlineStyle.single.rawValue : 0
        ])
    }
}

// MARK: - 状态点

final class DotView: NSView {
    var color: NSColor = D.ok { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 6, height: 6) }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        // 必须画满 bounds：之前写成 y=2 会让圆被视图顶部裁掉，看起来像个小三角
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 6, height: 6)).fill()
    }
}

// MARK: - 峰谷标签

/// 峰时 / 非峰时标签。规格：高 16pt、左右内边距 4pt、圆角 4、1px 描边、白底（都在 4px 网格上）。
/// 只用黑白灰拉开层级：峰时（贵）描边与文字走近黑 + medium，非峰时（便宜）走浅灰 + regular，
/// 默认安静、需要留意时才压重，和面板里「余额偏低变黄」同一套「重 = 要注意」的逻辑。
final class PeakChip: NSView {
    private let text = NSTextField(labelWithString: "")
    private static let hPad: CGFloat = 4
    private static let height: CGFloat = 16

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.backgroundColor = D.white.cgColor

        text.translatesAutoresizingMaskIntoConstraints = false
        text.alignment = .left
        text.lineBreakMode = .byClipping
        text.setContentHuggingPriority(.required, for: .horizontal)
        text.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(text)

        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.height)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ s: PeakPricing.State) {
        text.stringValue = s.text
        text.font = NSFont.systemFont(ofSize: 10, weight: s.isPeak ? .medium : .regular)
        text.textColor = s.isPeak ? D.ink : D.inkFaint
        layer?.borderColor = (s.isPeak ? D.ink : D.line).cgColor
        toolTip = s.tooltip
        // 文案在两态间来回切（2 字 / 3 字），宽度要跟着重算
        invalidateIntrinsicContentSize()
    }

    /// 按当前时刻重算（渲染时调用，不缓存进 BalanceResult，避免过期）
    func refreshNow() { update(PeakPricing.state(at: PeakPricing.displayDate())) }
}

// MARK: - 单条行

final class ProviderRow: NSView {
    private let dot = DotView()
    private let nameLabel: NSTextField
    private let amountLabel: NSTextField
    private let detailLabel: NSTextField
    private let recharge: TextButton
    private let consoleButton: TextButton?
    private let peakChip: PeakChip?
    private var result: BalanceResult

    init(result: BalanceResult, target: AnyObject, rechargeAction: Selector, consoleAction: Selector) {
        self.result = result
        self.nameLabel = label(result.name, size: 13, weight: .medium)
        self.amountLabel = label(result.displayAmount, size: 13, weight: .semibold, mono: true)
        self.detailLabel = label("", size: 11, color: D.inkFaint)
        self.recharge = TextButton(title: "充值", target: target, action: rechargeAction)
        self.consoleButton = result.consoleURL == nil ? nil : TextButton(title: "控制台", target: target, action: consoleAction)
        self.peakChip = result.showsPeakPricing ? PeakChip() : nil
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
        apply()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // 第一行：状态点 + 名称 +（峰谷标签）……… 金额
        let top = NSStackView(views: [dot, nameLabel] + (peakChip.map { [$0] } ?? []) + [spacer(), amountLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8
        if peakChip != nil {
            top.setCustomSpacing(4, after: nameLabel)   // 标签贴着名称（4px 网格）
        }

        // 第二行：详情 ……… 操作
        let actions = NSStackView(views: [recharge] + (consoleButton.map { [$0] } ?? []))
        actions.orientation = .horizontal
        actions.spacing = 12
        let bottom = NSStackView(views: [detailLabel, spacer(), actions])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 8

        let stack = NSStackView(views: [top, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func apply() {
        // 峰谷标签每次渲染都按当前时刻重算：只要走到这里（网络刷新 / 打开面板 /
        // 设置页保存 / 时段切换定时器）就是一次对齐，不依赖刷新频率，也不会显示过期状态
        peakChip?.refreshNow()

        switch result.state {
        case .ok:       dot.color = result.isLow ? D.warn : D.ok
        case .linkOnly: dot.color = D.inkFaint
        case .needKey:  dot.color = D.warn
        case .error:    dot.color = D.bad
        }
        amountLabel.stringValue = result.displayAmount
        amountLabel.textColor = result.amount == nil ? D.inkFaint
            : (result.state == .ok ? (result.isLow ? D.warn : D.ink) : D.inkFaint)

        var detail = ""
        switch result.state {
        case .ok:       detail = result.detail ?? "已更新"
        case .linkOnly: detail = result.detail ?? "点开查看"
        case .needKey:  detail = result.error ?? "缺少 key"
        case .error:    detail = result.error ?? "获取失败"
        }
        // 副行（智谱 GLM 的资源包 token）已由 provider 用 Fmt.tokens 格式化好，
        // 这里直接渲染，面板不再自行换算
        if let sub = result.subLine { detail = sub }
        // 用量信息跟在详情后面（没有用量接口的平台 usage 为 nil，不渲染）
        if let usage = result.usage {
            detail += detail.isEmpty ? usage : " · " + usage
        }
        detailLabel.stringValue = detail
        detailLabel.textColor = (result.state == .error || result.state == .needKey
                                  || result.subLineHasError) ? D.bad : D.inkFaint
    }
}

// MARK: - 分页约定
// 面板是容器，列表页 / 设置页是子控制器，互相通过 host 切换。

protocol PaneHost: AnyObject {
    func relayout()
    func showListPane()
    func showSettingsPane()
}

protocol PaneDumpable: AnyObject {
    func debugDump() -> String
}

// MARK: - 列表页

final class ListPaneController: NSViewController, PaneDumpable {
    weak var host: PaneHost?

    private let store = BalanceStore.shared
    private let contentStack = NSStackView()
    private let summary = label("", size: 11, color: D.inkFaint)
    private let updated = label("", size: 11, color: D.inkFaint, mono: true)
    private var refreshButton: TextButton!

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: D.panelWidth, height: 200))
        root.wantsLayer = true
        root.layer?.backgroundColor = D.white.cgColor
        view = root

        // 头部
        let title = label("余额看板", size: 13, weight: .semibold)
        // 标题左侧挂应用标记（与 .icns 同一份「¥」几何，模板图自动适配明暗）
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = BalanceIcon.glyphImage(pt: 14)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14)
        ])
        refreshButton = TextButton(title: "刷新", target: self, action: #selector(doRefresh))
        let settingsButton = TextButton(title: "设置", target: self, action: #selector(openSettings))
        let header = NSStackView(views: [iconView, title, spacer(), updated, refreshButton, settingsButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.setCustomSpacing(4, after: iconView)   // 标记与标题贴紧（4px 网格）

        // 列表
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0

        // 底部
        let configButton = TextButton(title: "配置文件", target: self, action: #selector(openConfig))
        let quitButton = TextButton(title: "退出", target: self, action: #selector(quit))
        let footer = NSStackView(views: [summary, spacer(), configButton, quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        let sep1 = hairline(), sep2 = hairline()
        let outer = NSStackView(views: [header, sep1, contentStack, sep2, footer])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.setCustomSpacing(12, after: header)
        outer.setCustomSpacing(16, after: sep1)
        outer.setCustomSpacing(16, after: contentStack)
        outer.setCustomSpacing(12, after: sep2)
        root.addSubview(outer)

        let inset = D.pad
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            outer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            outer.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),
            outer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
            root.widthAnchor.constraint(equalToConstant: D.panelWidth),
            header.widthAnchor.constraint(equalTo: outer.widthAnchor),
            footer.widthAnchor.constraint(equalTo: outer.widthAnchor),
            contentStack.widthAnchor.constraint(equalTo: outer.widthAnchor),
            sep1.widthAnchor.constraint(equalTo: outer.widthAnchor),
            sep2.widthAnchor.constraint(equalTo: outer.widthAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 多观察者：面板和菜单栏各自订阅，不要改回单槽闭包
        store.observe(self) { [weak self] in self?.render() }
        render()
        store.refresh()
    }

    /// 无头验证用：把面板上所有文字导出来
    func debugDump() -> String { dumpText(from: view) }

    private func render() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        // 首次加载用骨架行撑住面板高度，避免「先小后大」跳动
        let list: [BalanceResult]
        if store.results.isEmpty {
            list = store.config.providers.filter { $0.enabled }.map {
                BalanceResult(id: $0.id, name: $0.name, detail: "读取中…",
                              rechargeURL: $0.rechargeURL, consoleURL: $0.consoleURL,
                              lowWarn: $0.lowWarn, state: .linkOnly,
                              showsPeakPricing: ProviderMeta.of($0.type)?.peakPricing ?? false)
            }
        } else {
            list = store.results
        }
        let rows = list.map { makeRow($0) }
        for (i, v) in rows.enumerated() {
            contentStack.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            if i > 0 { contentStack.setCustomSpacing(0, after: contentStack.arrangedSubviews[i - 1]) }
        }

        updated.stringValue = store.isRefreshing
            ? "更新中…"
            : (store.lastUpdate.map { fmtTime($0) } ?? "未更新")
        refreshButton.isEnabled = !store.isRefreshing
        summary.stringValue = store.results.isEmpty ? "" : store.summaryLine()
        host?.relayout()   // 高度由容器统一算，popover 认的是容器的 preferredContentSize
        Log.write("面板渲染 | results=\(store.results.count) | \(debugDump())")
    }

    private func makeRow(_ r: BalanceResult) -> NSView {
        let row = ProviderRow(result: r, target: self,
                              rechargeAction: #selector(doRecharge(_:)),
                              consoleAction: #selector(doConsole(_:)))
        row.identifier = NSUserInterfaceItemIdentifier(r.id)
        // 顶部分隔线
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let sep = hairline()
        wrap.addSubview(sep); wrap.addSubview(row)
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            sep.topAnchor.constraint(equalTo: wrap.topAnchor),
            row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            row.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 1),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
        ])
        return wrap
    }

    private func result(for sender: NSButton) -> BalanceResult? {
        guard let id = findRowID(from: sender) else { return nil }
        return store.results.first { $0.id == id }
    }

    private func findRowID(from view: NSView) -> String? {
        var v: NSView? = view
        while let cur = v {
            if let id = cur.identifier?.rawValue, BalanceStore.shared.results.contains(where: { $0.id == id }) {
                return id
            }
            v = cur.superview
        }
        return nil
    }

    @objc private func doRefresh() { store.refresh() }

    @objc private func doRecharge(_ sender: NSButton) {
        guard let r = result(for: sender), let s = r.rechargeURL, let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
        NotificationCenter.default.post(name: .init("balancebar.closePanel"), object: nil)
    }

    @objc private func doConsole(_ sender: NSButton) {
        guard let r = result(for: sender), let s = r.consoleURL, let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
        NotificationCenter.default.post(name: .init("balancebar.closePanel"), object: nil)
    }

    @objc private func openSettings() { host?.showSettingsPane() }

    @objc private func openConfig() { store.openConfigFile() }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - 面板容器（列表页 ⇄ 设置页）

final class PanelViewController: NSViewController, PaneHost {
    private lazy var listPane = ListPaneController()
    private(set) lazy var settingsPane = SettingsPaneController()   // 无头自检要直接取输入框
    private var current: NSViewController?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: D.panelWidth, height: 200))
        root.wantsLayer = true
        root.layer?.backgroundColor = D.white.cgColor
        view = root
        showListPane()
    }

    /// NSPopover 只认 preferredContentSize，切页 / 数据变化后都要重算。
    /// 直接量「当前子页」的 fittingSize —— 容器自身的 fittingSize 会被
    /// preferredContentSize 反写回的 frame 污染，切回列表页时会卡在上一页的高度。
    func relayout() {
        guard isViewLoaded else { return }
        view.layoutSubtreeIfNeeded()
        let size = current?.view.fittingSize ?? view.fittingSize
        preferredContentSize = NSSize(width: max(size.width, D.panelWidth), height: size.height)
    }

    /// 无头验证用：当前 popover 会取到的尺寸
    func debugSize() -> NSSize { preferredContentSize }

    func debugLayoutState() -> String {
        let subs = view.subviews.map { "\(type(of: $0)) h=\(Int($0.fittingSize.height))" }.joined(separator: " | ")
        return "preferred=\(preferredContentSize) 当前页=\(current === settingsPane ? "设置" : "列表") "
            + "容器子视图=[\(subs)] 列表页高=\(Int(listPane.view.fittingSize.height)) "
            + "设置页高=\(Int(settingsPane.view.fittingSize.height))"
    }

    func showListPane() {
        let pane = listPane
        pane.host = self
        swap(to: pane, prepare: nil)
    }

    func showSettingsPane() {
        let pane = settingsPane
        pane.host = self
        swap(to: pane) { pane.refreshFromConfig() }
    }

    private func swap(to vc: NSViewController, prepare: (() -> Void)?) {
        _ = vc.view                       // 触发 loadView
        prepare?()
        if current !== vc {
            current?.view.removeFromSuperview()
            current?.removeFromParent()
            addChild(vc)
            let cv = vc.view
            cv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(cv)
            NSLayoutConstraint.activate([
                cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                cv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                cv.topAnchor.constraint(equalTo: view.topAnchor),
                cv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            current = vc
        }
        relayout()
        DispatchQueue.main.async { [weak self] in self?.relayout() }
    }

    // MARK: 无头验证入口

    func debugDump() -> String { (current as? PaneDumpable)?.debugDump() ?? "(空)" }

    func settingsMetrics() -> String {
        _ = settingsPane.view
        return settingsPane.debugMetrics()
    }

    func debugShowSettings() {
        showSettingsPane()
        view.layoutSubtreeIfNeeded()
    }

    func debugShowList() {
        showListPane()
        view.layoutSubtreeIfNeeded()
    }
}

func fmtTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}
