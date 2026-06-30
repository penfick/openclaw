import Observation
import OpenClawKit
import SwiftUI

// Models management page. Mirrors Windows ModelsPage.xaml.cs:
//  - allowlist (agents.defaults.models) → model cards
//  - default model = agents.defaults.model.primary (string) or agents.defaults.model (string, legacy)
//  - provider config under models.providers.<id>
// All writes go through direct file read/write of ~/.openclaw/openclaw.json (RFC 7396 merge patch).

/// One allowlist entry "provider/modelId" shown as a card.
struct ModelCard: Identifiable, Hashable {
    let key: String          // "openai/gpt-4o"
    let providerId: String   // "openai"
    let modelId: String      // "gpt-4o"
    let providerName: String // catalog name, or providerId if unknown
    let icon: String
    var isDefault: Bool

    var id: String { self.key }
}

/// Payload handed back from AddProviderSheet → model.applyProvider.
struct ProviderPayload {
    let isNew: Bool
    let id: String
    let api: String
    let baseUrl: String
    let apiKey: String
    let modelId: String
}

/// Carries existing provider info when editing (id locked).
struct ProviderEditTarget: Identifiable {
    let id: String
    let api: String
    let baseUrl: String
}

struct ModelsSettings: View {
    @Bindable var state: AppState
    @State private var model = ModelsSettingsModel()
    @State private var showAddProvider = false
    @State private var editingProvider: ProviderEditTarget?
    @State private var confirmDeleteKey: String?
    @State private var didScheduleInitialRefresh = false

    init(state: AppState = AppStateStore.shared) {
        self.state = state
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "Models",
                    subtitle: "管理模型 Provider、默认模型与允许清单。改动写入网关配置（models.providers / agents.defaults）。")

