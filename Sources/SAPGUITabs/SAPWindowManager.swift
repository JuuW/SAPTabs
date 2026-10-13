import AppKit
import ApplicationServices

/// 代表一个 SAP GUI 窗口
struct SAPWindow: Identifiable, Equatable {
    let id: String          // 用窗口标题 + 索引做稳定标识
    let title: String       // 原始窗口标题(如 "DWC (1) (010)"),用于分组/提示/身份
    let tcode: String?      // 当前事务码(如 "/SCWM/MON"),仅用于显示,读不到为 nil
    let axElement: AXUIElement
    let pid: pid_t

    // 身份只看 id。tcode/title 变化不改变窗口是谁,避免显示文本混入身份判断
    static func == (lhs: SAPWindow, rhs: SAPWindow) -> Bool {
        lhs.id == rhs.id
    }

    // 显示内容是否完全一致(含 tcode/title)。用于判断页签是否真的需要重绘,
    // 避免每秒 refresh 即便内容没变也推送 @Published 变更、触发溢出布局抖动。
    func displayEquals(_ other: SAPWindow) -> Bool {
        id == other.id && title == other.title && tcode == other.tcode
    }
}

/// 负责枚举 SAP GUI 窗口、读取标题、切换聚焦
final class SAPWindowManager: ObservableObject {
    @Published var windows: [SAPWindow] = []
    @Published var frontWindowID: String? = nil
    @Published var accessibilityGranted: Bool = false

    // SAP GUI for Java 的进程名
    private let processName = "SAPGUI"

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
                // 只保留 SAP 会话窗口(标题形如 "EUP (1) (300)")。
                // 弹出框(如 "Information")、连接管理器("SAP GUI for Java")的
                // role/subrole/modal 都和会话窗口一样,无法用 AX 属性区分,
                // 只能靠标题格式过滤:三字母系统号 + " (数字) (数字)"。
                if !isSessionWindow(title) { continue }

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

                result.append(SAPWindow(id: wid, title: title, tcode: readTransactionCode(win), axElement: win, pid: app.processIdentifier))

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

        // 三级排序:
        //  主键=系统首次出现序号(同系统聚在一起)
        //  次键=组内按 TCode 字母序(不区分大小写);读不到 TCode 的(登录屏/弹窗/主屏)
        //       统一视为空串,排在该组最前
        //  末键=窗口打开序号,仅用于打破 TCode 相同时的平局,保证排序稳定、不随 z-order 漂移
        result.sort { a, b in
            let sa = systemOrderSeen[systemID(a.title)] ?? 0
            let sb = systemOrderSeen[systemID(b.title)] ?? 0
            if sa != sb { return sa < sb }
            let ca = a.tcode ?? ""
            let cb = b.tcode ?? ""
            let cmp = ca.localizedCaseInsensitiveCompare(cb)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return (orderSeen[a.id] ?? 0) < (orderSeen[b.id] ?? 0)
        }

