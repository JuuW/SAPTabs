import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = SAPWindowManager()
    private let tcodeStore = TCodeStore()
    private let defaultsStore = DefaultsStore()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!

    // 菜单即将弹出那一刻抓到的前台窗口字段列表(系统/tcode/候选字段)。
    // 在 menuWillOpen 抓:此刻前台还是 SAP;菜单打开后前台会切到本 app。
    private var capturedChoices: (system: String, tcode: String, fields: [String])?
    private weak var addDefaultItem: NSMenuItem?
    private weak var hotKeyMenuItem: NSMenuItem?

    // SAPGUI 的 bundle id,只在它处于前台时显示面板
    private let sapBundleID = "com.sap.platin"
    // 用户是否通过菜单手动隐藏了面板(手动隐藏时不自动弹出)
    private var manuallyHidden = false

    // 全局快捷键监听(复制鼠标所指 SAP 树节点的完整路径)。键位可在菜单里配置。
    private var hotKeyMonitor: Any?
    // 当前快捷键:keyCode + 修饰键。默认 ⌥⌘P(keyCode 35 = P)。
    private var hotKeyCode: UInt16 = 35
    private var hotKeyMods: NSEvent.ModifierFlags = [.command, .option]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupStatusItem()
        manager.defaultsStore = defaultsStore
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
        setupHotKey()
    }

    /// 注册全局快捷键:把鼠标当前所指的 SAP 树节点完整路径复制到剪贴板。
    /// 键位从 UserDefaults 读取(默认 ⌥⌘P),可在菜单里重新配置。
    /// 用全局事件监听(依赖辅助功能权限,本 app 已具备)。只在 SAPGUI 前台时响应。
    private func setupHotKey() {
        loadHotKey()
        reregisterHotKey()
    }

    private let hotKeyCodeKey = "treePathHotKeyCode"
    private let hotKeyModsKey = "treePathHotKeyMods"

    /// 从 UserDefaults 读取已保存的快捷键;没存过则保持默认 ⌥⌘P。
    private func loadHotKey() {
        let d = UserDefaults.standard
        if d.object(forKey: hotKeyCodeKey) != nil {
            hotKeyCode = UInt16(d.integer(forKey: hotKeyCodeKey))
            hotKeyMods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: hotKeyModsKey)))
        }
    }

    private func saveHotKey() {
        let d = UserDefaults.standard
        d.set(Int(hotKeyCode), forKey: hotKeyCodeKey)
        d.set(Int(hotKeyMods.rawValue), forKey: hotKeyModsKey)
    }

    private func copyTreePath() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == sapBundleID else { return }
        if let path = manager.copyTreePathAtMouse() {
            showHUD("已复制路径", detail: path)
        } else {
            showHUD("未取到路径", detail: "请把鼠标停在 SAP 树的某个节点上再按 ⌥⌘P")
        }
    }

    /// 顶部短暂浮现一条提示(非激活面板,不抢焦点),2 秒后自动消失。
    private func showHUD(_ title: String, detail: String) {
        let text = "\(title):\(detail)"
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1

        let pad: CGFloat = 12
        let maxW: CGFloat = 900
        label.preferredMaxLayoutWidth = maxW
        var size = label.intrinsicContentSize
        size.width = min(size.width, maxW)
        let w = size.width + pad * 2, h: CGFloat = 26

        let hud = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        hud.level = .floating
        hud.isFloatingPanel = true
        hud.backgroundColor = NSColor(white: 0, alpha: 0.82)
        hud.isOpaque = false
        hud.hasShadow = true
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        label.frame = NSRect(x: pad, y: (h - size.height) / 2, width: size.width, height: size.height)
        hud.contentView?.addSubview(label)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            hud.setFrameOrigin(NSPoint(x: f.midX - w / 2, y: f.maxY - h - 40))
        }
        hud.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { hud.orderOut(nil) }
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
            button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "SAP GUI Tabs")
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false   // 手动控制"添加默认值"项的启用态
        menu.addItem(withTitle: "启用 / 停用自动显示", action: #selector(togglePanel), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "刷新", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "重新加载默认值配置", action: #selector(reloadDefaults), keyEquivalent: "").target = self
        let addItem = NSMenuItem(title: "添加当前页面字段默认值…", action: #selector(addCurrentFieldDefault), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
        addDefaultItem = addItem
        let hotKeyItem = NSMenuItem(title: "设置抓取 IMG 配置路径的快捷键…", action: #selector(configureHotKey), keyEquivalent: "")
        hotKeyItem.target = self
        menu.addItem(hotKeyItem)
        hotKeyMenuItem = hotKeyItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SAP GUI Tabs", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    /// 把 keyCode + 修饰键转成可读字符串,如 "⌥⌘P"。
    private func hotKeyDisplay() -> String {
        var s = ""
        if hotKeyMods.contains(.control) { s += "⌃" }
        if hotKeyMods.contains(.option)  { s += "⌥" }
        if hotKeyMods.contains(.shift)   { s += "⇧" }
        if hotKeyMods.contains(.command) { s += "⌘" }
        return s + Self.keyName(for: hotKeyCode)
    }

    /// 常见键的 keyCode → 字符。覆盖字母数字及少量常用键;其余回退显示码号。
    private static func keyName(for code: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A",11:"B",8:"C",2:"D",14:"E",3:"F",5:"G",4:"H",34:"I",38:"J",40:"K",37:"L",
            46:"M",45:"N",31:"O",35:"P",12:"Q",15:"R",1:"S",17:"T",32:"U",9:"V",13:"W",7:"X",16:"Y",6:"Z",
            29:"0",18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9",
            49:"Space",36:"↩",48:"⇥",53:"⎋",51:"⌫",
            123:"←",124:"→",125:"↓",126:"↑",
            122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",
        ]
        return map[code] ?? "Key\(code)"
    }

    // MARK: - NSMenuDelegate

    /// 菜单弹出前抓住前台窗口的字段列表,并据此启用/禁用"添加默认值"。
    func menuWillOpen(_ menu: NSMenu) {
        hotKeyMenuItem?.title = "设置抓取 IMG 配置路径的快捷键(当前 \(hotKeyDisplay()))…"
        capturedChoices = manager.captureFieldChoices()
        if let c = capturedChoices {
            addDefaultItem?.isEnabled = true
            addDefaultItem?.title = "添加默认值:\(c.system) / \(c.tcode)…"
        } else {
            addDefaultItem?.isEnabled = false
            addDefaultItem?.title = "添加当前页面字段默认值(需前台为 SAP 会话)"
        }
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

    @objc private func reloadDefaults() {
        defaultsStore.reload()
        manager.resetFilledState()   // 清去重记录,让新配置对在场窗口立即生效,不必重登
    }

    /// 用菜单弹出前抓到的前台窗口字段列表,弹框让用户选字段 + 输入默认值并写入配置。
    @objc private func addCurrentFieldDefault() {
        guard let c = capturedChoices else { return }

        let alert = NSAlert()
        alert.messageText = "添加字段默认值"
        alert.informativeText = "系统:\(c.system)   事务码:\(c.tcode)\n选择字段并填入默认值。下次进入该窗口的此事务码时,若字段为空将自动填入。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        // accessoryView:上方字段下拉 + 下方默认值输入框
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 300, height: 26), pullsDown: false)
        popup.addItems(withTitles: c.fields)
        container.addSubview(popup)

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "要自动填入的默认值"
        container.addSubview(input)

        alert.accessoryView = container
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let field = popup.titleOfSelectedItem else { return }
        let value = input.stringValue

        let ok = defaultsStore.addRule(system: c.system, tcode: c.tcode, field: field, value: value)
        if ok { manager.resetFilledState() }   // 立即生效:清去重记录,下次刷新即按新规则填
        let done = NSAlert()
        if ok {
            done.messageText = "已保存"
            done.informativeText = "\(c.system),\(c.tcode),\(field) = \(value)"
        } else {
            done.messageText = "保存失败"
            done.informativeText = "写入配置文件时出错,请检查 ~/.sapguitabs_defaults.json 是否可写。"
        }
        done.addButton(withTitle: "好")
        done.runModal()
    }

    /// 弹框录制新快捷键:按下任意「修饰键 + 主键」即实时显示,点保存落盘并重挂监听。
    /// 要求至少含一个修饰键(⌘/⌥/⌃/⇧),否则视为非法、保存按钮禁用。
    @objc private func configureHotKey() {
        let alert = NSAlert()
        alert.messageText = "设置抓取 IMG 配置路径的快捷键"
        alert.informativeText = "按下新的快捷键组合(需至少一个修饰键),然后点保存。\n当前:\(hotKeyDisplay())"
        let saveButton = alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let label = NSTextField(labelWithString: hotKeyDisplay())
        label.font = .systemFont(ofSize: 22, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
        alert.accessoryView = label

        // 录制态:初值为当前键位;合法时才允许保存
        var newCode = hotKeyCode
        var newMods = hotKeyMods
        saveButton.isEnabled = true

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil }   // 纯主键忽略,必须带修饰键
            newCode = event.keyCode
            newMods = mods
            var s = ""
            if mods.contains(.control) { s += "⌃" }
            if mods.contains(.option)  { s += "⌥" }
            if mods.contains(.shift)   { s += "⇧" }
            if mods.contains(.command) { s += "⌘" }
            label.stringValue = s + Self.keyName(for: event.keyCode)
            saveButton.isEnabled = true
            return nil   // 吞掉事件,避免触发系统/本窗口行为
        }

        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        guard result == .alertFirstButtonReturn else { return }

        hotKeyCode = newCode
        hotKeyMods = newMods
        saveHotKey()
        reregisterHotKey()
    }

    /// 配置变更后:摘掉旧全局监听,按新键位重新挂一个。
    private func reregisterHotKey() {
        if let m = hotKeyMonitor { NSEvent.removeMonitor(m) }
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard event.keyCode == self.hotKeyCode, mods == self.hotKeyMods else { return }
            self.copyTreePath()
        }
    }

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
