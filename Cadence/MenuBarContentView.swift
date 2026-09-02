import SwiftUI

/// Placeholder menu holding the lifecycle affordances while the product surfaces
/// are built. The dropdown proper — numerals, presets, transport — replaces this.
struct MenuBarContentView: View {
    @ObservedObject var loginItem: LoginItemManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Cadence") {
            AppActivation.showMainWindow(openWindow: openWindow)
        }
        .keyboardShortcut("o")

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))

        Divider()

        Button("Quit Cadence") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Helper for revealing the main window from the menu bar. Promotes the app to
/// a regular (Dock-visible) app, brings it forward, and opens the window.
enum AppActivation {
    @MainActor
    static func showMainWindow(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.main)
    }
}
