import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var manager: SAPWindowManager
    @ObservedObject var tcodeStore: TCodeStore
    @StateObject private var overflow = OverflowState()

    var body: some View {
        Group {
            if !manager.accessibilityGranted {
                permissionPrompt
            } else if manager.windows.isEmpty {
                emptyState
            } else {
                tabs
            }
        }
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.82, green: 0.90, blue: 0.98))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            // 最左:TCode 收藏下拉(字母序列表 + Add tcode)
            TCodeMenuView(manager: manager, store: tcodeStore)
            OverflowTabsLayout(count: manager.windows.count, reserve: 40, state: overflow) {
                // 子视图顺序:所有页签,最后一个是溢出按钮
                ForEach(Array(manager.windows.enumerated()), id: \.element.id) { idx, win in
                    chip(win: win, idx: idx)
                }
                OverflowMenuView(manager: manager, state: overflow)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(win: SAPWindow, idx: Int) -> some View {
        // 组首(与上一页签系统不同,或第 0 个)在页签前显示一次系统 ID 标签,
        // 组内其余页签不再重复系统 ID,只显 TCode
        let isGroupHead = idx == 0 || isSystemBoundary(at: idx)
        return TabChip(
            title: displayLabel(win),
            isActive: win.id == manager.frontWindowID,
            leadingSystemID: isGroupHead ? manager.systemID(win.title) : nil,
            onClose: { manager.close(win) }
        )
        .onTapGesture { manager.focus(win) }
        .help("\(win.title)\n单击切换")
    }

    // 当前页签与上一个页签系统 ID 不同时,即为系统组边界
    private func isSystemBoundary(at idx: Int) -> Bool {
        let prev = manager.systemID(manager.windows[idx - 1].title)
        let cur = manager.systemID(manager.windows[idx].title)
        return prev != cur
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .foregroundStyle(.secondary)
            Text("没有打开的 SAP 窗口")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text("需要「辅助功能」权限")
                .font(.system(size: 12))
            Button("去授权") { manager.promptAccessibility() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }

    /// 页签正文:只显当前事务码(如 "/SCWM/MON")。系统 ID 由组首标签单独显示,
    /// 这里不再重复。读不到事务码时(登录屏/弹窗/主屏)回退显示系统 ID,避免空白。
    /// 注意:仅用于显示。窗口身份与焦点匹配始终走 id / AX 元素身份,
    /// 两个页签即便显示文本相同也不会焦点混淆。
    private func displayLabel(_ win: SAPWindow) -> String {
        if let code = win.tcode, !code.isEmpty {
            return code
        }
        return manager.systemID(win.title)
    }
}

// CLT 工具链缺少 SwiftUIMacros 插件,@State 宏无法展开,改用 ObservableObject 承载悬停态
private final class HoverState: ObservableObject {
    @Published var on = false
}

struct TabChip: View {
    let title: String
    let isActive: Bool
    var leadingSystemID: String? = nil   // 组首页签在前面显示一次系统 ID 标签
    var onClose: () -> Void = {}

    @StateObject private var hover = HoverState()

    var body: some View {
        let hovering = hover.on
        return HStack(spacing: 0) {
            // 组首:在页签前画系统 ID 标签(同系统只出现一次);非组首留小间距
            if let sys = leadingSystemID {
                Text(sys)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize()               // 永远按内容完整显示,不被布局压缩成 "D..."
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(red: 0.12, green: 0.33, blue: 0.65))
                    )
                    .padding(.leading, 6)
                    .padding(.trailing, 3)
            } else {
                Color.clear.frame(width: 2, height: 1)
            }

            chipContent(hovering: hovering)
        }
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
    }

    private func chipContent(hovering: Bool) -> some View {
        HStack(spacing: 5) {
            // 用隐藏的粗体副本撑住宽度,实际文字叠在上面。
            // 这样激活(粗体)与否宽度都按最宽的粗体算,页签宽度恒定,
            // 分割线位置不会因点击加粗而右移。
            ZStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .hidden()
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .bold : .regular))
                    .foregroundStyle(Color.primary)
            }
            .lineLimit(1)
            // 为右上角关闭叉叉预留宽度,且所有页签恒定预留,焦点切换时宽度不跳动
            Spacer().frame(width: 12)
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 6, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 6,
                style: .continuous
            )
            .fill(isActive ? Color.white : (hovering ? Color.white.opacity(0.4) : Color.clear))
        )
        .overlay(alignment: .topTrailing) {
            if isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.secondary.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .help("关闭此窗口")
                .padding(.top, 2)
                .padding(.trailing, 2)
            }
        }
    }
}

