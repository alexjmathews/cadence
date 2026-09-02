import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = SessionController()

    var body: some Scene {
        // The main window. Launch is suppressed so starting at login stays
        // quiet in the menu bar; the user opens it explicitly.
        Window("Cadence", id: WindowID.main) {
            TimerWindowPlaceholder()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // A window, not a menu (D6): the 272 pt sheet cannot be drawn as one.
        MenuBarExtra {
            MenuBarDropdown(controller: controller)
        } label: {
            MenuBarStatusLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

enum WindowID {
    static let main = "main"
}

/// Stands in for the timer window until the window stage builds it. Deliberately
/// inert: the menu bar, not the window, is what this stage lands.
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
