import Cocoa

// MARK: - 输入外壳
// NSTextField 没有内边距 API：用外壳做 padding / 圆角 / 描边，
// 内部 field 关闭所有系统装饰（isBordered=false / drawsBackground=false）。

enum FieldStyle {
    case box        // 有描边框（普通字段）
    case underline  // 只有一条下划线（名称字段，避免一堆框）
}

final class FieldShell: NSView, NSTextFieldDelegate {
    let field: NSTextField
    private let style: FieldStyle
    private var line: NSBox?
    private var focused = false { didSet { paint() } }

    init(placeholder: String, secure: Bool = false, value: String = "",
         style: FieldStyle = .box) {
        self.style = style
        self.field = secure ? NSSecureTextField() : NSTextField()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 740), for: .horizontal)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = D.ink
        field.stringValue = value
        field.delegate = self
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: D.inkFaint
        ])
        addSubview(field)

        switch style {
        case .box:
            layer?.cornerRadius = 4
            layer?.borderWidth = 1
            layer?.backgroundColor = D.white.cgColor
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 28),
                field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        case .underline:
            let l = hairline()
            addSubview(l)
            line = l
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 24),
                l.leadingAnchor.constraint(equalTo: leadingAnchor),
                l.trailingAnchor.constraint(equalTo: trailingAnchor),
                l.bottomAnchor.constraint(equalTo: bottomAnchor),
                field.leadingAnchor.constraint(equalTo: leadingAnchor),
                field.trailingAnchor.constraint(equalTo: trailingAnchor),
                field.topAnchor.constraint(equalTo: topAnchor),
                field.bottomAnchor.constraint(equalTo: l.topAnchor, constant: -4)
            ])
        }
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    var value: String { field.stringValue.trimmed }
    var hasText: Bool { !value.isEmpty }

    /// 点外壳的空白处也能聚焦到输入框
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }

    /// 右键菜单兜底（鼠标党不一定知道 ⌘V）；action 走 nil target，
    /// 由 responder chain 交给当前字段编辑器
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu(title: "编辑")
        m.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        m.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        m.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        m.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return m
    }

    func controlTextDidBeginEditing(_ obj: Notification) { focused = true }
    func controlTextDidEndEditing(_ obj: Notification) { focused = false }

    private func paint() {
        switch style {
        case .box:
            layer?.borderColor = (focused ? D.ink : D.line).cgColor
        case .underline:
            line?.fillColor = focused ? D.ink : D.line
        }
    }
}

// MARK: - 主按钮（保存用，纯黑白灰）

final class PrimaryButton: NSButton {
    private var hover = false { didSet { paint() } }

    init(title: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let w = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 40
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: max(w, 88)),
            heightAnchor.constraint(equalToConstant: 28)
        ])
        paint()
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

    private func paint() {
        layer?.backgroundColor = (hover ? D.inkSoft : D.ink).cgColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: D.white
        ])
    }
}

// MARK: - 单个平台区块

/// 勾选框（NSButton 没有可读的 buttonType，单独开个子类给 dump 认）
final class CheckboxButton: NSButton {}

final class ProviderSectionView: NSView {
    let source: ProviderConfig
    let meta: ProviderMeta
    let enableBox = CheckboxButton()
    var nameShell: FieldShell!
    var apiShell: FieldShell?
    var baseShell: FieldShell?
    var rechargeShell: FieldShell?
    var consoleShell: FieldShell!
    /// 额外参数（meta.extras 渲染出来的），key → 输入外壳
    var extraShells: [String: FieldShell] = [:]

    private static let labelWidth: CGFloat = 88
    private static let nameWidth: CGFloat = 200
    private static let badgeWidth: CGFloat = 68

