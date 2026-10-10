import AppKit
import ApplicationServices

/// 代表一个 SAP GUI 窗口
struct SAPWindow: Identifiable, Equatable {
    let id: String          // 用窗口标题 + 索引做稳定标识
    let title: String       // 显示在页签上的标题
    let axElement: AXUIElement
    let pid: pid_t

    static func == (lhs: SAPWindow, rhs: SAPWindow) -> Bool {
        lhs.id == rhs.id
    }
}

/// 负责枚举 SAP GUI 窗口、读取标题、切换聚焦
final class SAPWindowManager: ObservableObject {
    @Published var windows: [SAPWindow] = []
    @Published var frontWindowID: String? = nil
    @Published var accessibilityGranted: Bool = false

    // SAP GUI for Java 的进程名
    private let processName = "SAPGUI"
    // 连接管理器主窗口标题,过滤掉不作为页签
    private let managerWindowTitles: Set<String> = ["SAP GUI for Java"]

    private var timer: Timer?

    init() {
        checkAccessibility()
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 权限

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// 弹出系统授权引导(只会在未授权时提示)
    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 枚举

    func refresh() {
        checkAccessibility()
        guard accessibilityGranted else {
            windows = []
            return
        }

        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == processName || $0.bundleURL?.lastPathComponent.contains(processName) == true
        }

        var result: [SAPWindow] = []
        var frontID: String? = nil

        for app in runningApps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let axWindows = windowsRef as? [AXUIElement] else { continue }

            for (idx, win) in axWindows.enumerated() {
                let title = copyStringAttribute(win, kAXTitleAttribute) ?? "(未命名)"
                if managerWindowTitles.contains(title) { continue }

                let wid = "\(app.processIdentifier)-\(idx)-\(title)"
                result.append(SAPWindow(id: wid, title: title, axElement: win, pid: app.processIdentifier))

                // 判断是否为当前前台窗口
                if app.isActive, isMain(win) {
                    frontID = wid
                }
            }
        }

        // 只有变化时才赋值,减少 UI 抖动
        if result.map(\.id) != windows.map(\.id) {
            windows = result
        } else {
            // 标题可能变了(事务码切换),同步更新
            windows = result
        }
        frontWindowID = frontID
    }

    // MARK: - 切换

    func focus(_ window: SAPWindow) {
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        // 再设一次 main/focused,确保键盘输入进到这个窗口
        AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        frontWindowID = window.id
    }

    // MARK: - 辅助

    private func copyStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        guard err == .success else { return nil }
        return ref as? String
    }

    private func isMain(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &ref)
        guard err == .success, let num = ref as? Bool else { return false }
        return num
    }
}
