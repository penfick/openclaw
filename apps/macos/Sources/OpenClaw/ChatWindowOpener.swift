import AppKit
import SwiftUI

/// Opens the primary TClaw chat window (sessions + conversation).
@MainActor
final class ChatWindowOpener {
    static let shared = ChatWindowOpener()
    static let windowID = "chat"

    private var openAction: (@MainActor () -> Void)?

    func register(openWindow: @escaping @MainActor () -> Void) {
        self.openAction = openWindow
    }

    func open() {
        NSApp.activate(ignoringOtherApps: true)
        DockIconManager.shared.temporarilyShowDock()
        if let openAction {
            openAction()
            return
        }
        // Fallback: nothing registered yet (very early launch) — retry shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.openAction?()
        }
    }
}
