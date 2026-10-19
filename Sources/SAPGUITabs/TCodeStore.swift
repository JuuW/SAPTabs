import Foundation

/// 收藏树的节点:事务码(叶子)、普通文本(叶子)、或文件夹(含子节点)。
/// - code:事务码,点击填入 OK Code 并执行,显示时前面带闪电图标。
/// - text:普通文本,点击只复制到剪贴板,不进 OK Code。
/// 叶子(code/text)有三个字段:
///   - display:显示用文本(必填,也是排序/判重依据)
///   - value:点击时实际拷贝/执行的内容(可空;空则回退用 display)
///   - note:一段备注(可空),显示时右对齐、字号小一号
enum TCodeNode: Codable, Equatable {
    case code(display: String, value: String, note: String)
    case text(display: String, value: String, note: String)
    case folder(name: String, children: [TCodeNode])

    /// 排序 / 显示用的名字(folder 用名字,叶子用 display)
    var sortName: String {
        switch self {
        case .code(let d, _, _): return d
        case .text(let d, _, _): return d
        case .folder(let n, _): return n
        }
    }
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    /// 同级排序的类别优先级:文件夹(0) < 事务码(1) < 普通文本(2),同类再按字母序
    var sortRank: Int {
        switch self {
        case .folder: return 0
        case .code:   return 1
        case .text:   return 2
        }
    }

    // 自定义编解码:
    //   {"type":"code","display":"类编辑器","value":"SE24","note":"..."}
    //   {"type":"text","display":"随便记点东西","value":"","note":""}
    //   {"type":"folder","name":"Dev","children":[...]}
    // 兼容旧格式:旧叶子只有 "value" 字段(既显示又拷贝)。缺 display 时把旧 value 当 display、
    // 新 value 置空(即点击仍拷贝 display,行为不变)。note 缺省按空串。
    private enum CodingKeys: String, CodingKey { case type, display, value, name, children, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func leaf() throws -> (String, String, String) {
            let note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            let rawValue = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
            if let display = try c.decodeIfPresent(String.self, forKey: .display) {
                return (display, rawValue, note)          // 新格式
            }
            return (rawValue, "", note)                   // 旧格式:value 即 display
        }
        switch try c.decode(String.self, forKey: .type) {
        case "folder":
            let name = try c.decode(String.self, forKey: .name)
            let children = try c.decodeIfPresent([TCodeNode].self, forKey: .children) ?? []
            self = .folder(name: name, children: children)
        case "text":
            let (d, v, n) = try leaf()
            self = .text(display: d, value: v, note: n)
        default:
            let (d, v, n) = try leaf()
            self = .code(display: d, value: v, note: n)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .code(let d, let v, let note):
            try c.encode("code", forKey: .type)
            try c.encode(d, forKey: .display)
            try c.encode(v, forKey: .value)
            try c.encode(note, forKey: .note)
        case .text(let d, let v, let note):
            try c.encode("text", forKey: .type)
            try c.encode(d, forKey: .display)
            try c.encode(v, forKey: .value)
            try c.encode(note, forKey: .note)
        case .folder(let name, let children):
            try c.encode("folder", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(children, forKey: .children)
        }
    }
}

/// 收藏的事务码树,持久化到 ~/.sapguitabs_tcodes.json。
/// 每一级:文件夹优先、再按名称字母序(不区分大小写)。供页签栏左侧多级下拉菜单使用。
///
/// 兼容旧格式:早期是扁平的 ["SE24","SPRO"] 字符串数组,load 时若识别到旧格式则升级为叶子节点。
final class TCodeStore: ObservableObject {
    @Published private(set) var root: [TCodeNode] = []

    private let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sapguitabs_tcodes.json")
    }()

    init() { load() }

    /// 用一棵新树整体替换收藏(管理窗口拖拽重排后写回)。会递归排序并落盘。
    func replaceRoot(_ newRoot: [TCodeNode]) {
        var t = newRoot
        sortTree(&t)
        root = t
        save()
    }

