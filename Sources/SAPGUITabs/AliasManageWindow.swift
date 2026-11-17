import AppKit

/// 事务码别名管理窗口:一个两列表格(事务码 / 别名),底部「+ 添加 / 编辑 / 删除」。
/// 增删改直接作用于 AliasStore,改完即落盘并刷新页签显示。
///
/// 为什么单独一个窗口而不是像收藏那样复用 NSOutlineView:别名是扁平的 tcode→别名
/// 映射,没有层级,用 NSTableView 两列更直观。编辑弹框复用 TabBarView 里的 TextPrompt
/// (主框=事务码,「实际值」框借用作别名输入)。
final class AliasManageWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = AliasManageWindowController()

    private var window: NSWindow?
    private var table: NSTableView?
    private weak var store: AliasStore?

    /// 打开(或前置)别名管理窗口。打开前 reload 一次,确保看到最新磁盘状态。
    func show(store: AliasStore) {
        self.store = store
        store.reload()

        if let w = window {
            table?.reloadData()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let table = NSTableView()
        let codeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tcode"))
        codeCol.title = "事务码"
        codeCol.width = 220
        let aliasCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("alias"))
        aliasCol.title = "别名"
        aliasCol.width = 140
        table.addTableColumn(codeCol)
        table.addTableColumn(aliasCol)
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
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = makeToolButton("+ 添加", #selector(addClicked))
        let editBtn = makeToolButton("编辑", #selector(editClicked))
        let deleteBtn = makeToolButton("删除", #selector(deleteClicked))

        let bar = NSStackView(views: [addBtn, NSView(), editBtn, deleteBtn])
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "事务码别名"
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
        cell.textField?.stringValue = (id.rawValue == "tcode") ? rule.tcode : rule.alias
        return cell
    }

    // MARK: - 增 / 改 / 删

    @objc private func addClicked() {
        guard let store = store else { return }
        guard let r = TextPrompt.run(title: "添加别名",
                                     message: "事务码在页签上将显示为别名。",
                                     placeholder: "事务码(如 /SCWM/MON)",
                                     valuePlaceholder: "别名(如 MON)"),
              !r.text.isEmpty, !r.value.isEmpty else { return }
        let tcode = r.text.uppercased()
        // 已存在则提示会覆盖
        if store.rules.contains(where: { $0.tcode.caseInsensitiveCompare(tcode) == .orderedSame }) {
            let a = NSAlert()
            a.messageText = "已存在别名"
            a.informativeText = "事务码 \"\(tcode)\" 已有别名,是否覆盖?"
            a.addButton(withTitle: "覆盖")
            a.addButton(withTitle: "取消")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        store.upsert(tcode: tcode, alias: r.value)
        reloadAndSelect(tcode: tcode)
    }

    @objc private func editClicked() {
        guard let store = store, let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, let rule = store.rules[safe: row] else {
            alert("未选中", "请先选中要编辑的别名。")
            return
        }
        guard let r = TextPrompt.run(title: "编辑别名",
                                     message: "事务码在页签上将显示为别名。",
                                     placeholder: "事务码(如 /SCWM/MON)",
                                     initialText: rule.tcode,
                                     initialValue: rule.alias,
                                     valuePlaceholder: "别名(如 MON)"),
              !r.text.isEmpty, !r.value.isEmpty else { return }
        let newTcode = r.text.uppercased()
        // 改了事务码且撞上另一条已有别名时提示
        if newTcode.caseInsensitiveCompare(rule.tcode) != .orderedSame,
           store.rules.contains(where: { $0.tcode.caseInsensitiveCompare(newTcode) == .orderedSame }) {
            alert("已存在", "事务码 \"\(newTcode)\" 已有别名。")
            return
        }
        // 事务码改名:先删旧键再写新键(upsert 按 tcode 判重,改名等于新增一条)
        if newTcode.caseInsensitiveCompare(rule.tcode) != .orderedSame {
            store.remove(tcode: rule.tcode)
        }
        store.upsert(tcode: newTcode, alias: r.value)
        reloadAndSelect(tcode: newTcode)
    }

    @objc private func deleteClicked() {
        guard let store = store, let table = table else { return }
        let row = table.selectedRow
        guard row >= 0, let rule = store.rules[safe: row] else {
            alert("未选中", "请先选中要删除的别名。")
            return
        }
        store.remove(tcode: rule.tcode)
        table.reloadData()
    }

    /// 刷新表格并把焦点落到指定 tcode 对应的行
    private func reloadAndSelect(tcode: String) {
        guard let store = store, let table = table else { return }
        table.reloadData()
        if let i = store.rules.firstIndex(where: { $0.tcode.caseInsensitiveCompare(tcode) == .orderedSame }) {
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

private extension Array {
    /// 越界返回 nil 的安全下标(reloadData 与数据变更之间可能出现瞬时越界)
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
