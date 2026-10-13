import AppKit

/// 收藏整理窗口:用 NSOutlineView 展示整棵收藏树,支持把事务码/文本/文件夹
/// 拖拽移动到别的文件夹(或拖回根级)。改动在一棵可变镜像树上进行,
/// 关窗(或每次拖拽后)写回 TCodeStore。
///
/// 为什么要镜像树:TCodeNode 是值类型 enum,NSOutlineView 需要稳定、可按引用
/// 比较(===)的 item 来跟踪展开/选中/拖拽。于是打开窗口时把 store 的树转成
/// 一棵 class 节点树(MutableNode,带身份),操作完再转回 [TCodeNode] 写回。

/// 可变镜像节点:叶子(code/text)无 children,文件夹有 children。
final class MutableNode {
    enum Kind { case code, text, folder }
    var kind: Kind
    var value: String            // code/text 的内容,或文件夹名
    var children: [MutableNode]
    weak var parent: MutableNode?

    init(kind: Kind, value: String, children: [MutableNode] = []) {
        self.kind = kind
        self.value = value
        self.children = children
        for c in children { c.parent = self }
    }

    var isFolder: Bool { kind == .folder }

    /// 自己是否是 target 的祖先(含自身)——拖拽时禁止把文件夹拖进它自己的子孙里
    func isAncestor(of target: MutableNode) -> Bool {
        var p: MutableNode? = target
        while let cur = p {
            if cur === self { return true }
            p = cur.parent
        }
        return false
    }

    // MARK: - 与 TCodeNode 互转

    static func from(_ nodes: [TCodeNode]) -> [MutableNode] {
        nodes.map { node in
            switch node {
            case .code(let c): return MutableNode(kind: .code, value: c)
            case .text(let t): return MutableNode(kind: .text, value: t)
            case .folder(let name, let kids):
                return MutableNode(kind: .folder, value: name, children: from(kids))
            }
        }
    }

    static func toTCodeNodes(_ nodes: [MutableNode]) -> [TCodeNode] {
        nodes.map { n in
            switch n.kind {
            case .code: return .code(n.value)
            case .text: return .text(n.value)
            case .folder: return .folder(name: n.value, children: toTCodeNodes(n.children))
            }
        }
    }
}

/// 整理窗口控制器(单例持有,避免被释放)
final class ManageWindowController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSWindowDelegate {
    static let shared = ManageWindowController()

    private var window: NSWindow?
    private var outline: NSOutlineView?
    private weak var store: TCodeStore?
    private var roots: [MutableNode] = []

    private static let dragType = NSPasteboard.PasteboardType("com.sap.sapguitabs.node")

