import Observation
import OpenClawKit
import SwiftUI

// MCP configuration page. Mirrors Windows McpMyServersControl + McpMarketplaceControl.
// My Servers: card grid over mcp.servers, add/edit/delete via sheet + alert.
// Marketplace: npmmirror search + curated catalog (9) + one-click install
//   (writes mcp.servers.<name> = {command:"npx", args:["-y", package]}), with instant
//   "installing…" feedback and authoritative re-read after install.

enum McpTab: Hashable {
    case myServers
    case market
}

struct McpServerRow: Identifiable, Hashable {
    let name: String
    let transport: String  // "stdio" | "streamable-http" | "sse"
    let display: String    // stdio: "command args", http: url
    let envHint: String    // "env: KEY1, KEY2" or ""

    var id: String { self.name }

    var transportBadge: String {
        switch self.transport {
        case "stdio": return "stdio"
        case "streamable-http": return "http"
        case "sse": return "sse"
        default: return self.transport
        }
    }
}

struct McpSearchResult: Identifiable, Hashable {
    let name: String
    let description: String
    let version: String
    var isInstalled: Bool
    var id: String { self.name }
}

struct McpServerEditTarget: Identifiable {
    let name: String
    let server: [String: Any]
    var id: String { self.name }
}

struct McpSettings: View {
    @Bindable var state: AppState
    @State private var model = McpSettingsModel()
    @State private var showAddServer = false
    @State private var editingServer: McpServerEditTarget?
    @State private var confirmDeleteName: String?
    @State private var didScheduleInitialRefresh = false