/// 共享:当前能放得下的页签数量(Layout 计算 → Menu 读取)
final class OverflowState: ObservableObject {
    @Published var visibleCount: Int = .max
    var updateToken: UInt64 = 0   // 非 @Published:仅用于防抖去重,不触发重绘
}

/// 单行溢出布局:子视图为 N 个页签 + 末尾 1 个溢出按钮。
/// 放得下时页签整体居中、溢出按钮尺寸归零;放不下时左对齐铺到临界点,
/// 其余页签不占空间(移出可视区),溢出按钮贴最右端。
struct OverflowTabsLayout: Layout {
    let count: Int                 // 页签数量(不含溢出按钮)
    let reserve: CGFloat           // 需要溢出时为溢出按钮预留的宽度
    // 普通引用,不是 @ObservedObject:Layout 只"写入"计算出的 visibleCount,
    // 绝不能"观察"它。否则 setVisible 改 visibleCount → Layout 重跑 → 又 setVisible,
    // 形成自激振荡(表现为溢出按钮/菜单不停闪烁)。布局重跑只应由 bounds/子视图
    // 尺寸变化驱动,这由 SwiftUI 自身管理。
    let state: OverflowState

    init(count: Int, reserve: CGFloat, state: OverflowState) {
        self.count = count
        self.reserve = reserve
        self.state = state
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard count > 0, subviews.count == count + 1 else { return }
        // SwiftUI 布局过程中会用 width=0 之类的中间提议来探测尺寸。若拿这些
        // 无意义的瞬时宽度去 setVisible,会让 visibleCount 在真实值(如 12)和
        // "一个都放不下"(1)之间每帧翻转,写回 @Published 触发溢出菜单重绘 →
        // 永不收敛的闪烁。因此:宽度不足以放下任何内容时,只做占位摆放,
        // 绝不更新 visibleCount。
        guard bounds.width > reserve else {
            for i in 0..<count {
                subviews[i].place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                                  anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            }
            subviews[count].place(at: CGPoint(x: bounds.minX, y: bounds.midY),
                                   anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            return
        }
        let tabWidths = (0..<count).map { subviews[$0].sizeThatFits(.unspecified).width }
        let total = tabWidths.reduce(0, +)
        let avail = bounds.width

        // 溢出按钮始终以固定宽度 reserve 提议,避免其内容变化反馈给布局造成震荡闪烁
        let btnProposal = ProposedViewSize(width: reserve, height: bounds.height)

        // 全部放得下:整体居中,溢出按钮移出可视区(仍占固定提议宽度,保证布局输入恒定)
        if total <= avail {
            var x = bounds.minX + (avail - total) / 2
            for i in 0..<count {
                subviews[i].place(
                    at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: tabWidths[i], height: bounds.height)
                )
                x += tabWidths[i]
            }
            subviews[count].place(at: CGPoint(x: bounds.maxX + 2000, y: bounds.midY),
                                   anchor: .leading, proposal: btnProposal)
            setVisible(count)
            return
        }

        // 放不下:预留溢出按钮宽度,左对齐塞尽可能多的页签
        let budget = avail - reserve
        var used: CGFloat = 0
        var visible = 0
        for i in 0..<count {
            if used + tabWidths[i] <= budget {
                used += tabWidths[i]
                visible += 1
            } else {
                break
            }
        }
        visible = max(visible, 1) // 至少显示 1 个

        var x = bounds.minX
        for i in 0..<count {
            if i < visible {
                subviews[i].place(
                    at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: tabWidths[i], height: bounds.height)
                )
                x += tabWidths[i]
            } else {
                // 溢出页签:不占可视空间
                subviews[i].place(at: CGPoint(x: bounds.maxX + 2000, y: bounds.midY),
                                  anchor: .leading, proposal: ProposedViewSize(width: 0, height: 0))
            }
        }
        // 溢出按钮贴最右端(固定提议宽度)
        subviews[count].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: btnProposal
        )
        setVisible(visible)
    }

    private func setVisible(_ n: Int) {
        // 滞回:避免临界点在 n / n-1 间反复横跳导致闪烁。
        // 仅当新值与已记录值不同、且距上次更新已稳定时才提交。
        guard state.visibleCount != n else { return }
        let token = state.updateToken &+ 1
        state.updateToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            // 期间若又有新的布局结果,token 会变,放弃这次过期的提交
            guard state.updateToken == token else { return }
            if state.visibleCount != n { state.visibleCount = n }
        }
    }
}

