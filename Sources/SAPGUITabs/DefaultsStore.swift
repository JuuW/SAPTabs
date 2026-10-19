import Foundation

/// 字段默认值配置:从 ~/.sapguitabs_defaults.conf 读取。
///
/// 每行一条:`系统ID,Tcode,字段ID = 默认值`
///   - 系统ID:窗口标题前三字符(如 SWA、DWC),大小写不敏感
///   - Tcode:事务码(如 SE16、S000),大小写不敏感;登录屏/主屏读不到码时用空串匹配不到,一般不配
///   - 字段ID:字段的标签文本,对应 AX 的 AXHelp(如 "Table Name"、"Logon Language"),大小写敏感(SAP 标签就那样显示)
///   - 默认值:要填入的内容
/// `#` 开头的行与空行忽略。不支持通配。
///
/// 这些默认值在某窗口首次进入对应 tcode 时,由 SAPWindowManager 自动填入(仅当字段为空)。
final class DefaultsStore {
    /// 一条默认值规则
    struct Rule {
        let system: String   // 已 uppercased
        let tcode: String    // 已 uppercased
        let field: String    // 原样(大小写敏感)
        let value: String
    }

    private(set) var rules: [Rule] = []

    private let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sapguitabs_defaults.conf")
    }()

    init() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            writeTemplate()
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

    // MARK: - 内部

    private func load() {
        rules = []
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // 拆成 "键 = 值";值里可能含 "="(如含等号的默认值),只按第一个 "=" 切
            guard let eq = line.firstIndex(of: "=") else { continue }
            let keyPart = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            // 键拆成 系统ID,Tcode,字段ID(字段ID里不含逗号;SAP 标签不含逗号)
            let keys = keyPart.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard keys.count == 3 else { continue }
            let system = keys[0], tcode = keys[1], field = keys[2]
            if system.isEmpty || tcode.isEmpty || field.isEmpty { continue }
            rules.append(Rule(system: system.uppercased(), tcode: tcode.uppercased(), field: field, value: value))
        }
    }

    /// 首次运行写一份带注释的示例模板,方便用户照着改
    private func writeTemplate() {
        let template = """
        # SAP GUI Tabs 字段默认值配置
        #
        # 每行一条规则,格式:
        #   系统ID,Tcode,字段ID = 默认值
        #
        #   系统ID  = 窗口标题前三个字符(如 SWA、DWC),不区分大小写
        #   Tcode   = 事务码(如 SE16、SE38),不区分大小写
        #   字段ID  = 字段左边的标签文字(如 Table Name、Program),区分大小写,照屏幕上显示的写
        #   默认值  = 要自动填入的内容
        #
        # 规则:某个会话窗口第一次进入对应 tcode 时,若该字段当前为空,就自动填入默认值。
        #       # 开头的行和空行会被忽略。不支持通配符。
        #
        # 示例(按需取消注释并改成你自己的):
        # SWA,SE16,Table Name = MARA
        # DWC,SE38,Program = ZHELLO_WORLD

        """
        try? template.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
