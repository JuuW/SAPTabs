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

    // 记录每个窗口 id 首次出现的序号,保证页签顺序稳定、不随 z-order 重排
    private var orderSeen: [String: Int] = [:]
    private var nextOrder: Int = 0
    // 每个系统 ID(标题前三字母)首次出现的序号,用于分组
    private var systemOrderSeen: [String: Int] = [:]
    private var nextSystemOrder: Int = 0

    // 同 (标题@位置) 撞车时,给每个 AX 元素分配并长期保留一个稳定区分号。
    // 必须锚定到元素身份而非遍历顺序,否则点击置顶会让撞车的两个窗口序号互换 → 重排。
    private var elementDiscriminators: [(element: AXUIElement, key: String, disc: Int)] = []

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
        // 本次刷新中仍存活的区分号条目索引,用于结束后清理已关闭窗口
        var liveDiscIdx = Set<Int>()

        for app in runningApps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            // 当前聚焦窗口的 AX 元素(用于高亮)。用元素身份比较而非标题,
            // 否则多个同标题窗口会被同时判为"当前"而一起高亮
            var focusedElement: AXUIElement? = nil
            if app.isActive {
                var focusedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
                   let focusedWin = focusedRef {
                    focusedElement = (focusedWin as! AXUIElement)
                }
            }

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let axWindows = windowsRef as? [AXUIElement] else { continue }

            for win in axWindows {
                let title = copyStringAttribute(win, kAXTitleAttribute) ?? "(未命名)"
                if managerWindowTitles.contains(title) { continue }

                // 稳定 id:pid + 标题 + 窗口位置。
                // 位置不随 z-order 变化,因此同标题的多个窗口(如三个 "DSC (1) (000)")
                // 在每次刷新都得到相同且互不相同的 id,排序不再因点击置顶而漂移。
                let baseKey = "\(app.processIdentifier)-\(title)"
                var wid: String
                if let p = windowPosition(win) {
                    wid = "\(baseKey)@\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
                } else {
                    wid = baseKey
                }
                // 位置也可能撞车(SAP 的多个同标题会话常叠在同一坐标 0,33),
                // 这会导致 id 重复 → 两个页签同时高亮、ForEach 渲染混乱。
                // 用锚定到 AX 元素身份的稳定区分号兜底:同一元素永远拿同一个号,
                // 不随 z-order 变,点击置顶不会让撞车的两个窗口序号互换。
                let (disc, idx) = discriminator(for: win, key: wid)
                liveDiscIdx.insert(idx)
                if disc > 0 { wid = "\(wid)#\(disc)" }

                result.append(SAPWindow(id: wid, title: title, axElement: win, pid: app.processIdentifier))

                // 按 AX 元素身份匹配聚焦窗口,避免同标题窗口一起高亮
                if let fe = focusedElement, CFEqual(fe, win), frontID == nil {
                    frontID = wid
                }
            }
        }

        // 清理已关闭窗口占用的区分号条目(保留本次仍存活的)
        elementDiscriminators = liveDiscIdx.sorted().map { elementDiscriminators[$0] }

        // 稳定排序:同系统页签聚在一起,组内按窗口打开时间先后
        let liveIDs = Set(result.map(\.id))
        orderSeen = orderSeen.filter { liveIDs.contains($0.key) } // 清理已关闭窗口
        for w in result where orderSeen[w.id] == nil {
            orderSeen[w.id] = nextOrder
            nextOrder += 1
        }

        // 登记每个系统首次出现的序号(系统 ID = 标题前三字母)
        let liveSystems = Set(result.map { systemID($0.title) })
        systemOrderSeen = systemOrderSeen.filter { liveSystems.contains($0.key) }
        // 按窗口打开顺序遍历,保证"先出现的系统"排在前面
        for w in result.sorted(by: { (orderSeen[$0.id] ?? 0) < (orderSeen[$1.id] ?? 0) }) {
            let sys = systemID(w.title)
            if systemOrderSeen[sys] == nil {
                systemOrderSeen[sys] = nextSystemOrder
                nextSystemOrder += 1
            }
        }

        // 两级排序:主键=系统首次出现序号,次键=窗口打开序号
        result.sort { a, b in
            let sa = systemOrderSeen[systemID(a.title)] ?? 0
            let sb = systemOrderSeen[systemID(b.title)] ?? 0
            if sa != sb { return sa < sb }
            return (orderSeen[a.id] ?? 0) < (orderSeen[b.id] ?? 0)
        }

        windows = result
        frontWindowID = frontID
    }

    /// 为 AX 元素返回其在同 key(标题@位置)下的稳定区分号及条目索引。
    /// 同一元素跨刷新永远拿同一个号(按身份 CFEqual 命中已有条目),
    /// 新元素才分配该 key 下尚未占用的最小非负整数。号不随 z-order 变。
    private func discriminator(for element: AXUIElement, key: String) -> (disc: Int, index: Int) {
        if let i = elementDiscriminators.firstIndex(where: { $0.key == key && CFEqual($0.element, element) }) {
            return (elementDiscriminators[i].disc, i)
        }
        let used = Set(elementDiscriminators.filter { $0.key == key }.map(\.disc))
        var d = 0
        while used.contains(d) { d += 1 }
        elementDiscriminators.append((element: element, key: key, disc: d))
        return (d, elementDiscriminators.count - 1)
    }

    /// 系统 ID:取窗口标题前三个字符(如 "I72 (1) (001)" → "I72")
    func systemID(_ title: String) -> String {
        String(title.prefix(3))
    }

    /// 系统的出现序号(第 0、1、2… 个出现的系统),供 UI 按顺序分配颜色,避免哈希撞色
    func systemIndex(for title: String) -> Int {
        systemOrderSeen[systemID(title)] ?? 0
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

    /// 关闭指定窗口(点其标题栏的关闭按钮)
    func close(_ window: SAPWindow) {
        var btnRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window.axElement, kAXCloseButtonAttribute as CFString, &btnRef) == .success,
           let btn = btnRef {
            AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
        }
        // 立即刷新,页签即时消失(SAP 若弹确认框则等用户处理后下次刷新再移除)
        refresh()
    }

    // MARK: - 辅助

    private func copyStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        guard err == .success else { return nil }
        return ref as? String
    }

    /// 读取窗口在屏幕上的位置(不随 z-order 变化),用于稳定区分同标题窗口
    private func windowPosition(_ element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(value as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }
}
