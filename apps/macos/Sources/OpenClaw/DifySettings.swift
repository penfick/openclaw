import SwiftUI

// 天音知识库 (Dify) integration. Mirrors Windows DifyPage.xaml.cs (天音 redesign).
// Independent of the gateway and OA — connects directly to a self-hosted Dify instance via SSE.
// Code names stay Dify* / dify:*; only USER-VISIBLE strings are de-branded to 天音知识库.
// Base URL in UserDefaults (plaintext), API key in Keychain (OAKeychain.difyApiKey).
// Chat history + conversationId persist to ~/Library/Application Support/OpenClaw/dify-chat.json
// so navigating away and back keeps the conversation.

enum DifyConfig {
    private static let baseUrlKey = "openclaw.dify.baseUrl"

    static var baseUrl: String {
        UserDefaults.standard.string(forKey: Self.baseUrlKey) ?? ""
    }

    static func saveBaseUrl(_ value: String) {
        UserDefaults.standard.set(value, forKey: Self.baseUrlKey)
    }

    static var apiKey: String? { OAKeychain.difyApiKey }

    static func saveApiKey(_ value: String) {
        OAKeychain.saveDifyApiKey(value)
    }
}

// MARK: - Message + persistence

struct DifyMessage: Identifiable, Codable, Hashable {
    let id: String
    let role: Role
    var text: String
    var think: String?
    var thinkInProgress: Bool

    enum Role: String, Codable { case user, assistant }

    init(id: String = UUID().uuidString, role: Role, text: String, think: String? = nil, thinkInProgress: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.think = think
        self.thinkInProgress = thinkInProgress
    }
}

/// Persisted chat snapshot (messages + conversation id) so navigation away and back keeps context.
enum DifyChatStore {
    private static let fileName = "dify-chat.json"

    struct Snapshot: Codable {
        var messages: [DifyMessage] = []
        var conversationId: String?
    }

    private static func url() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        else { return nil }
        let appDir = dir.appendingPathComponent("OpenClaw", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent(Self.fileName)
    }

    static func load() -> Snapshot {
        guard let url = Self.url(),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Snapshot() }
        return snap
    }

    static func save(_ snapshot: Snapshot) {
        guard let url = Self.url(),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

// MARK: - <think> stream parsing

private struct ParsedStream {
    var answer: String
    var think: String
    var thinkInProgress: Bool
}

/// Split a streamed answer into answer text + collapsible think content.
/// Handles multiple `<think>…</think>` blocks; an UNCLOSED `<think>` (mid-stream) is treated as
/// in-progress reasoning so it never renders as big answer text — the key fix from the Windows
/// 天音 redesign (otherwise during streaming the think shows as the answer and only shrinks at end).
private func parseDifyThink(_ raw: String) -> ParsedStream {
    var answer = ""
    var think = ""
    var thinkInProgress = false
    let openTag = "<think>"
    let closeTag = "</think>"
    var i = raw.startIndex
    var inThink = false
    while i < raw.endIndex {
        if !inThink {
            if let r = raw.range(of: openTag, range: i..<raw.endIndex) {
                answer += raw[i..<r.lowerBound]
                i = r.upperBound
                inThink = true
            } else {
                answer += raw[i..<raw.endIndex]
                break
            }
        } else if let r = raw.range(of: closeTag, range: i..<raw.endIndex) {
            think += raw[i..<r.lowerBound]
            i = r.upperBound
            inThink = false
        } else {
            // open <think> with no closing tag yet → remainder is in-progress reasoning.
            think += raw[i..<raw.endIndex]
            thinkInProgress = true
            break
        }
    }
    return ParsedStream(answer: answer, think: think, thinkInProgress: thinkInProgress)
}

// MARK: - View model

@MainActor
@Observable
final class DifyChatModel {
    var messages: [DifyMessage] = []
    var input: String = ""
    var isLoading = false
    var error: String?
    var conversationId: String?

    private var rawBuffer = ""

    init() {
        let snapshot = DifyChatStore.load()
        self.messages = snapshot.messages
        self.conversationId = snapshot.conversationId
    }

    private func persist() {
        DifyChatStore.save(.init(messages: self.messages, conversationId: self.conversationId))
    }

    func clear() {
        self.messages = []
        self.conversationId = nil
        self.rawBuffer = ""
        self.error = nil
        self.persist()
    }

    func send() async {
        let query = self.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let baseUrl = DifyConfig.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseUrl.isEmpty else {
            self.error = "请先配置天音知识库服务地址。"
            return
        }
        guard let apiKey = DifyConfig.apiKey, !apiKey.isEmpty else {
            self.error = "请先配置天音知识库 API Key。"
            return
        }

        // Normalize so we don't double the /v1 segment: if the configured base already ends with
        // /v1 (e.g. "http://host/v1"), append only /chat-messages; otherwise add /v1/chat-messages.
        let trimmedBase = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = trimmedBase.lowercased().hasSuffix("/v1")
            ? "\(trimmedBase)/chat-messages"
            : "\(trimmedBase)/v1/chat-messages"
        guard let url = URL(string: endpoint) else {
            self.error = "天音知识库服务地址无效。"
            return
        }

        self.isLoading = true
        self.error = nil
        self.input = ""
        self.messages.append(DifyMessage(role: .user, text: query))
        self.persist()

        var body: [String: Any] = [
            "inputs": [:],
            "query": query,
            "response_mode": "streaming",
            "user": "openclaw-mac",
        ]
        if let conversationId { body["conversation_id"] = conversationId }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Placeholder assistant message mutated as the stream arrives.
        let assistantId = UUID().uuidString

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                self.error = "天音知识库请求失败（HTTP \(code)）。请检查「天音设置」的服务地址是否正确（实际调用：\(endpoint)）。"
                self.isLoading = false
                self.persist()
                return
            }

            self.rawBuffer = ""
            self.messages.append(DifyMessage(id: assistantId, role: .assistant, text: ""))

            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                if let delta = json["answer"] as? String { self.rawBuffer += delta }
                if let cid = json["conversation_id"] as? String { self.conversationId = cid }
                let parsed = parseDifyThink(self.rawBuffer)
                self.updateAssistant(
                    id: assistantId,
                    text: parsed.answer,
                    think: parsed.think.isEmpty ? nil : parsed.think,
                    thinkInProgress: parsed.thinkInProgress)
                if (json["event"] as? String) == "error" {
                    let message = json["message"] as? String ?? "未知错误"
                    self.error = "天音知识库错误：\(message)"
                    break
                }
            }
            // Final pass — stream done; any open think is now considered closed.
            let parsed = parseDifyThink(self.rawBuffer)
            self.updateAssistant(
                id: assistantId,
                text: parsed.answer,
                think: parsed.think.isEmpty ? nil : parsed.think,
                thinkInProgress: false)
        } catch {
            self.error = "天音知识库请求失败：\(error.localizedDescription)"
        }

        self.isLoading = false
        self.persist()
    }

    private func updateAssistant(id: String, text: String, think: String?, thinkInProgress: Bool) {
        guard let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
        self.messages[index].text = text
        self.messages[index].think = think
        self.messages[index].thinkInProgress = thinkInProgress
    }
}