    init(config: ProviderConfig, isLast: Bool) {
        self.source = config
        self.meta = ProviderMeta.of(config.type)
            ?? ProviderMeta(label: config.type, needsKey: false, needsBaseURL: false)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(isLast: isLast)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 组装（字段全部按 meta 表派生，不写按 type 的分支）

    private func build(isLast: Bool) {
        // ── 首行：[启用] 类型 名称…………
        enableBox.setButtonType(.switch)
        enableBox.title = ""
        enableBox.imagePosition = .imageOnly
        enableBox.controlSize = .small
        enableBox.focusRingType = .none
        enableBox.state = source.enabled ? .on : .off
        enableBox.identifier = NSUserInterfaceItemIdentifier("enable:\(source.id)")
        enableBox.toolTip = meta.label + "｜启用后才会查询并显示在列表里"

        let badge = label(source.type, size: 11, color: D.inkFaint)
        badge.widthAnchor.constraint(equalToConstant: Self.badgeWidth).isActive = true

        nameShell = FieldShell(placeholder: "名称", value: source.name, style: .underline)
        nameShell.widthAnchor.constraint(equalToConstant: Self.nameWidth).isActive = true

        let top = NSStackView(views: [enableBox, badge, nameShell, spacer()])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8

        var rows: [NSView] = [top]

        if meta.consoleOnly {
            // ── 入口型平台（阿里云百炼 / 小米 MiMo）：只保留「控制台」一行
            consoleShell = FieldShell(placeholder: "https://…（可留空）", value: source.consoleURL ?? "")
            rows.append(row("控制台", consoleShell))
        } else {
            // ── API Key（密文，留空 = 不改）
            if meta.needsKey {
                let env = source.apiKeyEnv?.nonEmpty ?? Self.envName(from: source.id)
                let ph = KeyStore.has(env: env) ? "已配置（\(env)）· 留空不改" : "粘贴 \(env)"
                let shell = FieldShell(placeholder: ph, secure: true)
                apiShell = shell
                rows.append(row("API Key", shell))
            }

            // ── 站点地址
            if meta.needsBaseURL {
                let ph = meta.basePlaceholder ?? "https://接口根地址"
                let shell = FieldShell(placeholder: ph, value: source.baseURL ?? "")
                baseShell = shell
                rows.append(row("站点地址", shell))
            }

            // ── 额外参数（凭据走 env 判断，普通参数回填 config 值）
            for e in meta.extras {
                let shell: FieldShell
                if let env = e.envName {
                    let ph = KeyStore.has(env: env) ? "已配置（\(env)）· 留空不改" : e.placeholder
                    shell = FieldShell(placeholder: ph, secure: e.secure)
                } else {
                    shell = FieldShell(placeholder: e.placeholder, secure: e.secure,
                                       value: source.value(forKey: e.key) ?? "")
                }
                extraShells[e.key] = shell
                rows.append(row(e.label, shell))
            }

            // ── 充值页 / 控制台
            rechargeShell = FieldShell(placeholder: "https://…（可留空）", value: source.rechargeURL ?? "")
            consoleShell = FieldShell(placeholder: "https://…（可留空）", value: source.consoleURL ?? "")
            rows.append(row("充值页", rechargeShell!))
            rows.append(row("控制台", consoleShell))
        }

        // ── 竖排
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for r in rows {
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16)
        ])

