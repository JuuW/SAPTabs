import Foundation

/// 事务码显示别名配置:从 ~/.sapguitabs_aliases.json 读取。
///
/// 有些事务码太长(如 "/SCWM/MON"),在页签上占空间。这份配置把长事务码
/// 映射成一个短显示名,**只影响页签上显示的文字**,不改变窗口身份/焦点匹配,
/// 也不影响收藏、默认值等按真实 tcode 工作的逻辑。
///
/// JSON 结构(与其它两份配置一样用 Codable,保持三份格式一致):
/// ```json
/// {
///   "aliases": [
///     { "tcode": "/SCWM/MON", "alias": "MON" },
///     { "tcode": "/SCWM/RFUI", "alias": "RF"  }
///   ]
/// }
/// ```
///   - tcode:真实事务码(与页签读到的一致),大小写不敏感(存/比都 uppercased)
///   - alias:要在页签上替代显示的短文字(原样保留,区分大小写)
final class AliasStore: ObservableObject {
    /// 一条别名规则(JSON 里 aliases 数组的元素)。供管理窗口读写。
    struct Rule: Codable, Equatable {
        var tcode: String   // 存盘时 uppercased
        var alias: String   // 原样
    }

    private struct ConfigFile: Codable {
        var aliases: [Rule]
    }

    /// tcode(uppercased)→ 别名 的查找表(页签显示用)
    @Published private(set) var map: [String: String] = [:]

    /// 全部规则,按 tcode 字母序。管理窗口直接用这份做增删改。
    @Published private(set) var rules: [Rule] = []

    private let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sapguitabs_aliases.json")
    }()

    init() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            installDemoIfPresent()
        }
        load()
    }

    /// 查某 tcode 的显示别名;无别名返回 nil。tcode 不区分大小写。
    func alias(for tcode: String) -> String? {
        let a = map[tcode.uppercased()]
        return (a?.isEmpty == false) ? a : nil
    }

    /// 重新从磁盘加载(供管理窗口打开时取最新磁盘状态用)
    func reload() { load() }

    // MARK: - 编辑接口(管理窗口用;改完即排序、落盘、刷新 @Published)

    /// 新增或更新一条别名:按 tcode(不区分大小写)判重,已存在则改其 alias,否则追加。
    /// tcode/alias 去首尾空白;tcode 存为大写。任一为空则不操作返回 false。
    @discardableResult
    func upsert(tcode rawTcode: String, alias rawAlias: String) -> Bool {
        let tcode = rawTcode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let alias = rawAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tcode.isEmpty, !alias.isEmpty else { return false }
        var next = rules
        if let i = next.firstIndex(where: { $0.tcode.caseInsensitiveCompare(tcode) == .orderedSame }) {
            next[i].tcode = tcode
            next[i].alias = alias
        } else {
            next.append(Rule(tcode: tcode, alias: alias))
        }
        commit(next)
        return true
    }

    /// 删除某 tcode(不区分大小写)对应的别名
    @discardableResult
    func remove(tcode: String) -> Bool {
        let key = tcode.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = rules
        let before = next.count
        next.removeAll { $0.tcode.caseInsensitiveCompare(key) == .orderedSame }
        guard next.count != before else { return false }
        commit(next)
        return true
    }

    // MARK: - 内部

    /// 排序、更新内存查找表与规则列表、落盘
    private func commit(_ newRules: [Rule]) {
        var sorted = newRules
        sorted.sort { $0.tcode.localizedCaseInsensitiveCompare($1.tcode) == .orderedAscending }
        rules = sorted
        rebuildMap()
        save()
    }

    private func rebuildMap() {
        var result: [String: String] = [:]
        for r in rules where !r.tcode.isEmpty && !r.alias.isEmpty {
            result[r.tcode.uppercased()] = r.alias
        }
        map = result
    }

    private func load() {
        var loaded: [Rule] = []
        if let data = try? Data(contentsOf: fileURL),
           let config = try? JSONDecoder().decode(ConfigFile.self, from: data) {
            for r in config.aliases where !r.tcode.isEmpty && !r.alias.isEmpty {
                loaded.append(Rule(tcode: r.tcode.uppercased(), alias: r.alias))
            }
        }
        loaded.sort { $0.tcode.localizedCaseInsensitiveCompare($1.tcode) == .orderedAscending }
        rules = loaded
        rebuildMap()
    }

    /// 落盘。手写单行 JSON,与 TCodeStore 风格一致:aliases 数组每条一行。
    private func save() {
        let json: String
        if rules.isEmpty {
            json = "{\n  \"aliases\": []\n}"
        } else {
            let lines = rules.map { "    { \"tcode\": \(Self.quote($0.tcode)), \"alias\": \(Self.quote($0.alias)) }" }
            json = "{\n  \"aliases\": [\n" + lines.joined(separator: ",\n") + "\n  ]\n}"
        }
        guard let data = json.data(using: .utf8) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 把字符串编成合法 JSON 字符串字面量(含首尾引号),不转义斜杠、保留中文。
    private static func quote(_ s: String) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? enc.encode([s]), let str = String(data: data, encoding: .utf8) {
            return str.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        return "\"\""
    }

    /// 首次运行(用户目录无此配置)时,从 app bundle 里的示例文件
    /// Resources/sapguitabs_aliases.demo.json 拷一份到用户目录,方便照着改。
    /// 找不到示例文件时静默跳过(load 会得到空表,不报错)。
    private func installDemoIfPresent() {
        guard let demoURL = Bundle.main.url(forResource: "sapguitabs_aliases.demo", withExtension: "json") else { return }
        try? FileManager.default.copyItem(at: demoURL, to: fileURL)
    }
}