// MARK: - Views

// MARK: - 天音助手 (conversation)

struct TianyinAssistantView: View {
    @State private var chat = DifyChatModel()

    var body: some View {
        // Chat-app layout: header on top, transcript fills the middle, input pinned at the bottom.
        // Root MUST claim full height (not settingsDetailContent, which doesn't set maxHeight) —
        // otherwise the greedy transcript ScrollView squeezes the input bar off-screen.
        VStack(alignment: .leading, spacing: 14) {
            SettingsPageHeader(
                title: "天音助手",
                subtitle: "与天音知识库对话（独立于网关 / OA）。")

            self.messagesArea

            self.inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Conversation transcript — fills the available height and scrolls independently.
    @ViewBuilder
    private var messagesArea: some View {
        if self.chat.messages.isEmpty {
            Text("发送一条消息开始与天音知识库对话。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(self.chat.messages) { message in
                            DifyMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: self.chat.messages.last?.text) { _, _ in
                    if let last = self.chat.messages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    /// Input bar pinned at the bottom of the page (mirrors the Chat menu).
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = self.chat.error {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                TextField("输入消息", text: self.$chat.input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await self.chat.send() } }
                Button {
                    Task { await self.chat.send() }
                } label: {
                    if self.chat.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("发送", systemImage: "paperplane")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.chat.isLoading || self.chat.input.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(role: .destructive) {
                    self.chat.clear()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(self.chat.messages.isEmpty)
            }
        }
    }
}

// MARK: - 天音设置 (config)

struct TianyinSettingsView: View {
    @State private var baseUrlText: String = DifyConfig.baseUrl
    @State private var apiKeyText: String = DifyConfig.apiKey ?? ""
    @State private var configSaved: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "天音设置",
                    subtitle: "配置天音知识库的服务地址与 API Key（独立于网关 / OA）。")
                self.configCard
                Spacer(minLength: 8)
            }
            .settingsDetailContent()
        }
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCardGroup("天音知识库") {
                SettingsCardRow(title: "服务地址", showsDivider: true) {
                    TextField("https://tianyin.example.com", text: self.$baseUrlText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                SettingsCardRow(title: "API Key", showsDivider: false) {
                    SecureField("app-xxxx", text: self.$apiKeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
            }
            HStack {
                Button("保存") {
                    DifyConfig.saveBaseUrl(self.baseUrlText.trimmingCharacters(in: .whitespaces))
                    DifyConfig.saveApiKey(self.apiKeyText)
                    self.configSaved = "已保存。"
                }
                .buttonStyle(.borderedProminent)
                if let configSaved = self.configSaved {
                    Text(configSaved).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DifyMessageBubble: View {
    let message: DifyMessage

    var body: some View {
        if self.message.role == .user {
            self.userBubble
        } else {
            self.assistantBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(self.message.text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Self.avatar(systemName: "person.fill", tint: .accentColor)
            }
            .frame(maxWidth: 320, alignment: .trailing)
        }
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Self.avatar(systemName: "sparkles", tint: .secondary)
            VStack(alignment: .leading, spacing: 6) {
                if let think = self.message.think, !think.isEmpty {
                    DifyThinkBlock(think: think, inProgress: self.message.thinkInProgress)
                }
                if !self.message.text.isEmpty {
                    Text(self.message.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if self.message.thinkInProgress {
                    Text("思考中…").font(.caption).italic().foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private static func avatar(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(tint, in: Circle())
    }
}

private struct DifyThinkBlock: View {
    let think: String
    let inProgress: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                self.expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: self.expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(self.inProgress ? "思考中…" : "思考过程")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if self.expanded {
                Text(self.think)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
