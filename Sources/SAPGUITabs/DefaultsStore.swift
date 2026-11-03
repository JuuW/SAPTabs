import Foundation

/// 字段默认值配置:从 ~/.sapguitabs_defaults.json 读取。
///
/// JSON 结构(与收藏配置 ~/.sapguitabs_tcodes.json 一样用 Codable,保持两份配置格式一致):
/// ```json
/// {
///   "rules": [
///     { "system": "SWA", "tcode": "S000", "field": "User",     "value": "JIANWA1" },
///     { "system": "SWA", "tcode": "S000", "field": "Password", "value": "******"  }
///   ]
/// }
/// ```
///   - system:窗口标题前三字符(如 SWA、DWC),大小写不敏感(存/比都 uppercased)
///   - tcode:事务码(如 SE16、S000),大小写不敏感;登录屏/主屏统一按 S000 配
///   - field:字段的标签文本,对应 AX 的 AXDescription(如 "Table Name"、"User"),大小写敏感(SAP 标签就那样显示)
///   - value:要填入的内容
///
/// 这些默认值在某窗口首次进入对应 tcode 时,由 SAPWindowManager 自动填入(仅当字段为空)。
final class DefaultsStore {
    /// 一条默认值规则(JSON 里 rules 数组的元素)
    struct Rule: Codable {
        let system: String   // 读入后 uppercased
        let tcode: String    // 读入后 uppercased
        let field: String    // 原样(大小写敏感)
        let value: String
    }

    private struct ConfigFile: Codable {
        var rules: [Rule]
    }

    private(set) var rules: [Rule] = []

    private let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sapguitabs_defaults.json")
    }()

    init() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            installDemoIfPresent()
        }
        load()
    }

    /// 查某 (系统ID, tcode) 下所有要填的 (字段ID, 默认值)。系统ID/tcode 不区分大小写。
    func lookup(system: String, tcode: String) -> [(field: String, value: String)] {
        let sys = system.uppercased()
        let code = tcode.uppercased()
        return rules
            .filter { $0.system == sys && $0.tcode == code }
            .map { (field: $0.field, value: $0.value) }
    }

    /// 重新从磁盘加载(供手动刷新用)
    func reload() { load() }

    /// 新增/更新一条规则并写回磁盘。
    /// 同 (system, tcode, field) 已存在时覆盖其 value(system/tcode 不区分大小写,field 大小写敏感)。
    /// 返回 true 表示写盘成功。
    @discardableResult
    func addRule(system: String, tcode: String, field: String, value: String) -> Bool {
        let sys = system.uppercased()
        let code = tcode.uppercased()
        let fld = field.trimmingCharacters(in: .whitespaces)
        guard !sys.isEmpty, !code.isEmpty, !fld.isEmpty else { return false }

        var current = rules.filter { !($0.system == sys && $0.tcode == code && $0.field == fld) }
        current.append(Rule(system: sys, tcode: code, field: fld, value: value))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(ConfigFile(rules: current)) else { return false }
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return false }
        rules = current
        return true
    }

    // MARK: - 内部

    private func load() {
        rules = []
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(ConfigFile.self, from: data) else { return }
        rules = config.rules
            .filter { !$0.system.isEmpty && !$0.tcode.isEmpty && !$0.field.isEmpty }
            .map { Rule(system: $0.system.uppercased(), tcode: $0.tcode.uppercased(), field: $0.field, value: $0.value) }
    }

    /// 首次运行(用户目录无此配置)时,从 app bundle 里的示例文件
    /// Resources/sapguitabs_defaults.demo.json 拷一份到用户目录,方便照着改。
    /// 找不到示例文件时静默跳过(load 会得到空规则,不报错)。
    private func installDemoIfPresent() {
        guard let demoURL = Bundle.main.url(forResource: "sapguitabs_defaults.demo", withExtension: "json") else { return }
        try? FileManager.default.copyItem(at: demoURL, to: fileURL)
    }
}
