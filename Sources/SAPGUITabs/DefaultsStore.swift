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
    struct Rule: Codable, Equatable {
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
        let field = fld(field)
        guard !sys.isEmpty, !code.isEmpty, !field.isEmpty else { return false }

        var current = rules.filter { !($0.system == sys && $0.tcode == code && $0.field == field) }
        current.append(Rule(system: sys, tcode: code, field: field, value: value))
        return persist(current)
    }

    /// 删除一条规则(按 system/tcode/field 精确匹配;system/tcode 不区分大小写,field 大小写敏感)。
    /// 返回 true 表示确有删除并写盘成功。
    @discardableResult
    func removeRule(system: String, tcode: String, field: String) -> Bool {
        let sys = system.uppercased()
        let code = tcode.uppercased()
        let next = rules.filter { !($0.system == sys && $0.tcode == code && $0.field == fld(field)) }
        guard next.count != rules.count else { return false }
        return persist(next)
    }

    /// 编辑一条规则:把 old(system/tcode/field)这条改成 new 四字段。
    /// 若 new 的 (system,tcode,field) 撞上另一条已有规则(非 old 自身)则返回 false 不改动。
    @discardableResult
    func updateRule(oldSystem: String, oldTcode: String, oldField: String,
                    system: String, tcode: String, field: String, value: String) -> Bool {
        let oSys = oldSystem.uppercased(), oCode = oldTcode.uppercased(), oFld = fld(oldField)
        let nSys = system.uppercased(), nCode = tcode.uppercased(), nFld = fld(field)
        guard !nSys.isEmpty, !nCode.isEmpty, !nFld.isEmpty else { return false }

        // 键变了且与另一条已有规则冲突 → 拒绝
        let keyChanged = !(oSys == nSys && oCode == nCode && oFld == nFld)
        if keyChanged, rules.contains(where: { $0.system == nSys && $0.tcode == nCode && $0.field == nFld }) {
            return false
        }
        var next = rules.filter { !($0.system == oSys && $0.tcode == oCode && $0.field == oFld) }
        next.append(Rule(system: nSys, tcode: nCode, field: nFld, value: value))
        return persist(next)
    }

    // MARK: - 内部

    private func fld(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

    /// 把一组规则写回磁盘,成功则更新内存 rules。写盘用 prettyPrinted,与示例/手写格式一致。
    private func persist(_ next: [Rule]) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(ConfigFile(rules: next)) else { return false }
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return false }
        rules = next
        return true
    }

    // MARK: - 加载

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
