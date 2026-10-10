import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = SAPWindowManager()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupStatusItem()
        manager.start()
        // 首次运行若无权限,主动引导
        if !manager.accessibilityGranted {
            manager.promptAccessibility()
        }
    }

    private func setupPanel() {
        let hosting = NSHostingView(rootView: TabBarView(manager: manager))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 28),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = hosting
        panel.hidesOnDeactivate = false

        // 默认停在屏幕顶部居中
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w: CGFloat = 520, h: CGFloat = 28
            panel.setFrame(
                NSRect(x: f.midX - w / 2, y: f.maxY - h - 8, width: w, height: h),
                display: true
            )
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "SAP Tabs")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "显示 / 隐藏页签条", action: #selector(togglePanel), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "刷新", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SAP Tabs", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) }
        else { panel.orderFrontRegardless() }
    }

    @objc private func refreshNow() { manager.refresh() }

    @objc private func quit() {
        manager.stop()
        NSApp.terminate(nil)
    }
}

// MARK: - 启动入口(顶层代码)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 菜单栏模式,不占 Dock
app.run()