/// 页签栏最左侧的 TCode 收藏下拉:向下三角按钮,点开列出配置文件里的事务码
/// (字母序),点击某项即填入当前前台会话的 OK Code 框并回车执行;
/// 末行 "Add tcode" 抓当前会话正在跑的事务码加入列表,已存在则弹消息框提示。
///
/// 用原生 NSMenu(经 NSViewRepresentable 包一个按钮弹出)+ 标准 NSMenuItem:
/// 外观为系统原生、点击可靠。给菜单设 .aqua 外观以避免 vibrancy 半透明。
struct TCodeMenuView: View {
    @ObservedObject var manager: SAPWindowManager
    @ObservedObject var store: TCodeStore

    var body: some View {
        NativeTCodeButton(manager: manager, store: store)
            .frame(width: 33)
            .frame(maxHeight: .infinity)
            .padding(.vertical, -2)
            .padding(.trailing, 4)
            .help("事务码收藏:点选填入当前会话并执行(按住 Option 用 /n 当前窗口切换)")
    }
}

/// 承载 NSMenu 的三角按钮
private struct NativeTCodeButton: NSViewRepresentable {
    let manager: SAPWindowManager
    let store: TCodeStore

    func makeCoordinator() -> Coordinator { Coordinator(manager: manager, store: store) }

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .texturedRounded
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .heavy)
        btn.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "TCode")?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = NSColor(red: 0.12, green: 0.33, blue: 0.65, alpha: 1)
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.popMenu(_:))
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        btn.layer?.cornerRadius = 6
        return btn
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.manager = manager
        context.coordinator.store = store
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var manager: SAPWindowManager
        var store: TCodeStore

        /// 事务码菜单项前的闪电图标(普通文本节点不带),用于一眼区分两类叶子
        static let boltImage: NSImage? = {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            let img = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "TCode")?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = false
            return img
        }()

        /// 与闪电图标等尺寸的透明占位图:普通文本项用它占住图标位,使文本与事务码左对齐。
        /// 必须用 drawingHandler 画出真正的(透明)表示——空的 NSImage(size:) 没有
        /// representation,AppKit 对它的占位宽度不可靠(子菜单里尤其会不占位)。
        static let placeholderImage: NSImage? = {
            let size = boltImage?.size ?? NSSize(width: 12, height: 12)
            let img = NSImage(size: size, flipped: false) { _ in true } // 画个全透明
            img.isTemplate = false
            return img
        }()

        // 根菜单与其顶部搜索框:applySearch 直接增删根菜单下方的项来展示过滤结果
        private weak var rootMenu: NSMenu?
        private weak var searchField: SearchFieldView?

        init(manager: SAPWindowManager, store: TCodeStore) {
            self.manager = manager
            self.store = store
        }

        /// 菜单打开后,给它的宿主窗口垫一层不透明底色,盖住 vibrancy 透出的后方内容
        func menuDidClose(_ menu: NSMenu) {}
        func menuWillOpen(_ menu: NSMenu) {
            // 根菜单打开时,让顶部搜索框拿到键盘焦点,可直接输入过滤
            if menu === rootMenu { searchField?.focus() }
            // 菜单窗口此刻可能还没就位,下一轮 runloop 再处理
            DispatchQueue.main.async {
                for win in NSApp.windows where String(describing: type(of: win)).contains("NSMenuWindow")
                    || String(describing: type(of: win)).contains("NSPopupMenuWindow") {
                    guard let content = win.contentView else { continue }
                    win.isOpaque = false
                    // 在内容视图最底层插入一个不透明白色底板
                    if content.subviews.first(where: { $0.identifier?.rawValue == "opaqueBG" }) == nil {
                        let bg = NSView(frame: content.bounds)
                        bg.identifier = NSUserInterfaceItemIdentifier("opaqueBG")
                        bg.autoresizingMask = [.width, .height]
                        bg.wantsLayer = true
                        bg.layer?.backgroundColor = NSColor.white.cgColor
                        content.addSubview(bg, positioned: .below, relativeTo: content.subviews.first)
                    }
                }
            }
        }

        @objc func popMenu(_ sender: NSButton) {
            let menu = buildMenu(for: store.root, path: [], isRoot: true)
            let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
            menu.popUp(positioning: nil, at: origin, in: sender)
        }

        /// 递归构建某一级菜单:先列该级节点(文件夹→子菜单,TCode→可点击叶子),
        /// 末尾加分隔线 + Add Node + Add Folder(都作用于本级 path)。
        /// isRoot:仅根菜单在最顶部插入搜索框,输入时把下方替换为跨层级的扁平匹配结果。
        private func buildMenu(for nodes: [TCodeNode], path: [String], isRoot: Bool = false) -> NSMenu {
            let menu = NSMenu()
            menu.appearance = NSAppearance(named: .aqua)   // 避免 vibrancy 半透明
            menu.delegate = self

            if isRoot {
                rootMenu = menu
                let searchItem = NSMenuItem()
                let box = SearchFieldView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
                box.onChange = { [weak self] q in self?.applySearch(q) }
                searchItem.view = box
                searchField = box
                menu.addItem(searchItem)
                menu.addItem(.separator())
            }

            appendNodeItems(nodes, path: path, to: menu)

            // 根菜单末尾:打开整理窗口(增删节点/文件夹、拖拽移动)
            if isRoot {
                menu.addItem(.separator())
                let manage = NSMenuItem(title: "整理收藏…", action: #selector(openManageWindow), keyEquivalent: "")
                manage.target = self
                menu.addItem(manage)
            }
            return menu
        }

        /// 打开整理窗口:增删节点/文件夹、拖拽把节点移到别的文件夹
        @objc private func openManageWindow() {
            ManageWindowController.shared.show(store: store)
        }

        /// 把某一级节点渲染成菜单项追加到 menu(文件夹→子菜单,code→带闪电叶子,text→普通叶子)
        private func appendNodeItems(_ nodes: [TCodeNode], path: [String], to menu: NSMenu) {
            for node in nodes {
                switch node {
                case .code(let code):
                    // 事务码项:标题前带闪电图标,点击填入 OK Code 执行
                    let item = NSMenuItem(title: code, action: #selector(runTCode(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = code
                    item.image = Self.boltImage
                    menu.addItem(item)
                    // Alt 替身项:按住 Option 时顶替上面那项显示,标题前加小写 /n 作提示
                    let alt = NSMenuItem(title: "/n" + code, action: #selector(runTCode(_:)), keyEquivalent: "")
                    alt.target = self
                    alt.representedObject = code
                    alt.image = Self.boltImage
                    alt.keyEquivalentModifierMask = .option
                    alt.isAlternate = true
                    menu.addItem(alt)
                case .text(let text):
                    // 普通文本项:用透明占位图占住图标位,使其与事务码左对齐
                    let item = NSMenuItem(title: text, action: #selector(copyText(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = text
                    item.image = Self.placeholderImage
                    menu.addItem(item)
                case .folder(let name, let children):
                    let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                    // 文件夹用加粗字体区分普通叶子项
                    item.attributedTitle = NSAttributedString(string: name, attributes: [
                        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                    ])
                    item.submenu = buildMenu(for: children, path: path + [name])
                    menu.addItem(item)
                }
            }
        }

        /// 搜索框内容变化时:空查询→恢复根级常规树;否则把搜索框下方替换为跨层级扁平匹配结果。
        /// 匹配不区分大小写;只按叶子自身内容匹配,文件夹名不参与、也不在结果里显示路径。
        private func applySearch(_ query: String) {
            guard let menu = rootMenu else { return }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

            // 保留顶部的搜索框项(index 0)与其后的分隔线(index 1),清掉之后所有项再重建
            while menu.items.count > 2 { menu.removeItem(at: menu.items.count - 1) }

            if q.isEmpty {
                appendNodeItems(store.root, path: [], to: menu)
                menu.addItem(.separator())
                let manage = NSMenuItem(title: "整理收藏…", action: #selector(openManageWindow), keyEquivalent: "")
                manage.target = self
                menu.addItem(manage)
                return
            }

            var matches: [(node: TCodeNode, path: [String])] = []
            collectMatches(store.root, path: [], query: q, into: &matches)

            if matches.isEmpty {
                let none = NSMenuItem(title: "无匹配项", action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
                return
            }

            for m in matches {
                switch m.node {
                case .code(let code):
                    let item = NSMenuItem(title: code, action: #selector(runTCode(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = code
                    item.image = Self.boltImage
                    menu.addItem(item)
                case .text(let text):
                    let item = NSMenuItem(title: text, action: #selector(copyText(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = text
                    item.image = Self.placeholderImage
                    menu.addItem(item)
                case .folder:
                    break   // 搜索结果只列可点击的叶子
                }
            }
        }

        /// 递归收集匹配 query 的叶子节点(code / text),记录其所在文件夹路径。
        /// 只按叶子自身内容匹配,文件夹名不参与匹配——仅作为下钻路径继续往里找。
        private func collectMatches(_ nodes: [TCodeNode], path: [String], query: String,
                                    into out: inout [(node: TCodeNode, path: [String])]) {
            for node in nodes {
                switch node {
                case .code(let c):
                    if c.localizedCaseInsensitiveContains(query) { out.append((node, path)) }
                case .text(let t):
                    if t.localizedCaseInsensitiveContains(query) { out.append((node, path)) }
                case .folder(let name, let children):
                    collectMatches(children, path: path + [name], query: query, into: &out)
                }
            }
        }

        /// 点选事务码:默认加 /o(另开新窗口),按住 Option(Alt)则 /n(当前窗口切新事务)
        @objc private func runTCode(_ sender: NSMenuItem) {
            guard let code = sender.representedObject as? String else { return }
            let opt = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
            manager.writeCommand((opt ? "/n" : "/o") + code, execute: true)
        }

        /// 点选普通文本:只复制到系统剪贴板,不填入 OK Code
        @objc private func copyText(_ sender: NSMenuItem) {
            guard let text = sender.representedObject as? String else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }
}

/// LSUIElement(菜单栏小工具)没有常规菜单栏,Cmd+C/V/X/A/Z 这些标准编辑快捷键
/// 无处路由,导致输入框里无法粘贴。让输入框自己把这些快捷键转成对应的 responder action。
/// 返回 true 表示已处理。
private func handleEditKeyEquivalent(_ event: NSEvent, on field: NSControl) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
          let chars = event.charactersIgnoringModifiers else { return false }
    let selector: Selector?
    switch chars {
    case "x": selector = #selector(NSText.cut(_:))
    case "c": selector = #selector(NSText.copy(_:))
    case "v": selector = #selector(NSText.paste(_:))
    case "a": selector = #selector(NSResponder.selectAll(_:))
    case "z": selector = Selector(("undo:"))
    default:  selector = nil
    }
    guard let sel = selector else { return false }
    return NSApp.sendAction(sel, to: field.currentEditor(), from: field)
}

/// 支持 Cmd 编辑快捷键的搜索框(见 handleEditKeyEquivalent)
final class EditableSearchField: NSSearchField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditKeyEquivalent(event, on: self) || super.performKeyEquivalent(with: event)
    }
}

/// 支持 Cmd 编辑快捷键的文本框(见 handleEditKeyEquivalent)
final class EditableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditKeyEquivalent(event, on: self) || super.performKeyEquivalent(with: event)
    }
}

/// 承载在菜单顶部的搜索框:一个 NSSearchField,内容变化时回调 onChange。
/// 作为 NSMenuItem.view 放入菜单,点击/输入时菜单不会关闭。
final class SearchFieldView: NSView, NSSearchFieldDelegate {
    let field = EditableSearchField()
    var onChange: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.placeholderString = "搜索…"
        field.font = .systemFont(ofSize: 12)
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func controlTextDidChange(_ obj: Notification) {
        onChange?(field.stringValue)
    }

    /// 让搜索框在菜单弹出后尽快拿到键盘焦点
    func focus() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.field)
        }
    }
}

