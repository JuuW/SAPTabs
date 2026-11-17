import AppKit

/// 字段默认值管理窗口:一个四列表格(系统 / 事务码 / 字段 / 默认值),
/// 底部「+ 添加 / 编辑 / 删除」。增删改直接作用于 DefaultsStore,改完即落盘,
/// 并通过 onChange 回调让调用方清空已填记录(resetFilledState),使新配置对在场窗口即时生效。
///
/// 默认值规则有四个字段,TabBarView 里的 TextPrompt 只有三格,放不下,
/// 故本文件内建一个四字段模态弹框 FieldDefaultPrompt。
final class DefaultsManageWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = DefaultsManageWindowController()

    private var window: NSWindow?
    private var table: NSTableView?
    private weak var store: DefaultsStore?
    private var onChange: (() -> Void)?

    /// 打开(或前置)管理窗口。onChange 在每次增删改落盘后调用(用于 resetFilledState)。
    func show(store: DefaultsStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        store.reload()

        if let w = window {
            table?.reloadData()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let table = NSTableView()
        for (id, title, width) in [
            ("system", "系统", CGFloat(70)),
            ("tcode", "事务码", CGFloat(110)),
            ("field", "字段", CGFloat(160)),
            ("value", "默认值", CGFloat(160)),
        ] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            table.addTableColumn(col)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.rowSizeStyle = .default
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(editClicked)
        self.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = makeToolButton("+ 添加", #selector(addClicked))
        let copyBtn = makeToolButton("复制", #selector(copyClicked))
        let editBtn = makeToolButton("编辑", #selector(editClicked))
        let deleteBtn = makeToolButton("删除", #selector(deleteClicked))

        let bar = NSStackView(views: [addBtn, NSView(), copyBtn, editBtn, deleteBtn])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.setHuggingPriority(.defaultLow, for: .horizontal)

        let container = NSView()
        container.addSubview(scroll)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "字段默认值"
        win.contentView = container
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        self.window = win

        table.reloadData()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeToolButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        return b
    }

    // MARK: - 数据源

    func numberOfRows(in tableView: NSTableView) -> Int {
        store?.rules.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let rule = store?.rules[safe: row], let col = tableColumn else { return nil }
        let id = col.identifier
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            c.addSubview(tf)
            c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        switch id.rawValue {
        case "system": cell.textField?.stringValue = rule.system
        case "tcode":  cell.textField?.stringValue = rule.tcode
        case "field":  cell.textField?.stringValue = rule.field
        default:       cell.textField?.stringValue = rule.value
        }
        return cell
    }

    // MARK: - 增 / 改 / 删

    @objc private func addClicked() {
        guard let store = store else { return }
        guard let r = FieldDefaultPrompt.run(title: "添加字段默认值", window: window) else { return }
        // 同键已存在 → 确认覆盖
        let sys = r.system.uppercased(), code = r.tcode.uppercased(), fld = r.field
        if store.rules.contains(where: { $0.system == sys && $0.tcode == code && $0.field == fld }) {
            let a = NSAlert()
            a.messageText = "已存在该规则"
            a.informativeText = "系统 \(sys) / 事务码 \(code) / 字段 \"\(fld)\" 已有默认值,是否覆盖?"
            a.addButton(withTitle: "覆盖")
            a.addButton(withTitle: "取消")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        store.addRule(system: r.system, tcode: r.tcode, field: r.field, value: r.value)
        afterChange(select: (sys, code, fld))
    }

    /// 复制:把选中规则作为初始值弹出新建弹框,用户改动后存为新规则(保存逻辑同"添加")。
    @objc private func copyClicked() {
        guard let store = store, let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, let rule = store.rules[safe: row] else {
            alert("未选中", "请先选中要复制的规则。")
            return
        }
        guard let r = FieldDefaultPrompt.run(title: "复制字段默认值", window: window,
                                             system: rule.system, tcode: rule.tcode,
                                             field: rule.field, value: rule.value) else { return }
        let sys = r.system.uppercased(), code = r.tcode.uppercased(), fld = r.field
        if store.rules.contains(where: { $0.system == sys && $0.tcode == code && $0.field == fld }) {
            let a = NSAlert()
            a.messageText = "已存在该规则"
            a.informativeText = "系统 \(sys) / 事务码 \(code) / 字段 \"\(fld)\" 已有默认值,是否覆盖?"
            a.addButton(withTitle: "覆盖")
            a.addButton(withTitle: "取消")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        store.addRule(system: r.system, tcode: r.tcode, field: r.field, value: r.value)
        afterChange(select: (sys, code, fld))
    }

    @objc private func editClicked() {
        guard let store = store, let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, let rule = store.rules[safe: row] else {
            alert("未选中", "请先选中要编辑的规则。")
            return
        }
        guard let r = FieldDefaultPrompt.run(title: "编辑字段默认值", window: window,
                                             system: rule.system, tcode: rule.tcode,
                                             field: rule.field, value: rule.value) else { return }
        let ok = store.updateRule(oldSystem: rule.system, oldTcode: rule.tcode, oldField: rule.field,
                                  system: r.system, tcode: r.tcode, field: r.field, value: r.value)
        guard ok else {
            alert("已存在", "修改后的 系统/事务码/字段 与另一条规则冲突。")
            return
        }
        afterChange(select: (r.system.uppercased(), r.tcode.uppercased(), r.field.trimmingCharacters(in: .whitespaces)))
    }

    @objc private func deleteClicked() {
        guard let store = store, let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, let rule = store.rules[safe: row] else {
            alert("未选中", "请先选中要删除的规则。")
            return
        }
        store.removeRule(system: rule.system, tcode: rule.tcode, field: rule.field)
        afterChange(select: nil)
    }

    /// 落盘后:通知调用方(resetFilledState)、刷新表格、可选把焦点落到某条规则
    private func afterChange(select key: (system: String, tcode: String, field: String)?) {
        onChange?()
        guard let store = store, let table = table else { return }
        table.reloadData()
        if let k = key,
           let i = store.rules.firstIndex(where: { $0.system == k.system && $0.tcode == k.tcode && $0.field == k.field }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            table.scrollRowToVisible(i)
        }
    }

    private func alert(_ title: String, _ msg: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.addButton(withTitle: "好")
        if let w = window { a.beginSheetModal(for: w, completionHandler: nil) }
        else { a.runModal() }
    }

    // MARK: - 窗口

    func windowWillClose(_ notification: Notification) {
        window = nil
        table = nil
    }
}

/// 四字段默认值编辑弹框(系统 / 事务码 / 字段 / 默认值)。
/// 用 NSApp.runModal 做模态,回车=确定、Esc=取消;四格都非空才返回,否则返回 nil。
/// (独立于 TextPrompt:后者只有三格,放不下四个字段。)
final class FieldDefaultPrompt: NSObject {
    private let window: NSWindow
    private let systemField: NSTextField
    private let tcodeField: NSTextField
    private let fieldField: NSTextField
    private let valueField: NSTextField
    private var response: NSApplication.ModalResponse = .cancel

    static func run(title: String, window parent: NSWindow?,
                    system: String = "", tcode: String = "", field: String = "", value: String = "")
        -> (system: String, tcode: String, field: String, value: String)? {
        let p = FieldDefaultPrompt(title: title, system: system, tcode: tcode, field: field, value: value)
        return p.present(over: parent)
    }

    private init(title: String, system: String, tcode: String, field: String, value: String) {
        let width: CGFloat = 340
        let pad: CGFloat = 20
        let labelW: CGFloat = 64
        let rowH: CGFloat = 24
        let rowGap: CGFloat = 10
        let btnH: CGFloat = 28

        func makeInput(_ placeholder: String, _ initial: String) -> NSTextField {
            let f = EditableTextField(frame: .zero)
            f.placeholderString = placeholder
            f.font = .systemFont(ofSize: 13)
            f.stringValue = initial
            return f
        }
        systemField = makeInput("如 SWA", system)
        tcodeField  = makeInput("如 S000 / SE16", tcode)
        fieldField  = makeInput("字段标签,如 User", field)
        valueField  = makeInput("要自动填入的默认值", value)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)

        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: 12)
            l.alignment = .right
            l.textColor = .secondaryLabelColor
            return l
        }
        let rows: [(NSTextField, NSTextField)] = [
            (label("系统"), systemField),
            (label("事务码"), tcodeField),
            (label("字段"), fieldField),
            (label("默认值"), valueField),
        ]

        let okBtn = NSButton(title: "确定", target: nil, action: nil)
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r"
        let cancelBtn = NSButton(title: "取消", target: nil, action: nil)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"

        let totalH = pad + 18 + 12 + CGFloat(rows.count) * (rowH + rowGap) + 6 + btnH + pad

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: totalH),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false

        super.init()

        let content = window.contentView!
        content.addSubview(titleLabel)
        for (l, f) in rows { content.addSubview(l); content.addSubview(f) }
        content.addSubview(okBtn); content.addSubview(cancelBtn)

        var y = totalH - pad - 18
        titleLabel.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 18)
        y -= 12
        let fieldX = pad + labelW + 8
        let fieldW = width - pad - fieldX
        var prev: NSTextField?
        for (l, f) in rows {
            y -= (rowGap + rowH)
            l.frame = NSRect(x: pad, y: y + 3, width: labelW, height: 18)
            f.frame = NSRect(x: fieldX, y: y, width: fieldW, height: rowH)
            prev?.nextKeyView = f
            prev = f
        }
        y -= (6 + btnH)
        let btnW: CGFloat = 72
        okBtn.frame = NSRect(x: width - pad - btnW, y: y, width: btnW, height: btnH)
        cancelBtn.frame = NSRect(x: width - pad - btnW * 2 - 8, y: y, width: btnW, height: btnH)

        okBtn.target = self; okBtn.action = #selector(confirm)
        cancelBtn.target = self; cancelBtn.action = #selector(cancel)
        window.initialFirstResponder = systemField
    }

    private func present(over parent: NSWindow?) -> (system: String, tcode: String, field: String, value: String)? {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        response = NSApp.runModal(for: window)
        window.orderOut(nil)
        guard response == .OK else { return nil }
        let sys = systemField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = tcodeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fld = fieldField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let val = valueField.stringValue   // 默认值保留原样(可能含空格/首尾空白有意义)
        guard !sys.isEmpty, !code.isEmpty, !fld.isEmpty else { return nil }
        return (sys, code, fld, val)
    }

    @objc private func confirm() { response = .OK; NSApp.stopModal(withCode: .OK) }
    @objc private func cancel()  { response = .cancel; NSApp.stopModal(withCode: .cancel) }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
