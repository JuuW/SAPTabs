import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = SAPWindowManager()
    private let tcodeStore = TCodeStore()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!

    // SAPGUI 的 bundle id,只在它处于前台时显示面板
    private let sapBundleID = "com.sap.platin"
    // 用户是否通过菜单手动隐藏了面板(手动隐藏时不自动弹出)
    private var manuallyHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupStatusItem()
        manager.start()
        // 首次运行若无权限,主动引导
        if !manager.accessibilityGranted {
            manager.promptAccessibility()
        }

        // 监听前台 app 切换,只在 SAPGUI 在前台时显示面板
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self,
                       selector: #selector(activeAppChanged(_:)),
                       name: NSWorkspace.didActivateApplicationNotification,
                       object: nil)
        updatePanelVisibility() // 启动时按当前前台 app 决定显隐
    }

    @objc private func activeAppChanged(_ note: Notification) {
        updatePanelVisibility()
    }

    /// 根据当前前台 app 是否为 SAPGUI 来显隐面板
    private func updatePanelVisibility() {
        guard !manuallyHidden else { return }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if frontID == sapBundleID {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func setupPanel() {
        let hosting = NSHostingView(rootView: TabBarView(manager: manager, tcodeStore: tcodeStore))

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
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = hosting
        panel.hidesOnDeactivate = false

        positionPanel(panel)
        self.panel = panel

        // 屏幕分辨率/排布变化时重新按 90% 居中
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            if let p = self?.panel { self?.positionPanel(p) }
        }
    }

    // 固定:当前屏幕宽度的 90%、水平居中、紧贴屏幕最上方;高度固定 32
    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let w = f.width * 0.9
        let h: CGFloat = 28   // 与 macOS 标准标题栏(SAP GUI 关闭按钮那行)等高
        panel.setFrame(
            NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h),
            display: true
        )
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "SAP Tabs")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "启用 / 停用自动显示", action: #selector(togglePanel), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "刷新", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SAP Tabs", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func togglePanel() {
        manuallyHidden.toggle()
        if manuallyHidden {
            panel.orderOut(nil)
        } else {
            updatePanelVisibility()
        }
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