        // 仅在内容真正变化时才赋值。每秒 refresh 若无脑替换 @Published 数组,
        // 即便窗口集合和 TCode 都没变,也会每秒触发重绘 → 溢出布局反复重算 →
        // 下拉按钮/菜单不停闪烁(菜单打开时尤为明显)。深比较后无变化则跳过。
        if !sameWindows(windows, result) {
            windows = result
        }
        if frontWindowID != frontID {
            frontWindowID = frontID
        }
    }

    /// 两个窗口列表的显示内容是否完全一致(顺序 + id + title + tcode)
    private func sameWindows(_ a: [SAPWindow], _ b: [SAPWindow]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where !x.displayEquals(y) { return false }
        return true
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

    /// 完整显示标签:系统 ID + 当前事务码(如 "DWC /SCWM/MON")。
    /// 读不到事务码时只显系统 ID。供溢出下拉菜单等"扁平列表、无分组标签"的场景用;
    /// 页签本身因有独立的系统 ID 组标签,正文只显 TCode,不走这里。
    func fullLabel(for window: SAPWindow) -> String {
        let sys = systemID(window.title)
        if let code = window.tcode, !code.isEmpty {
            return "\(sys) \(code)"
        }
        return sys
    }

    /// 判定是否为 SAP 会话窗口。会话标题形如 "EUP (1) (300)":
    /// 任意系统号开头 + 一个 " (数字)" 会话号 + 一个 " (数字)" client 号。
    /// 弹出框/连接管理器不符合此格式,据此过滤掉。
    private func isSessionWindow(_ title: String) -> Bool {
        title.range(of: #"\(\d+\) \(\d+\)$"#, options: .regularExpression) != nil
    }

    /// 系统的出现序号(第 0、1、2… 个出现的系统),供 UI 按顺序分配颜色,避免哈希撞色
    func systemIndex(for title: String) -> Int {
        systemOrderSeen[systemID(title)] ?? 0
    }

    // MARK: - 切换

    func focus(_ window: SAPWindow) {
        // 先把高亮切过去,UI 立即响应,不等跨进程 AX 调用
        frontWindowID = window.id

        // 先在 App 内部把目标窗口抬到最前并设为 main,
        // 再激活整个 App。顺序反了会先激活 App、动画期间 raise 作用在旧窗口上,
        // 看起来就"慢半拍"。
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }
    }

    /// 向当前前台 SAP 会话的 OK Code(命令)输入框填入文本,可选回车执行。
    ///
    /// SAP GUI for Java 的命令框**不接受** AXSetValue 直接写值(调用返回成功但值不进去),
    /// 必须:先把该字段设为 AXFocused,再用 CGEvent 键盘事件逐字符键入。回读 AXValue 可确认。
    /// 定位:前台会话窗口 → system toolbar 子节点 → AXTextField 且 desc="command field"。
    func writeCommand(_ text: String, execute: Bool) {
        guard accessibilityGranted else { return }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == processName || $0.bundleURL?.lastPathComponent.contains(processName) == true
        }
        guard let app = apps.first(where: { $0.isActive }) ?? apps.first else { return }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)

        var fref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &fref) == .success,
              let fw = fref else { return }
        let win = fw as! AXUIElement
        guard let field = commandField(in: win) else { return }

        // 激活 App 并聚焦命令框(SAP Java 控件只认键盘事件,必须先拿到焦点)
        app.activate()
        usleep(120_000)
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(120_000)

        let src = CGEventSource(stateID: .combinedSessionState)
        for ch in text.unicodeScalars {
            var u = UniChar(ch.value)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
            up?.post(tap: .cghidEventTap)
            usleep(15_000)
        }

        if execute {
            usleep(60_000)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true) // Return
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// 在会话窗口里定位 OK Code 命令输入框(system toolbar 下的 command field)
    private func commandField(in window: AXUIElement) -> AXUIElement? {
        var topRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &topRef) == .success,
              let top = topRef as? [AXUIElement] else { return nil }
        for tb in top where copyStringAttribute(tb, kAXDescriptionAttribute) == "system toolbar" {
            var kidsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(tb, kAXChildrenAttribute as CFString, &kidsRef) == .success,
                  let kids = kidsRef as? [AXUIElement] else { continue }
            for c in kids where copyStringAttribute(c, kAXRoleAttribute) == "AXTextField"
                && copyStringAttribute(c, kAXDescriptionAttribute) == "command field" {
                return c
            }
        }
        return nil
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

    /// 读取窗口当前事务码,如 "/SCWM/MON"。读不到(登录屏/弹窗/主屏)返回 nil。
    ///
    /// 数据来源:状态栏那个系统信息下拉。它是**窗口的直接子节点**,
    /// 特征为 AXComboBox + desc="Show menu",其 value 形如 "System DWC"
    /// (有时直接是 "Transaction SE38")。真正的事务码在它子树里一行
    /// AXRow,desc 形如 "Transaction /SCWM/MON"。
    ///
    /// 关键:只在这一个 ComboBox 的子树里找,绝不遍历整窗口——主数据区的
    /// 字段子树单窗口可达近两万节点,盲目遍历会让每秒刷新卡死(实测 >1s)。
    /// 定位到 ComboBox 后其子树很小,查找开销可忽略。
    private func readTransactionCode(_ window: AXUIElement) -> String? {
        // 1. 在窗口直接子节点里找信息下拉 ComboBox
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let topChildren = childrenRef as? [AXUIElement] else { return nil }

        for child in topChildren {
            guard copyStringAttribute(child, kAXRoleAttribute) == "AXComboBox",
                  copyStringAttribute(child, kAXDescriptionAttribute) == "Show menu" else { continue }

            // 快速路径:ComboBox 的 value 有时直接就是 "Transaction SE38"
            if let v = copyStringAttribute(child, kAXValueAttribute),
               let code = tcode(fromDescription: v) {
                return code
            }
            // 否则在这个 ComboBox 的(很小的)子树里找 Transaction 行
            return findTransactionRow(child, depth: 0)
        }
        return nil
    }

    /// 在给定元素子树内找 "Transaction xxx" 行,返回事务码。限定浅层深度即可。
    private func findTransactionRow(_ el: AXUIElement, depth: Int) -> String? {
        if depth > 8 { return nil }
        if copyStringAttribute(el, kAXRoleAttribute) == "AXRow",
           let desc = copyStringAttribute(el, kAXDescriptionAttribute),
           let code = tcode(fromDescription: desc) {
            return code
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let kids = childrenRef as? [AXUIElement] {
            for k in kids {
                if let found = findTransactionRow(k, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    /// 从 "Transaction /SCWM/MON" 这类字符串里取出事务码;
    /// 不是 Transaction 行、或码为空(登录屏显示 "Transaction ")则返回 nil
    private func tcode(fromDescription desc: String) -> String? {
        let prefix = "Transaction "
        guard desc.hasPrefix(prefix) else { return nil }
        let code = String(desc.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return code.isEmpty ? nil : code
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
