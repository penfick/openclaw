import Foundation

// Curated MCP server catalog. Mirrors Windows McpCatalog.cs (9 entries).
// One-click install writes mcp.servers.<name> = {command:"npx", args:["-y", package]}
// (stdio, no transport field).

struct McpCatalogEntry: Identifiable, Hashable {
    let name: String
    let description: String
    let package: String
    let category: String
    /// Env var the server needs to function (e.g. GITHUB_PERSONAL_ACCESS_TOKEN); nil if none.
    let authEnvKey: String?

    var id: String { self.name }
}

enum McpCatalog {
    static let entries: [McpCatalogEntry] = [
        McpCatalogEntry(name: "Filesystem", description: "文件系统读写访问", package: "@modelcontextprotocol/server-filesystem", category: "开发", authEnvKey: nil),
        McpCatalogEntry(name: "GitHub", description: "GitHub 仓库 / Issue / PR 操作", package: "@modelcontextprotocol/server-github", category: "开发", authEnvKey: "GITHUB_PERSONAL_ACCESS_TOKEN"),
        McpCatalogEntry(name: "SQLite", description: "SQLite 数据库查询", package: "@modelcontextprotocol/server-sqlite", category: "开发", authEnvKey: nil),
        McpCatalogEntry(name: "Puppeteer", description: "浏览器自动化与网页抓取", package: "@modelcontextprotocol/server-puppeteer", category: "浏览器", authEnvKey: nil),
        McpCatalogEntry(name: "Fetch", description: "网页内容抓取", package: "@modelcontextprotocol/server-fetch", category: "网络", authEnvKey: nil),
        McpCatalogEntry(name: "Brave Search", description: "Brave 搜索引擎", package: "@modelcontextprotocol/server-brave-search", category: "网络", authEnvKey: "BRAVE_API_KEY"),
        McpCatalogEntry(name: "Google Maps", description: "Google 地图与定位", package: "@modelcontextprotocol/server-google-maps", category: "网络", authEnvKey: "GOOGLE_MAPS_API_KEY"),
        McpCatalogEntry(name: "Memory", description: "知识图谱记忆库", package: "@modelcontextprotocol/server-memory", category: "知识", authEnvKey: nil),
        McpCatalogEntry(name: "Sequential Thinking", description: "分步推理思考", package: "@modelcontextprotocol/server-sequential-thinking", category: "知识", authEnvKey: nil),
    ]
}
