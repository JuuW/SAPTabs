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
    /// 一条别名规则(JSON 里 aliases 数组的元素)
    private struct Rule: Codable {
        let tcode: String   // 读入后 uppercased
        let alias: String   // 原样
    }

    private struct ConfigFile: Codable {
        var aliases: [Rule]
    }

    /// tcode(uppercased)→ 别名 的查找表
    @Published private(set) var map: [String: String] = [:]

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

    /// 重新从磁盘加载(供菜单手动刷新用)
    func reload() { load() }

    // MARK: - 内部

    private func load() {
        var result: [String: String] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let config = try? JSONDecoder().decode(ConfigFile.self, from: data) {
            for r in config.aliases where !r.tcode.isEmpty && !r.alias.isEmpty {
                result[r.tcode.uppercased()] = r.alias
            }
        }
        map = result
    }

    /// 首次运行(用户目录无此配置)时,从 app bundle 里的示例文件
    /// Resources/sapguitabs_aliases.demo.json 拷一份到用户目录,方便照着改。
    /// 找不到示例文件时静默跳过(load 会得到空表,不报错)。
    private func installDemoIfPresent() {
        guard let demoURL = Bundle.main.url(forResource: "sapguitabs_aliases.demo", withExtension: "json") else { return }
        try? FileManager.default.copyItem(at: demoURL, to: fileURL)
    }
}