    /// 在指定文件夹路径下添加事务码。路径为空表示根级。
    /// 该级已存在同名(按 display,不区分大小写)返回 false;否则加入、排序、落盘返回 true。
    @discardableResult
    func addCode(_ raw: String, value: String = "", note: String = "", at path: [String]) -> Bool {
        let display = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !display.isEmpty else { return false }
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return mutate(at: path) { children in
            if children.contains(where: {
                if case .code(let d, _, _) = $0 { return d.caseInsensitiveCompare(display) == .orderedSame }
                return false
            }) { return false }
            children.append(.code(display: display, value: value, note: note))
            return true
        }
    }

    /// 在指定文件夹路径下添加普通文本节点(点击只复制到剪贴板)。
    /// 该级已存在完全相同 display 返回 false。
    @discardableResult
    func addText(_ raw: String, value: String = "", note: String = "", at path: [String]) -> Bool {
        let display = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !display.isEmpty else { return false }
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return mutate(at: path) { children in
            if children.contains(where: {
                if case .text(let d, _, _) = $0 { return d == display }
                return false
            }) { return false }
            children.append(.text(display: display, value: value, note: note))
            return true
        }
    }

    /// 在指定文件夹路径下新建子文件夹。该级已存在同名文件夹返回 false。
    @discardableResult
    func addFolder(_ raw: String, at path: [String]) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return mutate(at: path) { children in
            if children.contains(where: {
                if case .folder(let n, _) = $0 { return n.caseInsensitiveCompare(name) == .orderedSame }
                return false
            }) { return false }
            children.append(.folder(name: name, children: []))
            return true
        }
    }

    // MARK: - 内部

    /// 删除 path 层级下的某个事务码(按 display 匹配)
    @discardableResult
    func removeCode(_ display: String, at path: [String]) -> Bool {
        mutate(at: path) { children in
            let before = children.count
            children.removeAll {
                if case .code(let d, _, _) = $0 { return d.caseInsensitiveCompare(display) == .orderedSame }
                return false
            }
            return children.count != before
        }
    }

    /// 删除 path 层级下的某个普通文本节点(按完全相同 display 匹配)
    @discardableResult
    func removeText(_ display: String, at path: [String]) -> Bool {
        mutate(at: path) { children in
            let before = children.count
            children.removeAll {
                if case .text(let d, _, _) = $0 { return d == display }
                return false
            }
            return children.count != before
        }
    }

    /// 删除 path 层级下的某个文件夹(连同其所有子内容)
    @discardableResult
    func removeFolder(_ name: String, at path: [String]) -> Bool {
        mutate(at: path) { children in
            let before = children.count
            children.removeAll {
                if case .folder(let n, _) = $0 { return n.caseInsensitiveCompare(name) == .orderedSame }
                return false
            }
            return children.count != before
        }
    }

    /// 返回 path 层级下的直接子节点(供删除菜单列出本级各项)
    func children(at path: [String]) -> [TCodeNode] {
        var nodes = root
        for name in path {
            guard let next = nodes.first(where: {
                if case .folder(let n, _) = $0 { return n.caseInsensitiveCompare(name) == .orderedSame }
                return false
            }), case .folder(_, let kids) = next else { return [] }
            nodes = kids
        }
        return nodes
    }


    /// 定位到 path 指向的子节点数组,交给 body 修改(返回是否发生有效改动)。
    /// 改动后对该级排序并落盘。
    private func mutate(at path: [String], _ body: (inout [TCodeNode]) -> Bool) -> Bool {
        var changed = false
        root = applying(path: path, to: root) { children in
            changed = body(&children)
            if changed { Self.sort(&children) }
        }
        if changed { save() }
        return changed
    }

    /// 递归下钻到 path,对目标层的 children 执行 transform,返回新的本层数组
    private func applying(path: [String], to nodes: [TCodeNode],
                          _ transform: (inout [TCodeNode]) -> Void) -> [TCodeNode] {
        guard let head = path.first else {
            var copy = nodes
            transform(&copy)
            return copy
        }
        return nodes.map { node in
            if case .folder(let name, let children) = node,
               name.caseInsensitiveCompare(head) == .orderedSame {
                return .folder(name: name, children: applying(path: Array(path.dropFirst()), to: children, transform))
            }
            return node
        }
    }

    /// 文件夹在前、其次事务码、最后普通文本;同类再按名称字母序(不区分大小写)
    private static func sort(_ nodes: inout [TCodeNode]) {
        nodes.sort { a, b in
            if a.sortRank != b.sortRank { return a.sortRank < b.sortRank }
            return a.sortName.localizedCaseInsensitiveCompare(b.sortName) == .orderedAscending
        }
    }

    private func sortTree(_ nodes: inout [TCodeNode]) {
        Self.sort(&nodes)
        for i in nodes.indices {
            if case .folder(let name, var children) = nodes[i] {
                sortTree(&children)
                nodes[i] = .folder(name: name, children: children)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // 新格式:节点树
        if let tree = try? JSONDecoder().decode([TCodeNode].self, from: data) {
            var t = tree
            sortTree(&t)
            root = t
            return
        }
        // 旧格式:扁平字符串数组 → 升级为根级叶子
        if let flat = try? JSONDecoder().decode([String].self, from: data) {
            var t = flat.map { TCodeNode.code(display: $0, value: "", note: "") }
            sortTree(&t)
            root = t
            save() // 顺手写回新格式
        }
    }

    private func save() {
        let json = Self.serialize(root)
        guard let data = json.data(using: .utf8) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 自定义 JSON 序列化(仍是合法 JSON,load 用标准 JSONDecoder 读回)
    //
    // 目标排版:叶子(code/text)压成一行,文件夹(含 children 数组)分行缩进。
    // 键按固定语义顺序输出:type → display/name → value → note → children。
    // JSONEncoder 的 .prettyPrinted 做不到"叶子单行、容器展开"的混合排版,故手写。

    /// 把一层节点数组序列化成带缩进的 JSON 文本。indent 为当前层缩进(空格串)。
    private static func serialize(_ nodes: [TCodeNode], indent: String = "") -> String {
        if nodes.isEmpty { return "[]" }
        let inner = indent + "  "
        let items = nodes.map { inner + serialize(node: $0, indent: inner) }
        return "[\n" + items.joined(separator: ",\n") + "\n" + indent + "]"
    }

    /// 序列化单个节点。叶子返回单行对象;文件夹返回多行(type/name 各一行、children 递归展开)。
    private static func serialize(node: TCodeNode, indent: String) -> String {
        switch node {
        case .code(let d, let v, let note):
            return leafLine(type: "code", display: d, value: v, note: note)
        case .text(let d, let v, let note):
            return leafLine(type: "text", display: d, value: v, note: note)
        case .folder(let name, let children):
            let inner = indent + "  "
            let kids = serialize(children, indent: inner)
            return "{\n"
                + inner + "\"type\": \"folder\",\n"
                + inner + "\"name\": \(quote(name)),\n"
                + inner + "\"children\": \(kids)\n"
                + indent + "}"
        }
    }

    /// 叶子对象的单行形式:{ "type": .., "display": .., "value": .., "note": .. }
    private static func leafLine(type: String, display: String, value: String, note: String) -> String {
        "{ \"type\": \"\(type)\", \"display\": \(quote(display)), \"value\": \(quote(value)), \"note\": \(quote(note)) }"
    }

    /// 把字符串编成合法的 JSON 字符串字面量(含首尾引号)。借用 JSONEncoder 处理转义,
    /// 不转义斜杠,保留中文原样,保证输出可被 JSONDecoder 读回。
    private static func quote(_ s: String) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? enc.encode([s]), let str = String(data: data, encoding: .utf8) {
            // encode 单个字符串在部分平台需 fragmentsAllowed;改为编码单元素数组再剥掉首尾 [ ]
            let trimmed = str.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return trimmed
        }
        return "\"\""
    }
}