struct OverflowMenuView: View {
    @ObservedObject var manager: SAPWindowManager
    @ObservedObject var state: OverflowState

    private var overflow: [SAPWindow] {
        let n = state.visibleCount
        guard n < manager.windows.count else { return [] }
        return Array(manager.windows.suffix(manager.windows.count - n))
    }

    var body: some View {
        let items = overflow
        // 固定占位宽度 40(= Layout 的 reserve),空时透明,避免尺寸在有/无溢出间跳变导致闪烁
        return ZStack {
            if !items.isEmpty {
                Menu {
                    ForEach(items) { win in
                        Button { manager.focus(win) } label: { Text(manager.fullLabel(for: win)) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(items.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.6))
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("还有 \(items.count) 个页签放不下")
            }
        }
        .frame(width: 40, height: 24)
    }
}

/// 紧凑的单行输入弹窗:标题、输入框、可选勾选框、确定/取消两个按钮,无图标、无多余留白。
/// 用 NSApp.runModal 做模态,回车=确定、Esc=取消。
/// 返回 (输入文本, 勾选框是否勾上);取消返回 nil。无勾选框时 checked 恒为 false。
final class TextPrompt: NSObject {
    private let window: NSWindow
    private let field: NSTextField
    private let checkbox: NSButton?
    private var response: NSApplication.ModalResponse = .cancel

    /// checkboxTitle 为 nil 时不显示勾选框;checkboxOn 为勾选框初始状态
    static func run(title: String, message: String, placeholder: String,
                    checkboxTitle: String? = nil, checkboxOn: Bool = false) -> (text: String, checked: Bool)? {
        let p = TextPrompt(title: title, message: message, placeholder: placeholder,
                           checkboxTitle: checkboxTitle, checkboxOn: checkboxOn)
        return p.present()
    }

    private init(title: String, message: String, placeholder: String,
                 checkboxTitle: String?, checkboxOn: Bool) {
        let width: CGFloat = 300
        let pad: CGFloat = 20

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)

        let msgLabel = NSTextField(labelWithString: message)
        msgLabel.font = .systemFont(ofSize: 12)
        msgLabel.textColor = .secondaryLabelColor

        field = EditableTextField(frame: .zero)
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)

        if let cbTitle = checkboxTitle {
            let cb = NSButton(checkboxWithTitle: cbTitle, target: nil, action: nil)
            cb.state = checkboxOn ? .on : .off
            cb.font = .systemFont(ofSize: 12)
            checkbox = cb
        } else {
            checkbox = nil
        }

        let okBtn = NSButton(title: "确定", target: nil, action: nil)
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r"
        let cancelBtn = NSButton(title: "取消", target: nil, action: nil)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}" // Esc

