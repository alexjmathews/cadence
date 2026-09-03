import SwiftUI

/// The one preference that is not a per-session choice, and the home Stage 5 gives
/// `LoginItemManager`.
///
/// **Why a `Settings` scene.** D8 rules the dropdown sheet out and gives the reason:
/// the sheet is per-session actions, and launch-at-login is set once and then forgotten.
/// The visual specification's row grid (§3.1) has no slot for it either — every row in
/// the window is allocated, and the whole point of that grid is that nothing moves
/// between states, so a preference control would have to displace something the mockups
/// draw. A `Settings` scene is the only surface that adds *no pixels to any mockup*:
/// macOS puts it behind the standard `Cadence ▸ Settings…` item and `⌘,`, which is
/// where a Mac user looks for a set-once preference without being taught.
///
/// **The door is in the sheet; the preference is behind it.** macOS reaches this pane
/// through `Cadence ▸ Settings…` and `⌘,`, both of which need the app promoted out of
/// `.accessory` — so a menu-bar-only user could never enable launch-at-login, which is
/// exactly the user most likely to want it. D8 as amended in Stage 5 answers that the
/// same way it answered Quit: a `Settings… ⌘,` footer row in the dropdown sheet
/// (`AppActivation.showSettings`). The preference itself stays here, because the sheet
/// is per-session actions and a preference with two homes is two things that can
/// disagree.
///
/// `endEarlyBuffer` is deliberately **not** here. It is already a first-class control in
/// the window's swap slot where the mockups put it, and a preference with two homes is
/// two things that can disagree.
struct SettingsView: View {
    /// Owned here rather than by the app: the scene is instantiated when the pane opens,
    /// and `SMAppService.mainApp.status` is read then, which is the only moment the
    /// answer is worth having. A manager held for the app's lifetime would cache a
    /// status the user can change in System Settings behind its back.
    @StateObject private var loginItem = LoginItemManager()

    private typealias Pane = DesignTokens.Layout.Settings

    var body: some View {
        VStack(alignment: .leading, spacing: Pane.captionGap) {
            Toggle(isOn: binding) {
                Text("Launch Cadence at login")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.TextColor.primary)
            }
            .toggleStyle(.switch)
            .tint(DesignTokens.Accent.base)
            .frame(minHeight: Pane.rowHeight)
            .accessibilityLabel("Launch Cadence at login")

            Text("Cadence starts in the menu bar. No window opens.")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.TextColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Pane.padding)
        .frame(width: Pane.width, alignment: .leading)
        .background(DesignTokens.Surface.base)
        // The pane's body is the product's own shell, so its title bar has to be too.
        // Left alone a `Settings` scene keeps the system's light bar over
        // `Surface.base`, which reads as an unfinished window rather than as a
        // deliberately system-chromed preferences pane — and §5 of the visual spec's
        // one statement about title bars is that they follow the shell.
        .background(SettingsChrome())
    }

    /// Writes through `LoginItemManager`, which reflects back whatever the *system*
    /// reports rather than what was asked for. A registration the user then declines in
    /// System Settings has to leave the switch off, or the pane is lying about a state
    /// it does not own.
    private var binding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }
}

/// The dark title bar, and nothing else.
///
/// Deliberately *not* the timer window's `WindowChrome`: that one also applies §3's
/// 520 × 414 size criterion, which on a 320 pt preferences pane would resize it to the
/// timer's geometry. Two windows, two jobs, and the shared part is three lines.
private struct SettingsChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(DesignTokens.Surface.base)
        }
    }
}
