import OpenClawChatUI
import OpenClawKit
import SwiftUI

// Chat embedded as a Settings tab. Same view the standalone WebChat window uses
// (OpenClawChatView on the main gateway session) — so this tab and the independent chat window
// render the same main-session conversation. The standalone window (WebChatManager) stays
// available from the menu bar / dock; this just also exposes chat inside Settings.
//
// At launch the gateway (and its WS) may still be coming up, and OpenClawChatView shows a sticky
// "gateway connect" error if its first health probe misses. So we wait for the gateway to be
// HEALTHY (same probe the chat view uses: healthOK) and stable before constructing the chat view
// model — showing a "正在连接 OpenClaw 网关…" loading state meanwhile. Only error after genuinely
// failing to reach the gateway.

struct ChatSettingsView: View {
    @State private var viewModel: OpenClawChatViewModel?
    @State private var connectError: String?

    var body: some View {
        Group {
            if let viewModel {
                OpenClawChatView(viewModel: viewModel, style: .standard)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let connectError {
                self.errorView(connectError)
            } else {
                self.loadingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await self.connect()
        }
    }

    private func connect() async {
        guard self.viewModel == nil else { return }
        self.connectError = nil
        let ready = await Self.waitUntilGatewayReady(timeoutSeconds: 60)
        guard !Task.isCancelled else { return }
        guard ready else {
            self.connectError = "连不上 OpenClaw 网关，请确认网关在运行后重试。"
            return
        }
        let key = await GatewayConnection.shared.mainSessionKey()
        guard !Task.isCancelled else { return }
        self.viewModel = OpenClawChatViewModel(sessionKey: key, transport: MacGatewayChatTransport())
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
                Task { await self.connect() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Poll the gateway's health (the same probe OpenClawChatView uses) until it is reachable AND
    /// stable — two consecutive OKs ~1.2s apart — so the chat view's first health probe doesn't
    /// miss a startup hot-reload and flash a sticky connect error.
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