        // ── 区块之间的 1px 分隔线
        let line = hairline()
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: isLast ? 0 : 1)
        ])
        if isLast { line.isHidden = true }
    }

    private func row(_ title: String, _ shell: FieldShell) -> NSView {
        let l = label(title, size: 11, color: D.inkSoft)
        l.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        let s = NSStackView(views: [l, shell])
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = 8
        return s
    }

    // MARK: 取值

    /// 返回（更新后的配置，需要写进 .env 的密文）
    func collect() -> (ProviderConfig, [String: String]) {
        var p = source
        p.enabled = enableBox.state == .on
        let nm = nameShell.value
        if !nm.isEmpty { p.name = nm }

        // 留空 → 保留原地址（防止手滑把默认站点清空；要禁用平台请取消勾选）
        p.baseURL = normURL(baseShell?.value ?? "", fallback: source.baseURL ?? "")
        p.rechargeURL = normURL(rechargeShell?.value ?? "", fallback: source.rechargeURL ?? "")
        p.consoleURL = normURL(consoleShell.value, fallback: source.consoleURL ?? "")

        var secrets: [String: String] = [:]
        if meta.needsKey, let api = apiShell, api.hasText {
            let env = p.apiKeyEnv?.nonEmpty ?? Self.envName(from: p.id)
            p.apiKeyEnv = env
            secrets[env] = api.value
        }
        for e in meta.extras {
            guard let shell = extraShells[e.key] else { continue }
            let v = shell.value
            if let env = e.envName {
                if !v.isEmpty { secrets[env] = v }      // 凭据：留空 = 不改
            } else {
                p.setValue(v.isEmpty ? nil : v, forKey: e.key)   // 普通参数：留空 = 恢复默认
            }
        }
        return (p, secrets)
    }

    private func normURL(_ v: String, fallback: String) -> String {
        let t = v.trimmed
        if t.isEmpty { return fallback }
        if t.contains("://") { return t }
        return "https://" + t
    }

    static func envName(from id: String) -> String {
        let body = id.uppercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "_"
        }
        return String(body) + "_API_KEY"
    }
}

// MARK: - 设置页

final class SettingsPaneController: NSViewController, PaneDumpable {
    weak var host: PaneHost?

    private let store = BalanceStore.shared
    private let sectionsStack = NSStackView()
    private let scroll = NSScrollView()
    private var scrollHeight: NSLayoutConstraint!
    private let statusLabel = label("", size: 11, color: D.inkFaint)
    private var sections: [ProviderSectionView] = []
    private var draft: [ProviderConfig] = []
    // 通用设置（刷新间隔 / 菜单栏标题）
    var refreshShell: FieldShell!
    var menuTitleShell: FieldShell!

