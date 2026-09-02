import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var loginItem = LoginItemManager()

    var body: some Scene {
        // The main window. Launch is suppressed so starting at login stays
        // quiet in the menu bar; the user opens it explicitly.
        Window("Cadence", id: WindowID.main) {
            TimerWindowPlaceholder()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // The ink mark from the icon handoff. The imageset carries template
        // rendering intent, so AppKit handles light/dark menu bars for us —
        // don't tint it here.
        MenuBarExtra("Cadence", image: "CadenceStatusIdle") {
            MenuBarContentView(loginItem: loginItem)
        }
        .menuBarExtraStyle(.menu)
    }
}

enum WindowID {
    static let main = "main"
}

/// Stands in for the timer window until the window stage builds it. Deliberately
/// inert: the model, not a view, is what this stage lands.
private struct TimerWindowPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(
                width: DesignTokens.Layout.windowSize.width,
                height: DesignTokens.Layout.windowSize.height
            )
            .background(DesignTokens.Surface.base)
    }
}
