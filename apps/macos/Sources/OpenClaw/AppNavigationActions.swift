import AppKit

@MainActor
enum AppNavigationActions {
    static func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        if DashboardManager.shared.showConfiguredWindowIfPossible() {
            return
        }
        Task { @MainActor in
            if DashboardManager.shared.showConfiguredWindowIfPossible() {
                return
            }
            do {
                try await DashboardManager.shared.show()
            } catch {
                DashboardManager.shared.showFailure(error)
            }
        }
    }

    /// Opens the primary multi-session chat window (not the legacy floating panel).
    static func openChat() {
        ChatWindowOpener.shared.open()
    }

    /// Legacy floating chat panel (menu-bar popover style). Kept for `--chat` / power users.
    static func openChatPanel() {
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let sessionKey = await WebChatManager.shared.preferredSessionKey()
            WebChatManager.shared.show(sessionKey: sessionKey)
        }
    }

    static func toggleCanvas() {
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            if AppStateStore.shared.canvasPanelVisible {
                CanvasManager.shared.hideAll()
            } else {
                let sessionKey = await GatewayConnection.shared.mainSessionKey()
                _ = try? CanvasManager.shared.show(sessionKey: sessionKey, path: nil)
            }
        }
    }

    static func openSettings(tab: SettingsTab = .general) {
        // Chat is no longer a settings tab — route to the main chat window.
        if tab == .chat {
            openChat()
            return
        }
        SettingsTabRouter.request(tab)
        SettingsWindowOpener.shared.open()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openclawSelectSettingsTab, object: tab)
        }
    }
}