    private static let hintText = "key 只写入本机 ~/.balancebar/.env，不会上传"

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: D.panelWidth, height: 400))
        root.wantsLayer = true
        root.layer?.backgroundColor = D.white.cgColor
        view = root

        // ── 头部
        let title = label("设置", size: 13, weight: .semibold)
        let back = TextButton(title: "返回", target: self, action: #selector(goBack))
        let header = NSStackView(views: [title, spacer(), back])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        // ── 滚动区（documentView 必须是翻转坐标容器，否则内容从底部排）
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .leading
        sectionsStack.spacing = 0
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(sectionsStack)
        scroll.documentView = doc

        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            sectionsStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            sectionsStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            sectionsStack.topAnchor.constraint(equalTo: doc.topAnchor),
            sectionsStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor)
        ])

        // ── 底部
        statusLabel.stringValue = Self.hintText
        let save = PrimaryButton(title: "保存并刷新", target: self, action: #selector(doSave))
        let buttons = NSStackView(views: [spacer(), save])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        let footer = NSStackView(views: [statusLabel, buttons])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 8

        let sep1 = hairline(), sep2 = hairline()
        let outer = NSStackView(views: [header, sep1, scroll, sep2, footer])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.setCustomSpacing(12, after: header)
        outer.setCustomSpacing(16, after: sep1)
        outer.setCustomSpacing(16, after: scroll)
        outer.setCustomSpacing(12, after: sep2)
        root.addSubview(outer)

        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 160)
        scrollHeight.isActive = true

        let inset = D.pad
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            outer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            outer.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),
            outer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
            root.widthAnchor.constraint(equalToConstant: D.panelWidth),
            header.widthAnchor.constraint(equalTo: outer.widthAnchor),
            footer.widthAnchor.constraint(equalTo: outer.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: footer.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: footer.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: outer.widthAnchor),
            sep1.widthAnchor.constraint(equalTo: outer.widthAnchor),
            sep2.widthAnchor.constraint(equalTo: outer.widthAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildSections()
    }

    // MARK: 区块构建

    func refreshFromConfig() {
        draft = store.config.providers
        rebuildSections()
        statusLabel.stringValue = Self.hintText
        statusLabel.textColor = D.inkFaint
    }

    private func rebuildSections() {
        sectionsStack.arrangedSubviews.forEach {
            sectionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        sections = []

        // ── 通用区块（刷新间隔 / 菜单栏标题）
        let general = buildGeneralSection()
        sectionsStack.addArrangedSubview(general)
        general.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true

        // ── 平台区块：按白名单顺序渲染（白名单外的旧条目保存时自动清除）
        for type in ProviderMeta.settingsWhitelist {
            let p = draft.first(where: { $0.type == type }) ?? Self.fallbackProvider(type)
            let s = ProviderSectionView(config: p, isLast: type == ProviderMeta.settingsWhitelist.last)
            sections.append(s)
            sectionsStack.addArrangedSubview(s)
            s.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true
        }
        layoutScroll()
        Log.write("设置页渲染 | 区块=\(sections.count) | 滚动内容高=\(Int(sectionsStack.fittingSize.height))")
    }

    /// 配置里缺某个白名单平台时补一个默认条目（如旧配置没有 mimo）
    private static func fallbackProvider(_ type: String) -> ProviderConfig {
        let defaults: [String: ProviderConfig] = [
            "mimo": ProviderConfig(
                id: "mimo", name: "小米 MiMo", type: "mimo", enabled: true,
                consoleURL: "https://platform.xiaomimimo.com/console/balance",
                note: "MiMo API 开放平台，无公开余额接口，点开控制台查看用量与余额"
            ),
            "aliyun": ProviderConfig(
                id: "bailian", name: "阿里云百炼", type: "aliyun", enabled: false,
                consoleURL: "https://bailian.console.aliyun.com/",
                note: "无按 key 的公开余额接口，点开控制台查看"
            )
        ]
        if let d = defaults[type] { return d }
        return ProviderConfig(id: type, name: ProviderMeta.of(type)?.label ?? type,
                              type: type, enabled: false)
    }

    /// 顶部「通用」区块：刷新间隔 + 菜单栏标题（全局配置，不属于任何平台）
    private func buildGeneralSection() -> NSView {
        let title = label("通用", size: 13, weight: .semibold)
        let top = NSStackView(views: [title, spacer()])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8

        refreshShell = FieldShell(placeholder: "秒，默认 600（最低 60）",
                                  value: ProviderConfig.numStr(store.config.refreshSeconds))
        let r1 = generalRow("刷新间隔(秒)", refreshShell)
        menuTitleShell = FieldShell(placeholder: "auto / total / min / 平台id",
                                    value: store.config.menuTitle)
        let r2 = generalRow("菜单栏标题", menuTitleShell)

        let stack = NSStackView(views: [top, r1, r2])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        let line = hairline()
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 16),
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            line.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor),
            r1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            r2.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return wrap
    }

    private func generalRow(_ title: String, _ shell: FieldShell) -> NSView {
        let l = label(title, size: 11, color: D.inkSoft)
        l.widthAnchor.constraint(equalToConstant: 88).isActive = true
        let s = NSStackView(views: [l, shell])
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = 8
        return s
    }

    /// 滚动区高度 = min(内容高度, 520)，并让 popover 重新自适应
    private func layoutScroll() {
        view.layoutSubtreeIfNeeded()
        let natural = sectionsStack.fittingSize.height
        scrollHeight.constant = min(max(natural, 96), 520)
        view.layoutSubtreeIfNeeded()
        host?.relayout()
    }

    func debugMetrics() -> String {
        "区块=\(sections.count) 内容高=\(Int(sectionsStack.fittingSize.height)) 滚动高=\(Int(scrollHeight.constant)) 面板=\(view.fittingSize)"
    }

    /// 无头验证：导出设置页所有文字 / 占位符 / 勾选状态
    func debugDump() -> String { dumpText(from: view) }

    // MARK: 动作

    @objc private func goBack() { host?.showListPane() }

    @objc private func doSave() {
        let (message, _, warnings) = saveNow()
        if warnings.isEmpty {
            statusLabel.stringValue = "\(message) · 正在刷新…"
            statusLabel.textColor = D.inkFaint
            rebuildSections()
            host?.showListPane()
        } else {
            // 有需要补的信息就留在设置页，别让提示被切页吞掉
            rebuildSections()
            statusLabel.stringValue = "\(message) · 还差：" + warnings.joined(separator: "、")
            statusLabel.textColor = D.warn
        }
    }

    /// 收集界面字段 → 写 config.json + .env → 重载 → 刷新
    private func saveNow() -> (message: String, providers: [ProviderConfig], warnings: [String]) {
        var cfg = store.config
        var warnings: [String] = []

        // ── 通用设置
        if let v = refreshShell?.value.nonEmpty {
            if let d = Double(v), d >= 30 {
                cfg.refreshSeconds = d
            } else {
                warnings.append("刷新间隔要填数字（秒，最低 30）")
            }
        }
        if let t = menuTitleShell?.value.trimmed.nonEmpty { cfg.menuTitle = t }

        // ── 各平台
        var providers: [ProviderConfig] = []
        var secrets: [String: String] = [:]
        for s in sections {
            let (p, sec) = s.collect()
            providers.append(p)
            secrets.merge(sec) { _, new in new }
        }
        cfg.providers = providers

        let message = ConfigWriter.save(config: cfg, secrets: secrets)

        for p in providers where p.enabled && (p.baseURL?.trimmed.isEmpty ?? true) {
            if let m = ProviderMeta.of(p.type), m.needsBaseURL {
                warnings.append("「\(p.name)」没填站点地址")
            }
        }
        for p in providers where p.enabled && p.apiKeyEnv?.nonEmpty != nil && !KeyStore.has(env: p.apiKeyEnv) {
            warnings.append("「\(p.name)」还没填 key")
        }

        store.reloadConfig()
        NotificationCenter.default.post(name: .init("balancebar.configSaved"), object: nil)
        if warnings.isEmpty { store.refresh() }
        return (message, providers, warnings)
    }

    // MARK: 无头验证辅助

    func debugApiKeyShell() -> FieldShell? {
        sections.first(where: { $0.meta.needsKey })?.apiShell
    }

    func debugExtraShell(key: String) -> FieldShell? {
        sections.first(where: { $0.extraShells[key] != nil })?.extraShells[key]
    }

    /// 无头验证用：按当前界面字段真实写盘（调用方负责恢复原文件），返回（提示, 平台数, 警告数）
    func debugCollectAndSave() -> (String, Int, Int) {
        let r = saveNow()
        return (r.message, r.providers.count, r.warnings.count)
    }
}

// MARK: - 翻转坐标容器（NSScrollView 的 documentView 必须翻转，否则内容从底部开始排）

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - dump

/// 收集面板上所有可断言的文字：文本 / 按钮 / 占位符 / 勾选状态
func dumpText(from root: NSView) -> String {
    func collect(_ v: NSView, _ out: inout [String]) {
        if let tf = v as? NSTextField {
            if !tf.stringValue.isEmpty {
                out.append(tf.stringValue)
            } else if let ph = tf.placeholderString ?? tf.placeholderAttributedString?.string, !ph.isEmpty {
                out.append("~\"\(ph)\"")
            }
        }
        if let b = v as? NSButton {
            if b is CheckboxButton {
                let name = b.title.isEmpty ? (b.identifier?.rawValue ?? "开关") : b.title
                out.append("[\(name)=\(b.state == .on ? "on" : "off")]")
            } else if !b.title.isEmpty {
                out.append("[\(b.title)]")
            }
        }
        v.subviews.forEach { collect($0, &out) }
    }
    var out: [String] = []
    collect(root, &out)
    return out.joined(separator: " · ")
}
