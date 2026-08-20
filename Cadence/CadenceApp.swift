import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var loginItem = LoginItemManager()

    var body: some Scene {
        // The main window. Launch is suppressed so starting at login stays
        // quiet in the menu bar; the user opens it explicitly.
        Window("Cadence", id: WindowID.main) {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra("Cadence", systemImage: "timer") {
            MenuBarContentView(loginItem: loginItem)
        }
        .menuBarExtraStyle(.menu)
    }
}

enum WindowID {
    static let main = "main"
}
