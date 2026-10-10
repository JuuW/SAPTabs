import SwiftUI

struct TabBarView: View {
    @ObservedObject var manager: SAPWindowManager

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
        .padding(.vertical, 3)
        .frame(minWidth: 220, maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(.ultraThinMaterial)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(manager.windows) { win in
                    TabChip(
                        title: shortTitle(win.title),
                        isActive: win.id == manager.frontWindowID
                    )
                    .onTapGesture { manager.focus(win) }
                    .help(win.title)
                }
            }
        }
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

    /// SAP 窗口标题常形如 "I72 (1) (001)",保留系统名+会话号即可
    private func shortTitle(_ t: String) -> String {
        return t
    }
}

struct TabChip: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.9) : Color.gray.opacity(0.18))
            )
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}
