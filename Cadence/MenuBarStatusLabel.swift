import SwiftUI

/// The status item itself: the ink mark alone when there is nothing to report, and
/// the mark plus a countdown in an accent pill once a session exists.
///
/// The countdown redraws from the controller's tick (D1) rather than from
/// `Text(timerInterval:)`, which does not reliably self-update here. Reading
/// `controller.now` is what subscribes this label to that tick.
///
/// The composed states are rasterised and handed over as a single non-template
/// image: a `MenuBarExtra` label built from live views is flattened to a template
/// mask, which loses the accent and mint the mockups call for.
struct MenuBarStatusLabel: View {
    let controller: SessionController

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let status = controller.status

        if status == .idle {
            // Nothing to tint: the mark is monochrome, so let the menu bar own it
            // and get light/dark handling for free.
            Image("CadenceStatusIdle")
                .accessibilityLabel(accessibilityLabel(for: status))
        } else {
            Image(nsImage: PillCache.image(clockText: controller.clockText, status: status, scale: scale))
                .renderingMode(.original)
                .accessibilityLabel(accessibilityLabel(for: status))
        }
    }

    /// `displayScale` resolves against the *main* display, but the menu bar the
    /// item is drawn into may be on another one — a Retina laptop screen beside a
    /// 1× primary renders visibly soft. Rasterising at the sharpest scale attached
    /// is always safe: `NSImage.size` stays in points, so an over-rendered bitmap
    /// simply downsamples.
    private var scale: CGFloat {
        max(displayScale, NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
    }

    private func accessibilityLabel(for status: SessionStatus) -> String {
        switch status {
        case .idle: "Cadence, ready"
        case .running: "Cadence, \(controller.clockText) remaining"
        case .paused: "Cadence, paused at \(controller.clockText)"
        case .complete: "Cadence, session complete"
        }
    }
}

/// One rasterised pill, kept until something about it changes. The ticker redraws
/// the label every second, but the bitmap only differs when the digits, the state,
/// or the display do — so the render happens once per change instead of once per
/// tick.
@MainActor
private enum PillCache {
    private struct Key: Equatable {
        var clockText: String
        var status: SessionStatus
        var scale: CGFloat
    }

    private static var key: Key?
    private static var image: NSImage?

    static func image(clockText: String, status: SessionStatus, scale: CGFloat) -> NSImage {
        let key = Key(clockText: clockText, status: status, scale: scale)
        if key == Self.key, let image { return image }

        let renderer = ImageRenderer(content: StatusPill(clockText: clockText, status: status))
        renderer.scale = scale
        let rendered = renderer.nsImage ?? NSImage()
        rendered.isTemplate = false

        Self.key = key
        Self.image = rendered
        return rendered
    }
}

/// The mark and countdown as the mockups compose them, with one departure: the
/// pill is opaque.
///
/// The mockups tint the bar itself — accent at 28% over a near-black menu bar. But
/// `isTemplate = false` opts the bitmap out of AppKit's light/dark handling, and
/// the menu bar's appearance follows the *wallpaper*, not the system theme, so on a
/// light bar that tint collapses to roughly 1.5:1 against its own label. A
/// `MenuBarExtra` label has no access to the status button's effective appearance,
/// so it cannot adapt; instead the pill composites the tint over `Surface.base`
/// and ships opaque. On a dark bar that lands on the mockup's own rendered color;
/// on a light one it stays a legible dark chip.
private struct StatusPill: View {
    let clockText: String
    let status: SessionStatus

    private typealias Item = DesignTokens.Layout.StatusItem

    var body: some View {
        HStack(spacing: Item.pillContentGap) {
            mark
                .resizable()
                .renderingMode(.template)
                .frame(width: Item.glyphSize, height: Item.glyphSize)
                .foregroundStyle(tint)

            Text(clockText)
                .font(DesignTokens.Typography.listTime)
                .monospacedDigit()
                .foregroundStyle(label)
        }
        .padding(.horizontal, Item.pillHorizontalPadding)
        .frame(height: Item.pillHeight)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Layout.statusItemPillRadius)
                .fill(DesignTokens.Surface.base)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Layout.statusItemPillRadius)
                        .fill(tint.opacity(Item.pillTintOpacity))
                }
        }
    }

    private var mark: Image {
        switch status {
        case .idle, .paused: Image("CadenceStatusIdle")
        case .running: Image("CadenceStatusRunning")
        case .complete: Image("CadenceStatusComplete")
        }
    }

    /// The glyph and the pill take the state accent; the countdown takes its
    /// on-dark text weight, which is what keeps the digits legible over the tint.
    private var tint: Color {
        status == .complete ? DesignTokens.Accent.complete : DesignTokens.Accent.base
    }

    private var label: Color {
        status == .complete ? DesignTokens.Accent.completeText : DesignTokens.Accent.text
    }
}