    /// 打开(或前置)整理窗口
    func show(store: TCodeStore) {
        self.store = store
        self.roots = MutableNode.from(store.root)

        if let w = window {
            outline?.reloadData()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let outline = NSOutlineView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.title = "收藏"
        col.width = 360
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.rowSizeStyle = .default
        outline.indentationPerLevel = 16
        outline.dataSource = self
        outline.delegate = self
        outline.registerForDraggedTypes([Self.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.floatsGroupRows = false
        self.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // 底部工具栏:+ 节点 / + 文件夹 / 删除(作用于选中项所在层级)
        let addNodeBtn = makeToolButton("+ 节点", #selector(addNodeClicked))
        let addFolderBtn = makeToolButton("+ 文件夹", #selector(addFolderClicked))
        let deleteBtn = makeToolButton("删除", #selector(deleteClicked))

        let bar = NSStackView(views: [addNodeBtn, addFolderBtn, NSView(), deleteBtn])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        bar.translatesAutoresizingMaskIntoConstraints = false
        // 中间塞一个可伸展的空 view 把删除按钮推到右边
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "整理收藏(拖拽移动)"
        win.contentView = container
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        self.window = win

        outline.reloadData()
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

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        childrenOf(item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        childrenOf(item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? MutableNode)?.isFolder ?? false
    }

    private func childrenOf(_ item: Any?) -> [MutableNode] {
        guard let node = item as? MutableNode else { return roots }
        return node.children
    }

    // MARK: - 视图

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? MutableNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(iv)
            c.addSubview(tf)
            c.imageView = iv
            c.textField = tf
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                iv.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 14),
                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 5),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()

        switch node.kind {
        case .folder:
            cell.textField?.stringValue = node.value
            cell.textField?.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            cell.imageView?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        case .code:
            cell.textField?.stringValue = node.value
            cell.textField?.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.imageView?.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        case .text:
            cell.textField?.stringValue = node.value
            cell.textField?.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.imageView?.image = nil
        }
        return cell
    }

    // MARK: - 拖拽

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        // 用 item 在 draggedNode 里缓存被拖的节点;pasteboard 只放一个占位串
        guard let node = item as? MutableNode else { return nil }
        draggedNode = node
        let pb = NSPasteboardItem()
        pb.setString(node.value, forType: Self.dragType)
        return pb
    }

    private weak var draggedNode: MutableNode?

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let dragged = draggedNode else { return [] }
        let targetFolder = item as? MutableNode   // nil = 根级

        // 目标必须是文件夹或根级
        if let t = targetFolder, !t.isFolder { return [] }
        // 不能把文件夹拖进它自身或其子孙
        if let t = targetFolder, dragged.isFolder, dragged.isAncestor(of: t) { return [] }
        // 拖到自身没有意义
        if let t = targetFolder, t === dragged { return [] }

        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        guard let dragged = draggedNode else { return false }
        let targetFolder = item as? MutableNode

        // 从原父节点摘除
        detach(dragged)

        // 挂到目标(文件夹的 children 或根级)。因为写回时会重新排序,这里追加即可。
        if let folder = targetFolder {
            dragged.parent = folder
            folder.children.append(dragged)
        } else {
            dragged.parent = nil
            roots.append(dragged)
        }

        commit()
        outlineView.reloadData()
        if let folder = targetFolder { outlineView.expandItem(folder) }
        return true
    }

    /// 从当前父节点(或根)移除 node
    private func detach(_ node: MutableNode) {
        if let p = node.parent {
            p.children.removeAll { $0 === node }
        } else {
            roots.removeAll { $0 === node }
        }
        node.parent = nil
    }

    /// 把镜像树写回 store(store 会递归排序 + 落盘)
    private func commit() {
        store?.replaceRoot(MutableNode.toTCodeNodes(roots))
    }

    // MARK: - 增 / 删(作用于选中项所在层级)

    /// 当前操作的目标文件夹:选中文件夹→它本身;选中叶子→其父;未选→根级(nil=根)。
    private func targetFolderForInsert() -> MutableNode? {
        guard let outline = outline else { return nil }
        let row = outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? MutableNode else { return nil }
        return node.isFolder ? node : node.parent
    }

    /// 目标文件夹的直接子节点数组(nil 文件夹=根级)
    private func siblings(in folder: MutableNode?) -> [MutableNode] {
        folder?.children ?? roots
    }

    @objc private func addNodeClicked() {
        guard let r = TextPrompt.run(title: "添加节点",
                                     message: "请输入内容:",
                                     placeholder: "事务码或文本",
                                     checkboxTitle: "作为事务码添加",
                                     checkboxOn: true),
              !r.text.isEmpty else { return }
        let value = r.text.uppercased()
        let folder = targetFolderForInsert()
        let kind: MutableNode.Kind = r.checked ? .code : .text

        // 同层级同类重名判重(code 不区分大小写、text 完全相同——这里都已大写,统一按相等判)
        if siblings(in: folder).contains(where: { $0.kind == kind && $0.value == value }) {
            alert("已存在", "\"\(value)\" 已在该文件夹中。")
            return
        }

        let node = MutableNode(kind: kind, value: value)
        insert(node, into: folder)
    }

    @objc private func addFolderClicked() {
        guard let r = TextPrompt.run(title: "新建文件夹",
                                     message: "请输入文件夹名称:",
                                     placeholder: "文件夹名"),
              !r.text.isEmpty else { return }
        let name = r.text
        let folder = targetFolderForInsert()
        if siblings(in: folder).contains(where: { $0.isFolder && $0.value.caseInsensitiveCompare(name) == .orderedSame }) {
            alert("已存在", "文件夹 \"\(name)\" 已在该层级中。")
            return
        }
        let node = MutableNode(kind: .folder, value: name)
        insert(node, into: folder)
    }

    /// 把新节点挂到目标文件夹(或根级),写回、刷新、展开并选中
    private func insert(_ node: MutableNode, into folder: MutableNode?) {
        if let f = folder {
            node.parent = f
            f.children.append(node)
        } else {
            node.parent = nil
            roots.append(node)
        }
        commit()
        outline?.reloadData()
        if let f = folder { outline?.expandItem(f) }
        let row = outline?.row(forItem: node) ?? -1
        if row >= 0 { outline?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    @objc private func deleteClicked() {
        guard let outline = outline else { return }
        let row = outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? MutableNode else {
            alert("未选中", "请先选中要删除的项。")
            return
        }
        if node.isFolder {
            let a = NSAlert()
            a.messageText = "删除文件夹"
            a.informativeText = "确定删除文件夹 \"\(node.value)\" 及其全部内容?"
            a.addButton(withTitle: "删除")
            a.addButton(withTitle: "取消")
            if let w = window { a.beginSheetModal(for: w) { resp in
                if resp == .alertFirstButtonReturn { self.performDelete(node) }
            } } else if a.runModal() == .alertFirstButtonReturn {
                performDelete(node)
            }
        } else {
            performDelete(node)
        }
    }

    private func performDelete(_ node: MutableNode) {
        detach(node)
        commit()
        outline?.reloadData()
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
        commit()
        window = nil
        outline = nil
    }
}
