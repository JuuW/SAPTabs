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
        .padding(.horizontal, 8)
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
        }
    }

    private func chip(win: SAPWindow, idx: Int) -> some View {
        // 组首(与上一页签系统不同,或第 0 个)在页签前显示一次系统 ID 标签,
        // 组内其余页签不再重复系统 ID,只显 TCode
        let isGroupHead = idx == 0 || isSystemBoundary(at: idx)
        return TabChip(
            title: displayLabel(win),
            isActive: win.id == manager.frontWindowID,
            leadingSystemID: isGroupHead ? manager.systemID(win.title) : nil
        )
        .onTapGesture { manager.focus(win) }
        .contextMenu {
            Button(role: .destructive) { manager.close(win) } label: {
                Label("关闭", systemImage: "xmark")
            }
        }
        .help("\(win.title)\n单击切换 · 右键关闭")
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
            .fixedSize()
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
        btn.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "TCode")?
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

        init(manager: SAPWindowManager, store: TCodeStore) {
            self.manager = manager
            self.store = store
        }

        /// 菜单打开后,给它的宿主窗口垫一层不透明底色,盖住 vibrancy 透出的后方内容
        func menuDidClose(_ menu: NSMenu) {}
        func menuWillOpen(_ menu: NSMenu) {
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
            let menu = buildMenu(for: store.root, path: [])
            let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
            menu.popUp(positioning: nil, at: origin, in: sender)
        }

        /// 递归构建某一级菜单:先列该级节点(文件夹→子菜单,TCode→可点击叶子),
        /// 末尾加分隔线 + Add TCode + Add Folder(都作用于本级 path)。
        private func buildMenu(for nodes: [TCodeNode], path: [String]) -> NSMenu {
            let menu = NSMenu()
            menu.appearance = NSAppearance(named: .aqua)   // 避免 vibrancy 半透明
            menu.delegate = self

            for node in nodes {
                switch node {
                case .code(let code):
                    let item = NSMenuItem(title: code, action: #selector(runTCode(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = code
                    menu.addItem(item)
                case .folder(let name, let children):
                    let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                    // 文件夹用加粗字体区分普通 TCode 项
                    item.attributedTitle = NSAttributedString(string: name, attributes: [
                        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                    ])
                    item.submenu = buildMenu(for: children, path: path + [name])
                    menu.addItem(item)
                }
            }

            menu.addItem(.separator())
            let addCode = NSMenuItem(title: "Add TCode", action: #selector(addCurrentTCode(_:)), keyEquivalent: "")
            addCode.target = self
            addCode.representedObject = path
            menu.addItem(addCode)
            let addFolder = NSMenuItem(title: "Add Folder", action: #selector(addFolder(_:)), keyEquivalent: "")
            addFolder.target = self
            addFolder.representedObject = path
            menu.addItem(addFolder)
            return menu
        }

        /// 点选事务码:默认加 /o(另开新窗口),按住 Option(Alt)则 /n(当前窗口切新事务)
        @objc private func runTCode(_ sender: NSMenuItem) {
            guard let code = sender.representedObject as? String else { return }
            let opt = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
            manager.writeCommand((opt ? "/n" : "/o") + code, execute: true)
        }

        /// 抓当前前台会话正在跑的事务码加入到该级;成功静默,读不到/已存在则弹提示
        @objc private func addCurrentTCode(_ sender: NSMenuItem) {
            let path = sender.representedObject as? [String] ?? []
            guard let code = manager.frontmostTCode(), !code.isEmpty else {
                alert("无法添加", "当前前台会话没有正在运行的事务码(可能停在登录屏或主屏)。")
                return
            }
            if !store.addCode(code, at: path) {
                alert("已存在", "事务码 \"\(code)\" 已在该文件夹中。")
            }
        }

        /// 在该级新建文件夹:弹框输入名字,重名则提示
        @objc private func addFolder(_ sender: NSMenuItem) {
            let path = sender.representedObject as? [String] ?? []
            guard let name = promptForFolderName(), !name.isEmpty else { return }
            if !store.addFolder(name, at: path) {
                alert("已存在", "文件夹 \"\(name)\" 已在该层级中。")
            }
        }

        /// 弹出带输入框的对话框,返回用户输入的文件夹名(取消返回 nil)
        private func promptForFolderName() -> String? {
            let a = NSAlert()
            a.messageText = "新建文件夹"
            a.informativeText = "请输入文件夹名称:"
            a.addButton(withTitle: "确定")
            a.addButton(withTitle: "取消")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            field.placeholderString = "文件夹名"
            a.accessoryView = field
            a.window.initialFirstResponder = field
            return a.runModal() == .alertFirstButtonReturn
                ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
        }

        private func alert(_ title: String, _ msg: String) {
            let a = NSAlert()
            a.messageText = title
            a.informativeText = msg
            a.addButton(withTitle: "好")
            a.runModal()
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
