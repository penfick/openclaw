import SwiftUI

// Two-step add/edit provider sheet. Mirrors Windows AddProviderDialog.xaml.cs.
// Step 1: built-in provider grid (38 entries, grouped).
// Step 2: credentials form + "fetch available models" (direct HTTP GET {baseUrl}/models + Bearer,
//         because the provider is NOT yet in config so gateway models.list can't see it).
// New → ProviderPayload(isNew:true); Edit (locked id) → ProviderPayload(isNew:false) updates apiKey only.

struct AddProviderSheet: View {
    let editing: ProviderEditTarget?
    @Binding var isSaving: Bool
    @Binding var error: String?
    let onCancel: () -> Void
    let onSave: (ProviderPayload) -> Void

    @State private var step: Int = 1
    @State private var selectedDef: ProviderDefinition?
    @State private var idText: String = ""
    @State private var baseUrlText: String = ""
    @State private var apiKey: String = ""
    @State private var modelIdText: String = ""
    @State private var fetchedModels: [String] = []
    @State private var isFetching: Bool = false
    @State private var customApi: String = "openai-completions"

    private let apiTypes = ["openai-completions", "openai-responses", "anthropic-messages", "google-generative-ai"]

    init(
        editing: ProviderEditTarget?,
        isSaving: Binding<Bool>,
        error: Binding<String?>,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ProviderPayload) -> Void)
    {
        self.editing = editing
        self._isSaving = isSaving
        self._error = error
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(self.editing == nil ? "添加 Provider" : "编辑 Provider")
                    .font(.headline)
                Spacer()
            }

            if self.step == 1 && self.editing == nil {
                self.step1View
            } else {
                self.step2View
            }

            if let error = self.error {
                Text(error).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if self.editing == nil && self.step == 2 {
                    Button("返回") {
                        self.step = 1
                        self.error = nil
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("取消", role: .cancel) { self.onCancel() }
                Button(self.editing == nil ? "添加" : "保存") { self.confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.isSaving || self.isFetching)
            }
        }
        .padding(20)
        .onAppear {
            if let editing {
                self.step = 2
                self.idText = editing.id
                self.baseUrlText = editing.baseUrl
                self.customApi = editing.api
            }
        }
    }

    // MARK: - Step 1: provider grid

    private var step1View: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ProviderCatalog.grouped(), id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(group.providers) { def in
                                Button { self.selectDef(def) } label: {
                                    HStack(spacing: 8) {
                                        Text(def.icon)
                                        Text(def.name).font(.callout)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 2: credentials

    private var step2View: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let def = self.selectedDef {
                HStack(spacing: 10) {
                    Text(def.icon).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.name).font(.callout.weight(.semibold))
                        Text(def.categoryHint).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            self.fieldRow("Provider ID") {
                TextField("openai", text: self.$idText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(self.editing != nil)
            }

            if self.showBaseUrlField {
                self.fieldRow("Base URL") {
                    TextField("https://api.example.com/v1", text: self.$baseUrlText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(self.editing != nil)
                }
            }

            if self.isCustom {
                self.fieldRow("API 类型") {
                    Picker("", selection: self.$customApi) {
                        ForEach(self.apiTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
            }

            self.fieldRow("API Key") {
                SecureField(self.apiKeyPlaceholder, text: self.$apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if self.editing == nil {
                self.fieldRow("Model ID") {
                    if self.fetchedModels.isEmpty {
                        TextField("模型 ID", text: self.$modelIdText)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("", selection: self.$modelIdText) {
                            ForEach(self.fetchedModels, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                }

                HStack {
                    Button {
                        Task { await self.fetchModels() }
                    } label: {
                        if self.isFetching {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("获取可用模型", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.isFetching || self.baseUrlText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
            }
        }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(title).font(.callout).frame(width: 84, alignment: .leading)
            content()
        }
    }

    // MARK: - Derived

    private var isCustom: Bool {
        self.editing == nil && self.selectedDef?.id == "custom"
    }

    private var showBaseUrlField: Bool {
        if self.editing != nil { return true }
        guard let def = self.selectedDef else { return false }
        return def.showBaseUrl || def.id == "custom"
    }

    private var apiKeyPlaceholder: String {
        if self.selectedDef?.category == "local" { return "本地模型可留空" }
        return "sk-..."
    }

    private var resolvedApi: String {
        if let editing { return editing.api }
        if self.selectedDef?.id == "custom" { return self.customApi }
        return self.selectedDef?.api ?? "openai-completions"
    }

    // MARK: - Actions

    private func selectDef(_ def: ProviderDefinition) {
        self.selectedDef = def
        self.idText = def.id
        self.baseUrlText = def.defaultBaseUrl ?? ""
        self.modelIdText = def.showModelId ? def.defaultModelId : ""
        self.customApi = def.api
        self.error = nil
        self.step = 2
    }

    private func confirm() {
        self.error = nil
        let id = self.idText.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { self.error = "Provider ID 为空。"; return }

        let apiKey = self.apiKey
        let modelId = self.modelIdText.trimmingCharacters(in: .whitespaces)

        if self.editing == nil {
            guard !modelId.isEmpty else { self.error = "请选择或填写模型。"; return }
        } else {
            guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { self.error = "请输入新的 API Key。"; return }
        }

        let payload = ProviderPayload(
            isNew: self.editing == nil,
            id: id,
            api: self.resolvedApi,
            baseUrl: self.baseUrlText.trimmingCharacters(in: .whitespaces),
            apiKey: apiKey,
            modelId: self.editing == nil ? modelId : "")
        self.onSave(payload)
    }

    // MARK: - Fetch available models (direct HTTP, not gateway)

    private func fetchModels() async {
        let base = self.baseUrlText.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { self.error = "请先填写 Base URL。"; return }

        self.isFetching = true
        self.error = nil
        defer { self.isFetching = false }

        guard let url = URL(string: "\(base)/models") else {
            self.error = "Base URL 无效。"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let key = self.apiKey.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                self.error = "无响应。"
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                self.error = "获取失败 (\(http.statusCode))：\(String(body.prefix(200)))"
                return
            }
            let models = Self.parseModels(data)
            if models.isEmpty {
                self.error = "未找到模型。请检查 Base URL 和 API Key。"
                return
            }
            self.fetchedModels = models
            if self.modelIdText.isEmpty { self.modelIdText = models[0] }
        } catch {
            self.error = "获取失败：\(error.localizedDescription)"
        }
    }

    /// Accepts OpenAI { data: [{ id }] } and bare arrays [{ id }]; sorted ascending.
    private static func parseModels(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var ids: [String] = []
        if let dict = json as? [String: Any], let arr = dict["data"] as? [[String: Any]] {
            for item in arr {
                if let id = item["id"] as? String, !id.isEmpty { ids.append(id) }
            }
        } else if let arr = json as? [[String: Any]] {
            for item in arr {
                if let id = item["id"] as? String, !id.isEmpty { ids.append(id) }
            }
        }
        return ids.sorted()
    }
}
