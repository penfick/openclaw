import OpenClawChatUI
import OpenClawKit
import SwiftUI

/// Which product conversation surface is shown in the main window.
enum MainChatSurface: Equatable {
    case gateway
    case tianyin
}

/// Primary product window: conversation rail + chat transcript (gateway or 天音).
/// Settings lives in a separate window (gear / ⌘, / menu bar).
struct ChatMainView: View {
    @State private var viewModel: OpenClawChatViewModel?
    @State private var connectError: String?
    @State private var surface: MainChatSurface = .gateway
    @State private var tianyinChat = DifyChatModel()
    @AppStorage("openclaw.chat.sessionRailCollapsed") private var sessionRailCollapsed = false

    private var auth: OAAuthCoordinator { OAAuthCoordinator.shared }

    var body: some View {
        Group {
            if !self.auth.authenticated {
                self.loginGate
            } else if let viewModel {
                self.chatChrome(viewModel)
            } else if let connectError {
                self.errorView(connectError)
            } else {
                self.loadingView
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: self.auth.authenticated) {
            guard self.auth.authenticated else {
                self.viewModel = nil
                return
            }
            await self.connect()
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private func chatChrome(_ viewModel: OpenClawChatViewModel) -> some View {
        VStack(spacing: 0) {
            self.topBar(viewModel)
            Divider()
            HStack(spacing: 0) {
                if !self.sessionRailCollapsed {
                    ChatSessionSidebar(
                        viewModel: viewModel,
                        collapsed: self.$sessionRailCollapsed,
                        surface: self.$surface,
                        onNewTianyin: { self.openNewTianyin() })
                    Divider()
                }

                VStack(spacing: 0) {
                    if self.sessionRailCollapsed {
                        self.collapsedRailBar(viewModel)
                        Divider()
                    }
                    self.contentArea(viewModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func contentArea(_ viewModel: OpenClawChatViewModel) -> some View {
        switch self.surface {
        case .gateway:
            OpenClawChatView(viewModel: viewModel, style: .standard)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .tianyin:
            TianyinAssistantView(chat: self.tianyinChat, embedded: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func topBar(_ viewModel: OpenClawChatViewModel) -> some View {
        HStack(spacing: 10) {
            Text("TClaw")
                .font(.headline)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(self.currentTitle(viewModel))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if self.surface == .tianyin {
                Button {
                    AppNavigationActions.openSettings(tab: .tianyinSettings)
                } label: {
                    Label("天音设置", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("天音知识库服务地址与 API Key")
            }

            Button {
                AppNavigationActions.openSettings(tab: .general)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func collapsedRailBar(_ viewModel: OpenClawChatViewModel) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.sessionRailCollapsed = false
                }
            } label: {
                Label("Conversations", systemImage: "sidebar.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Show conversation list")

            Button {
                self.surface = .gateway
                viewModel.startNewSession(label: "New Chat")
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.sessionRailCollapsed = false
                }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("New conversation (⌘N)")
            .keyboardShortcut("n", modifiers: .command)

            Button {
                self.openNewTianyin()
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.sessionRailCollapsed = false
                }
            } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.borderless)
            .help("New 天音 conversation (⌘⇧N)")
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Text(self.currentTitle(viewModel))
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func openNewTianyin() {
        self.tianyinChat.clear()
        self.surface = .tianyin
    }

    private func currentTitle(_ viewModel: OpenClawChatViewModel) -> String {
        switch self.surface {
        case .tianyin:
            return "天音助手"
        case .gateway:
            if viewModel.isMainSessionKey(viewModel.sessionKey) {
                return "Main conversation"
            }
            if let match = viewModel.sidebarSessions.first(where: { $0.key == viewModel.sessionKey }),
               let name = match.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty
            {
                return name
            }
            return viewModel.sessionKey
        }
    }

    private var loginGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("请先登录 OA 账号")
                .font(.title3.weight(.semibold))
            Text("登录后即可使用对话与其它企业功能。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("打开设置登录") {
                AppNavigationActions.openSettings(tab: .account)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Connect

    private func connect() async {
        if self.viewModel != nil { return }
        self.connectError = nil
        let ready = await Self.waitUntilGatewayReady(timeoutSeconds: 60)
        guard !Task.isCancelled else { return }
        guard ready else {
            self.connectError = "连不上 OpenClaw 网关，请确认网关在运行后重试。"
            return
        }
        let key = await GatewayConnection.shared.mainSessionKey()
        guard !Task.isCancelled else { return }
        self.viewModel = OpenClawChatViewModel(
            sessionKey: key,
            transport: MacGatewayChatTransport())
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("正在连接 OpenClaw 网关…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("启动时网关可能需要几秒钟就绪。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                self.viewModel = nil
                Task { await self.connect() }
            }
            .buttonStyle(.borderedProminent)
            Button("打开设置") {
                AppNavigationActions.openSettings(tab: .connection)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func waitUntilGatewayReady(timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var stable = false
        while Date() < deadline {
            if Task.isCancelled { return false }
            let ok = (try? await GatewayConnection.shared.healthOK(timeoutMs: 3000)) ?? false
            if ok {
                if stable { return true }
                stable = true
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                continue
            }
            stable = false
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return false
    }
}
