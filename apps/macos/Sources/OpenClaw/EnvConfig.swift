import Foundation

// 企业服务端环境配置（测试 / 正式）。改 `isTestEnvironment` 一个常量即可切换全环境。
// 取代之前在 AccountSettings UI 里手填的地址 —— 地址不再暴露给终端用户。
// 发版正式版时：把 isTestEnvironment 改成 false，并填正式地址（标 TODO 的两处）。

enum EnvConfig {
    /// `true` = 测试环境，`false` = 正式环境。
    static let isTestEnvironment = true

    /// OA (corporate OAuth) base URL.
    static var oaBaseUrl: String {
        isTestEnvironment
            ? "http://172.20.200.61:8080/Report/PF"
            : "https://oa.yourcompany.com/Report/PF"   // TODO: 正式 OA 地址
    }

    /// Company Skills Hub base URL.
    static var companySkillsHubUrl: String {
        isTestEnvironment
            ? "http://192.168.100.203:3001"
            : "https://skills.yourcompany.com"         // TODO: 正式公司技能市场地址
    }
}