                self.defaultModelCard
                self.toolbarCard
                self.statusBanner
                self.modelsGrid
                Spacer(minLength: 8)
            }
            .settingsDetailContent()
        }
        .task {
            guard !self.didScheduleInitialRefresh else { return }
            self.didScheduleInitialRefresh = true
            await self.model.refreshIfNeeded()
        }
        .sheet(isPresented: self.$showAddProvider) {
            AddProviderSheet(
                editing: nil,
                isSaving: self.$model.isSaving,
                error: self.$model.editorError,
                onCancel: { self.showAddProvider = false },
                onSave: { payload in Task { await self.onSaveProvider(payload) } })
                .frame(minWidth: 560, minHeight: 520)
        }
        .sheet(item: self.$editingProvider) { target in
            AddProviderSheet(
                editing: target,
                isSaving: self.$model.isSaving,
                error: self.$model.editorError,
                onCancel: { self.editingProvider = nil },
                onSave: { payload in Task { await self.onSaveProvider(payload) } })
                .frame(minWidth: 560, minHeight: 520)
        }
        .alert("删除模型？", isPresented: Binding(
            get: { self.confirmDeleteKey != nil },
            set: { if !$0 { self.confirmDeleteKey = nil } }))
        {
            Button("取消", role: .cancel) { self.confirmDeleteKey = nil }
            Button("删除", role: .destructive) {
                if let key = self.confirmDeleteKey {
                    Task { await self.onDelete(key: key) }
                }
                self.confirmDeleteKey = nil
            }
        } message: {
            if let key = self.confirmDeleteKey { Text(key) }
        }
    }

    // MARK: - Default model (cascading provider → model)

    @ViewBuilder
    private var defaultModelCard: some View {
        let providerOptions = self.model.distinctProviderIds
        let modelOptions = self.model.models(forProvider: self.model.defaultProviderId)
        SettingsCardGroup("默认模型") {
            SettingsCardRow(title: "Provider", subtitle: "选择已配置的 Provider。", showsDivider: true) {
                Picker("Provider", selection: Binding(
                    get: { self.model.defaultProviderId },
                    set: { newId in Task { await self.onPickProvider(newId) } }))
                {
                    ForEach(providerOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            SettingsCardRow(title: "Model", subtitle: "该 Provider 下的模型。", showsDivider: false) {
                Picker("Model", selection: Binding(
                    get: { self.model.defaultModelKey },
                    set: { newKey in Task { await self.onPickModel(newKey) } }))
                {
                    ForEach(modelOptions) { Text($0.modelId).tag($0.key) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarCard: some View {
        SettingsCardGroup("Provider") {
            SettingsCardRow(
                title: "添加 / 管理 Provider",
                subtitle: "新增 Provider 并设为默认，或在卡片上编辑 API Key、删除。",
                showsDivider: false)
            {
                if self.model.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    self.showAddProvider = true
                } label: {
                    Label("添加 Provider", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await self.model.refresh(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
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

    // MARK: - Cards grid

    private var modelsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return Group {
            if self.model.cards.isEmpty && !self.model.isLoading {
                Text("还没有模型。点「添加 Provider」开始。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(self.model.cards) { card in
                        self.modelCardView(card)
                    }
                }
            }
        }
    }

    private func modelCardView(_ card: ModelCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(card.icon).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.providerName).font(.callout.weight(.semibold))
                        if card.isDefault {
                            Text("默认")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(card.modelId).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                if !card.isDefault {
                    Button("设为默认") { Task { await self.onPickModel(card.key) } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Button("编辑 Key") {
                    self.editingProvider = self.model.editTarget(for: card.providerId)
                }
                .buttonStyle(.bordered).controlSize(.small)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    self.confirmDeleteKey = card.key
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless).help("删除")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.055))
        }
    }

    // MARK: - Actions (MainActor — touch @State + @Observable model)

    @MainActor
    private func onPickProvider(_ providerId: String) async {
        self.model.defaultProviderId = providerId
        if let first = self.model.models(forProvider: providerId).first {
            await self.changeDefault(key: first.key)
        }
    }

    @MainActor
    private func onPickModel(_ key: String) async {
        await self.changeDefault(key: key)
    }

    @MainActor
    private func changeDefault(key: String) async {
        self.model.error = nil
        self.model.statusMessage = nil
        do {
            try await self.model.setDefault(key: key)
            self.model.defaultModelKey = key
            self.model.defaultProviderId = key.split(separator: "/").first.map(String.init) ?? ""
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.model.refresh(force: true)
            self.model.statusMessage = "已设为默认：\(key)"
        } catch {
            self.model.error = EnterpriseConfigPatch.friendlyConfigError(error.localizedDescription)
        }
    }

    @MainActor
    private func onSaveProvider(_ payload: ProviderPayload) async {
        self.model.isSaving = true
        self.model.editorError = nil
        do {
            try await self.model.applyProvider(payload)
            self.showAddProvider = false
            self.editingProvider = nil
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.model.refresh(force: true)
            self.model.statusMessage = payload.isNew ? "已添加 Provider \(payload.id)" : "已更新 \(payload.id) 的 API Key"
        } catch {
            self.model.editorError = EnterpriseConfigPatch.friendlyConfigError(error.localizedDescription)
        }
        self.model.isSaving = false
    }

    @MainActor
    private func onDelete(key: String) async {
        self.model.error = nil
        do {
            try await self.model.removeAllowlist(key: key)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.model.refresh(force: true)
            self.model.statusMessage = "已删除 \(key)"
        } catch {
            self.model.error = EnterpriseConfigPatch.friendlyConfigError(error.localizedDescription)
        }
    }
}

@MainActor
@Observable
final class ModelsSettingsModel {
    var cards: [ModelCard] = []
    var primaryKey: String = ""
    var defaultProviderId: String = ""
    var defaultModelKey: String = ""
    var isLoading = false
    var error: String?
    var statusMessage: String?
    var isSaving = false
    var editorError: String?

    /// providerId → raw config dict (api/baseUrl/apiKey/models), for the edit sheet.
    private(set) var providersConfig: [String: [String: Any]] = [:]
    private var hasLoaded = false

    // MARK: - Load

    func refreshIfNeeded() async {
        guard !self.hasLoaded else { return }
        await self.refresh()
    }

    func refresh(force: Bool = false) async {
        guard !self.isLoading else { return }
        if self.hasLoaded, !force { return }
        self.isLoading = true
        self.error = nil
        if let root = await EnterpriseConfigPatch.readConfig() {
            self.primaryKey = Self.readPrimary(root)
            self.providersConfig = Self.readProviders(root)
            self.cards = Self.buildCards(root: root, primary: self.primaryKey)
                .sorted { Self.compareDefaultFirst($0, $1) }
            self.defaultModelKey = self.primaryKey
            self.defaultProviderId = self.primaryKey.split(separator: "/").first.map(String.init) ?? ""
            if self.defaultProviderId.isEmpty, let first = self.cards.first {
                self.defaultProviderId = first.providerId
            }
            self.hasLoaded = true
        } else {
            self.error = "无法读取网关配置。请确认网关已连接。"
        }
        self.isLoading = false
    }

    var distinctProviderIds: [String] {
        let ids = Set(self.cards.map { $0.providerId })
        return ids.sorted()
    }

    func models(forProvider providerId: String) -> [ModelCard] {
        self.cards.filter { $0.providerId == providerId }.sorted { $0.modelId < $1.modelId }
    }

    func editTarget(for providerId: String) -> ProviderEditTarget? {
        guard let cfg = self.providersConfig[providerId] else { return nil }
        return ProviderEditTarget(
            id: providerId,
            api: cfg["api"] as? String ?? "openai-completions",
            baseUrl: cfg["baseUrl"] as? String ?? "")
    }

    // MARK: - Config parsing

    /// agents.defaults.model may be a string (legacy) or { primary: "..." } (current).
    private static func readPrimary(_ root: [String: Any]) -> String {
        guard let agents = root["agents"] as? [String: Any],
              let defaults = agents["defaults"] as? [String: Any],
              let model = defaults["model"]
        else { return "" }
        if let s = model as? String { return s }
        if let dict = model as? [String: Any], let pri = dict["primary"] as? String { return pri }
        return ""
    }

    private static func readProviders(_ root: [String: Any]) -> [String: [String: Any]] {
        let node = EnterpriseConfigPatch.walk(root, dotPath: EnterpriseConfigPaths.providers)
        guard let dict = node as? [String: Any] else { return [:] }
        return dict.compactMapValues { $0 as? [String: Any] }
    }

    /// Build cards from the allowlist (agents.defaults.models). Keys look like "openai/gpt-4o".
    private static func buildCards(root: [String: Any], primary: String) -> [ModelCard] {
        let node = EnterpriseConfigPatch.walk(root, dotPath: EnterpriseConfigPaths.allowlist)
        guard let allowlist = node as? [String: Any] else { return [] }
        return allowlist.keys.compactMap { key -> ModelCard? in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            let providerId = parts.first ?? key
            let modelId = parts.count > 1 ? parts[1] : ""
            let catalog = ProviderCatalog.find(providerId)
            return ModelCard(
                key: key,
                providerId: providerId,
                modelId: modelId,
                providerName: catalog?.name ?? providerId,
                icon: catalog?.icon ?? "📦",
                isDefault: key == primary)
        }
    }

    private static func compareDefaultFirst(_ a: ModelCard, _ b: ModelCard) -> Bool {
        if a.isDefault != b.isDefault { return a.isDefault }
        if a.providerName != b.providerName { return a.providerName < b.providerName }
        return a.modelId < b.modelId
    }

    // MARK: - Writes

    /// New: single patch writes provider config + allowlist + default (AddProviderFullyAsync).
    /// Edit: only the apiKey (SetProviderApiKeyAsync).
    func applyProvider(_ payload: ProviderPayload) async throws {        if payload.isNew {
            let key = "\(payload.id)/\(payload.modelId)"
            let patch: [String: Any] = [
                "models": ["providers": [
                    payload.id: [
                        "api": payload.api,
                        "baseUrl": payload.baseUrl,
                        "apiKey": payload.apiKey,
                        "models": [["id": payload.modelId, "name": payload.modelId]],
                    ] as [String: Any],
                ]],
                "agents": ["defaults": [
                    "models": [key: [String: Any]()],
                    "model": ["primary": key],
                ] as [String: Any]],
            ]
            try await EnterpriseConfigPatch.writePatch(patch)
        } else {
            let patch = EnterpriseConfigPatch.buildNestedPatch(
                parentPath: EnterpriseConfigPaths.providers,
                finalKey: payload.id,
                value: ["apiKey": payload.apiKey])
            try await EnterpriseConfigPatch.writePatch(patch)
        }
    }

    func setDefault(key: String) async throws {        let patch = EnterpriseConfigPatch.buildNestedPatch(
            parentPath: "agents.defaults.model",
            finalKey: "primary",
            value: key)
        try await EnterpriseConfigPatch.writePatch(patch)
    }

    /// null value → key deletion (RFC 7396). Leaf null is legal here (whole key removed).
    func removeAllowlist(key: String) async throws {        let patch = EnterpriseConfigPatch.buildNestedPatch(
            parentPath: EnterpriseConfigPaths.allowlist,
            finalKey: key,
            value: nil)
        try await EnterpriseConfigPatch.writePatch(patch)
    }
}

#if DEBUG
struct ModelsSettings_Previews: PreviewProvider {
    static var previews: some View {
        ModelsSettings(state: .preview)
            .frame(width: SettingsTab.windowWidth, height: SettingsTab.windowHeight)
    }
}
#endif
