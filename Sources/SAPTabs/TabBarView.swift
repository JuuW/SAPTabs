import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var manager: SAPWindowManager
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
        OverflowTabsLayout(count: manager.windows.count, reserve: 40, state: overflow) {
            // 子视图顺序:所有页签,最后一个是溢出按钮
            ForEach(Array(manager.windows.enumerated()), id: \.element.id) { idx, win in
                chip(win: win, idx: idx)
            }
            OverflowMenuView(manager: manager, state: overflow)
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
                    .font(.system(size: 14, weight: .bold))
                    .hidden()
                Text(title)
                    .font(.system(size: 14, weight: isActive ? .bold : .regular))
                    .foregroundStyle(Color.primary)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 11)
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
    @ObservedObject var state: OverflowState

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

/// 右端溢出按钮:下拉列出放不下的页签,可切换与关闭
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
                        Button { manager.focus(win) } label: { Text(win.title) }
                        Button(role: .destructive) { manager.close(win) } label: {
                            Label("关闭 \(win.title)", systemImage: "xmark")
                        }
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