        let fieldHeight: CGFloat = 24
        let btnHeight: CGFloat = 28
        let checkHeight: CGFloat = checkbox == nil ? 0 : 20
        let checkGap: CGFloat = checkbox == nil ? 0 : 10
        let gap: CGFloat = 10
        let contentWidth = width - pad * 2
        let totalHeight = pad + 18 + 4 + 16 + gap + fieldHeight
            + checkGap + checkHeight + gap + btnHeight + pad

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: totalHeight),
            styleMask: [.titled],
            backing: .buffered, defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false

        super.init()

        let content = window.contentView!
        var views: [NSView] = [titleLabel, msgLabel, field, okBtn, cancelBtn]
        if let cb = checkbox { views.append(cb) }
        for v in views { content.addSubview(v) }

        var y = totalHeight - pad - 18
        titleLabel.frame = NSRect(x: pad, y: y, width: contentWidth, height: 18)
        y -= (4 + 16)
        msgLabel.frame = NSRect(x: pad, y: y, width: contentWidth, height: 16)
        y -= (gap + fieldHeight)
        field.frame = NSRect(x: pad, y: y, width: contentWidth, height: fieldHeight)
        if let cb = checkbox {
            y -= (checkGap + checkHeight)
            cb.frame = NSRect(x: pad, y: y, width: contentWidth, height: checkHeight)
        }
        y -= (gap + btnHeight)
        let btnWidth: CGFloat = 72
        okBtn.frame = NSRect(x: width - pad - btnWidth, y: y, width: btnWidth, height: btnHeight)
        cancelBtn.frame = NSRect(x: width - pad - btnWidth * 2 - 8, y: y, width: btnWidth, height: btnHeight)

        okBtn.target = self
        okBtn.action = #selector(confirm)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancel)
        window.initialFirstResponder = field
    }

    private func present() -> (text: String, checked: Bool)? {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        response = NSApp.runModal(for: window)
        window.orderOut(nil)
        guard response == .OK else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, checkbox?.state == .on)
    }

    @objc private func confirm() {
        response = .OK
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func cancel() {
        response = .cancel
        NSApp.stopModal(withCode: .cancel)
    }
}
