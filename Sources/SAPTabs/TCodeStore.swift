import Foundation

/// 收藏树的节点:要么是一个事务码(叶子),要么是一个文件夹(含子节点)。
enum TCodeNode: Codable, Equatable {
    case code(String)
    case folder(name: String, children: [TCodeNode])

    /// 排序用的显示名(folder 用名字,code 用码本身)
    var sortName: String {
        switch self {
        case .code(let c): return c
        case .folder(let n, _): return n
        }
    }
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    // 自定义编解码:{"type":"code","value":"SE24"} 或
    // {"type":"folder","name":"Dev","children":[...]}
    private enum CodingKeys: String, CodingKey { case type, value, name, children }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "folder":
            let name = try c.decode(String.self, forKey: .name)
            let children = try c.decodeIfPresent([TCodeNode].self, forKey: .children) ?? []
            self = .folder(name: name, children: children)
        default:
            self = .code(try c.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .code(let v):
            try c.encode("code", forKey: .type)
            try c.encode(v, forKey: .value)
        case .folder(let name, let children):
            try c.encode("folder", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(children, forKey: .children)
        }
    }
}

/// 收藏的事务码树,持久化到 ~/.saptabs_tcodes.json。
/// 每一级:文件夹优先、再按名称字母序(不区分大小写)。供页签栏左侧多级下拉菜单使用。
///
/// 兼容旧格式:早期是扁平的 ["SE24","SPRO"] 字符串数组,load 时若识别到旧格式则升级为叶子节点。
final class TCodeStore: ObservableObject {
    @Published private(set) var root: [TCodeNode] = []

    private let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".saptabs_tcodes.json")
    }()

    init() { load() }

    /// 在指定文件夹路径下添加事务码。路径为空表示根级。
    /// 该级已存在同名 code(不区分大小写)返回 false;否则加入、排序、落盘返回 true。
    @discardableResult
    func addCode(_ raw: String, at path: [String]) -> Bool {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return false }
        return mutate(at: path) { children in
            if children.contains(where: {
                if case .code(let c) = $0 { return c.caseInsensitiveCompare(code) == .orderedSame }
                return false
            }) { return false }
            children.append(.code(code))
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

    /// 文件夹优先,再按名称字母序(不区分大小写)
    private static func sort(_ nodes: inout [TCodeNode]) {
        nodes.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
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
            var t = flat.map { TCodeNode.code($0) }
            sortTree(&t)
            root = t
            save() // 顺手写回新格式
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(root) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
