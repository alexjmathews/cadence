import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = SessionController()

    var body: some Scene {
        // The main window. Launch is suppressed so starting at login stays
        // quiet in the menu bar; the user opens it explicitly.
        Window("Cadence", id: WindowID.main) {
            TimerWindow(controller: controller)
        }
        // 520 × 414 is the window's default and minimum *frame* (§3, §3.2), and
        // `.defaultSize` sizes the content view — which `.hiddenTitleBar` leaves a
        // title bar shorter than the frame. So both this and the content's own
        // `minWidth` / `minHeight` are `windowContentSize`, and the frame comes out
        // at the specified 520 × 414. See `WindowGeometry`.
        .defaultSize(
            width: DesignTokens.Layout.windowContentSize.width,
            height: DesignTokens.Layout.windowContentSize.height
        )
        .defaultLaunchBehavior(.suppressed)
        // The shell recolors on completion, title bar included (§5 of the visual
        // spec), so the title bar is transparent and `WindowChrome` carries the color
        // onto the `NSWindow` itself.
        .windowStyle(.hiddenTitleBar)

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
