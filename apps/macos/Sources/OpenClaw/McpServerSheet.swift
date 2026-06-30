import SwiftUI

// MCP server add/edit sheet. Mirrors Windows McpServerDialog.xaml.cs.
// stdio → { command, args?, env? } (NO transport field; omitting transport == stdio).
// http  → { transport: "streamable-http", url }.
// Only fields that exist are written — a LEAF null is rejected by the gateway schema and
// rolls back the whole patch. Edit mode locks name + type (merge-patch can't cleanly replace
// a sub-object; switching type = delete + re-add).

struct McpServerSheet: View {
    let editing: Bool
    @Binding var isSaving: Bool
    @Binding var error: String?
    let initialName: String?
    let initialServer: [String: Any]?
    let onCancel: () -> Void
    let onSave: (String, [String: Any]) -> Void

    @State private var name: String = ""
    @State private var transport: String = "stdio"
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var env: String = ""
    @State private var url: String = ""

    private let transports = ["stdio", "streamable-http"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(self.editing ? "编辑 MCP 服务器" : "添加 MCP 服务器")
                .font(.headline)

            self.fieldRow("名称") {
                TextField("my-server", text: self.$name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(self.editing)
            }

            self.fieldRow("类型") {
                Picker("", selection: self.$transport) {
                    ForEach(self.transports, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .disabled(self.editing)
            }

            if self.transport == "stdio" {
                self.fieldRow("命令") {
                    TextField("npx", text: self.$command)
                        .textFieldStyle(.roundedBorder)
                }
                self.fieldRow("参数") {
                    TextField("空格分隔：-y @modelcontextprotocol/server-filesystem /tmp", text: self.$args)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("环境变量").font(.callout)
                    TextEditor(text: self.$env)
                        .font(.callout)
                        .frame(minHeight: 70, maxHeight: 110)
                        .padding(4)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    Text("每行 KEY=value").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                self.fieldRow("URL") {
                    TextField("https://example.com/mcp", text: self.$url)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let error = self.error {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { self.onCancel() }
                Button(self.editing ? "保存" : "添加") { self.confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.isSaving)
            }
        }
        .padding(20)
        .onAppear { self.configureFromInitial() }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(title).font(.callout).frame(width: 64, alignment: .leading)
            content()
        }
    }

    // MARK: - Configure from existing (edit mode)

    private func configureFromInitial() {
        self.name = self.initialName ?? ""
        guard let server = self.initialServer else { return }

        let t = server["transport"] as? String ?? ""
        let hasCommand = server["command"] != nil
        let isStdio = t.isEmpty || t == "stdio" || hasCommand
        self.transport = isStdio ? "stdio" : t

        self.command = server["command"] as? String ?? ""
        if let argsArr = server["args"] as? [String] {
            self.args = argsArr.joined(separator: " ")
        } else if let argsArr = server["args"] as? [Any] {
            self.args = argsArr.map { String(describing: $0) }.joined(separator: " ")
        }
        self.env = Self.envToText(server["env"])
        self.url = server["url"] as? String ?? ""
    }

    private static func envToText(_ raw: Any?) -> String {
        guard let raw else { return "" }
        if let dict = raw as? [String: String] {
            return dict.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        }
        if let dict = raw as? [String: Any] {
            return dict.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        }
        return ""
    }

    // MARK: - Build + validate

    private func confirm() {
        self.error = nil
        let name = self.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { self.error = "请填写名称。"; return }
        if self.transport == "stdio" {
            guard !self.command.trimmingCharacters(in: .whitespaces).isEmpty else {
                self.error = "stdio 类型需要填写命令。"
                return
            }
        } else {
            guard !self.url.trimmingCharacters(in: .whitespaces).isEmpty else {
                self.error = "streamable-http 类型需要填写 URL。"
                return
            }
        }
        self.onSave(name, Self.buildServer(transport: self.transport, command: self.command, args: self.args, url: self.url, env: self.env))
    }

    /// stdio → { command, args?, env? } (no transport); http → { transport, url }.
    /// Empty optional fields are omitted (never written as null).
    static func buildServer(transport: String, command: String, args: String, url: String, env: String) -> [String: Any] {
        if transport == "stdio" {
            var server: [String: Any] = ["command": command.trimmingCharacters(in: .whitespaces)]
            let argList = args.split(whereSeparator: { $0 == " " })
                .map { String($0) }
                .filter { !$0.isEmpty }
            if !argList.isEmpty { server["args"] = argList }
            if let envDict = parseEnv(env), !envDict.isEmpty { server["env"] = envDict }
            return server
        }
        return ["transport": transport, "url": url.trimmingCharacters(in: .whitespaces)]
    }

    /// Per-line KEY=value; lines without '=' (or empty key) are skipped. nil if none.
    static func parseEnv(_ text: String) -> [String: String]? {
        var env: [String: String] = [:]
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let eq = line.firstIndex(of: "="), eq > line.startIndex else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            env[key] = value
        }
        return env.isEmpty ? nil : env
    }
}