    init(state: AppState = AppStateStore.shared) {
        self.state = state
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsPageHeader(
                    title: "MCP",
                    subtitle: "管理 MCP 服务器（mcp.servers）。stdio / http，一键安装市场服务器。")

                Picker("", selection: self.$model.selectedTab) {
                    Text("我的服务器").tag(McpTab.myServers)
                    Text("市场").tag(McpTab.market)
                }
                .pickerStyle(.segmented)

                self.statusBanner

                if self.model.selectedTab == .myServers {
                    self.myServersSection
                } else {
                    self.marketSection
                }
                Spacer(minLength: 8)
            }
            .settingsDetailContent()
        }
        .task {
            guard !self.didScheduleInitialRefresh else { return }
            self.didScheduleInitialRefresh = true
            await self.model.refreshIfNeeded()
        }
        .sheet(isPresented: self.$showAddServer) {
            self.serverSheet(editing: false, name: nil, server: nil)
        }
        .sheet(item: self.$editingServer) { target in
            self.serverSheet(editing: true, name: target.name, server: target.server)
        }
        .alert("删除 MCP 服务器？", isPresented: Binding(
            get: { self.confirmDeleteName != nil },
            set: { if !$0 { self.confirmDeleteName = nil } }))
        {
            Button("取消", role: .cancel) { self.confirmDeleteName = nil }
            Button("删除", role: .destructive) {
                if let name = self.confirmDeleteName {
                    Task { await self.onDelete(name: name) }
                }
                self.confirmDeleteName = nil
            }
        } message: {
            if let name = self.confirmDeleteName { Text(name) }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let error = self.model.error {
            Text(error).font(.footnote).foregroundStyle(.orange)
        } else if let message = self.model.statusMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - My servers

    private var myServersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if self.model.isLoading { ProgressView().controlSize(.small) }
                Button {
                    self.showAddServer = true
                } label: {
                    Label("添加服务器", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await self.model.refresh(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            if self.model.servers.isEmpty && !self.model.isLoading {
                Text("还没有 MCP 服务器。点「添加服务器」或去「市场」一键安装。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(self.model.servers) { row in
                        self.serverCard(row)
                    }
                }
            }
        }
    }

    private func serverCard(_ row: McpServerRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(row.name).font(.callout.weight(.semibold))
                Text(row.transportBadge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                Spacer()
            }
            Text(row.display).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            if !row.envHint.isEmpty {
                Text(row.envHint).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Button("编辑") {
                    if let target = self.model.editTarget(for: row.name) {
                        self.editingServer = target
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button(role: .destructive) {
                    self.confirmDeleteName = row.name
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.055))
        }
    }

    // MARK: - Market

    private var marketSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("搜索 MCP（默认 mcp server）", text: self.$model.marketTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await self.model.searchMarket() } }
                Button {
                    Task { await self.model.searchMarket() }
                } label: {
                    if self.model.isLoading { ProgressView().controlSize(.small) }
                    else { Label("搜索", systemImage: "magnifyingglass") }
                }
                .buttonStyle(.bordered)
            }

            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

            // 搜索框有内容时只显示搜索结果；为空时显示精选目录（不再两者叠在下方）。
            if self.model.marketTerm.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("精选目录").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(McpCatalog.entries) { entry in
                        self.catalogCard(entry)
                    }
                }
            } else {
                Text("搜索结果").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if self.model.marketResults.isEmpty {
                    if self.model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("无结果").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(self.model.marketResults) { result in
                            self.searchResultCard(result)
                        }
                    }
                }
            }
        }
    }

    private func catalogCard(_ entry: McpCatalogEntry) -> some View {
        let installed = self.model.installedNames.contains(entry.name)
        let installing = self.model.installingName == entry.name
        return VStack(alignment: .leading, spacing: 6) {
            Text(entry.name).font(.callout.weight(.semibold))
            Text(entry.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Spacer()
                if installing {
                    Text("正在安装…").font(.caption).foregroundStyle(.secondary)
                } else if installed {
                    Text("已安装").font(.caption).foregroundStyle(.green)
                } else {
                    Button("一键安装") {
                        Task { await self.model.install(name: entry.name, package: entry.package, authEnvKey: entry.authEnvKey) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.055))
        }
    }

    private func searchResultCard(_ result: McpSearchResult) -> some View {
        let installing = self.model.installingName == result.name
        return VStack(alignment: .leading, spacing: 6) {
            Text(result.name).font(.callout.weight(.semibold)).lineLimit(1)
            if !result.description.isEmpty {
                Text(result.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Text(result.version).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if installing {
                    Text("正在安装…").font(.caption).foregroundStyle(.secondary)
                } else if result.isInstalled {
                    Text("已安装").font(.caption).foregroundStyle(.green)
                } else {
                    Button("安装") {
                        Task { await self.model.install(name: result.name, package: result.name, authEnvKey: nil) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.055))
        }
    }

    // MARK: - Sheet + actions

    private func serverSheet(editing: Bool, name: String?, server: [String: Any]?) -> some View {
        McpServerSheet(
            editing: editing,
            isSaving: self.$model.isSaving,
            error: self.$model.editorError,
            initialName: name,
            initialServer: server,
            onCancel: {
                self.showAddServer = false
                self.editingServer = nil
            },
            onSave: { serverName, serverDict in
                Task { await self.saveServer(editing: editing, name: serverName, server: serverDict) }
            })
            .frame(minWidth: 520, minHeight: 460)
    }

    @MainActor
    private func onDelete(name: String) async {
        self.model.error = nil
        do {
            try await self.model.deleteServer(name: name)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.model.refresh(force: true)
            self.model.statusMessage = "已删除 \(name)"
        } catch {
            self.model.error = EnterpriseConfigPatch.friendlyConfigError(error.localizedDescription)
        }
    }

    @MainActor
    private func saveServer(editing: Bool, name: String, server: [String: Any]) async {
        self.model.isSaving = true
        self.model.editorError = nil
        do {
            try await self.model.writeServer(name: name, server: server)
            self.showAddServer = false
            self.editingServer = nil
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.model.refresh(force: true)
            self.model.statusMessage = editing ? "已保存 \(name)" : "已添加 \(name)"
        } catch {
            self.model.editorError = EnterpriseConfigPatch.friendlyConfigError(error.localizedDescription)
        }
        self.model.isSaving = false
    }
}

@MainActor
@Observable
final class McpSettingsModel {
    var servers: [McpServerRow] = []
    var installedNames: Set<String> = []
    var installingName: String?
    var marketResults: [McpSearchResult] = []
    var marketTerm: String = ""
    var selectedTab: McpTab = .myServers
    var isLoading = false
    var isSaving = false
    var error: String?
    var statusMessage: String?
    var editorError: String?

    /// name → raw server dict, for the edit sheet.
    private(set) var serversRaw: [String: [String: Any]] = [:]
    private var hasLoaded = false

    func refreshIfNeeded() async {
        guard !self.hasLoaded else { return }
        await self.refresh()
    }

    func refresh(force: Bool = false) async {
        guard !self.isLoading else { return }
        if self.hasLoaded, !force { return }
        self.isLoading = true
        self.error = nil
        await self.refreshMyServers()
        self.isLoading = false
    }

    func refreshMyServers() async {
        guard let root = await EnterpriseConfigPatch.readConfig() else {
            self.error = "无法读取网关配置。请确认网关已连接。"
            return
        }
        let node = EnterpriseConfigPatch.walk(root, dotPath: EnterpriseConfigPaths.mcpServers)
        var rows: [McpServerRow] = []
        var raw: [String: [String: Any]] = [:]
        var names: Set<String> = []
        if let dict = node as? [String: Any] {
            for (name, value) in dict {
                guard let server = value as? [String: Any] else { continue }
                names.insert(name)
                raw[name] = server
                let transport = Self.detectTransport(server)
                rows.append(McpServerRow(
                    name: name,
                    transport: transport,
                    display: Self.buildDisplay(server, transport: transport),
                    envHint: Self.buildEnvHint(server)))
            }
        }
        self.servers = rows.sorted { $0.name < $1.name }
        self.serversRaw = raw
        self.installedNames = names
        // Reflect authoritative install state into cached search results.
        for index in self.marketResults.indices {
            self.marketResults[index].isInstalled = names.contains(self.marketResults[index].name)
        }
        self.hasLoaded = true
    }

    func editTarget(for name: String) -> McpServerEditTarget? {
        guard let server = self.serversRaw[name] else { return nil }
        return McpServerEditTarget(name: name, server: server)
    }

    // MARK: - Writes

    /// mcp.servers.<name> = server (direct file write). server == nil → delete key.
    func writeServer(name: String, server: [String: Any]?) async throws {
        let patch = EnterpriseConfigPatch.buildNestedPatch(
            parentPath: EnterpriseConfigPaths.mcpServers,
            finalKey: name,
            value: server)
        try await EnterpriseConfigPatch.writePatch(patch)
    }

    func deleteServer(name: String) async throws {
        try await self.writeServer(name: name, server: nil)
    }

    /// One-click install: stdio npx server + instant feedback + authoritative re-read.
    func install(name: String, package: String, authEnvKey: String?) async {
        guard self.installingName == nil else { return }
        self.installingName = name
        self.error = nil
        self.statusMessage = "正在安装 \(name)…"
        do {
            let server: [String: Any] = ["command": "npx", "args": ["-y", package]]
            try await self.writeServer(name: name, server: server)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.refreshMyServers()
            self.installingName = nil
            self.statusMessage = authEnvKey == nil
                ? "已安装 \(name)。"
                : "已安装 \(name)。注意：此 MCP 需要配置环境变量 \(authEnvKey!)（在「我的服务器」里编辑该服务器的 env）。"
        } catch {
            self.installingName = nil
            self.error = EnterpriseConfigPatch.friendlyConfigError(error.localizedDescription)
        }
    }

    // MARK: - Market search (npmmirror)

    func searchMarket() async {
        let term = self.marketTerm.trimmingCharacters(in: .whitespaces)
        let effective = term.isEmpty ? "mcp server" : term
        self.isLoading = true
        self.error = nil
        defer { self.isLoading = false }

        let encoded = effective.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? effective
        guard let url = URL(string: "https://registry.npmmirror.com/-/v1/search?text=\(encoded)&size=40") else {
            self.error = "搜索 URL 无效。"
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            self.marketResults = Self.parseSearch(data, installed: self.installedNames)
            self.statusMessage = self.marketResults.isEmpty ? "无结果" : "找到 \(self.marketResults.count) 个结果"
        } catch {
            self.error = "搜索失败：\(error.localizedDescription)"
        }
    }

    private static func parseSearch(_ data: Data, installed: Set<String>) -> [McpSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objects = json["objects"] as? [[String: Any]]
        else { return [] }
        var results: [McpSearchResult] = []
        for object in objects {
            guard let pkg = object["package"] as? [String: Any] else { continue }
            let name = pkg["name"] as? String ?? ""
            let desc = pkg["description"] as? String ?? ""
            let version = pkg["version"] as? String ?? ""
            let nameLower = name.lowercased()
            let descLower = desc.lowercased()
            guard nameLower.contains("mcp")
                || nameLower.contains("@modelcontextprotocol")
                || descLower.contains("mcp")
            else { continue }
            results.append(McpSearchResult(
                name: name,
                description: desc,
                version: version,
                isInstalled: installed.contains(name)))
        }
        return results
    }

    // MARK: - Parsing helpers

    private static func detectTransport(_ server: [String: Any]) -> String {
        let t = server["transport"] as? String ?? ""
        if t.isEmpty || t == "stdio" || server["command"] != nil { return "stdio" }
        return t
    }

    private static func buildDisplay(_ server: [String: Any], transport: String) -> String {
        if transport == "stdio" {
            let cmd = server["command"] as? String ?? ""
            let argsText: String
            if let arr = server["args"] as? [String] {
                argsText = arr.joined(separator: " ")
            } else if let arr = server["args"] as? [Any] {
                argsText = arr.map { String(describing: $0) }.joined(separator: " ")
            } else {
                argsText = ""
            }
            return argsText.isEmpty ? cmd : "\(cmd) \(argsText)"
        }
        return server["url"] as? String ?? ""
    }

    /// Only env key NAMES are shown — values are never surfaced (avoid leaking secrets).
    private static func buildEnvHint(_ server: [String: Any]) -> String {
        guard let env = server["env"] as? [String: Any], !env.isEmpty else { return "" }
        return "env: " + env.keys.sorted().joined(separator: ", ")
    }
}

#if DEBUG
struct McpSettings_Previews: PreviewProvider {
    static var previews: some View {
        McpSettings(state: .preview)
            .frame(width: SettingsTab.windowWidth, height: SettingsTab.windowHeight)
    }
}
#endif
