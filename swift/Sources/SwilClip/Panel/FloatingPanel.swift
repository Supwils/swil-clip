import AppKit
import SwiftUI

/// The 340×480 frosted panel.
///
/// An `NSPanel` rather than SwiftUI's `MenuBarExtra`, for three reasons that are
/// each individually disqualifying for the simpler route:
///
/// 1. it opens **at the cursor**, anywhere on any display — `MenuBarExtra`
///    anchors to the menu bar;
/// 2. it must be `.nonactivatingPanel` so summoning it does not disturb the app
///    the user was in, which is the foundation of focus restoration;
/// 3. it needs its own size, corner radius and `NSVisualEffectView` backing.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // `.borderless` for the custom shell, `.nonactivatingPanel` so a
            // click does not yank activation away from the frontmost app.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above normal windows but below the menu bar, matching Spotlight.
        level = .popUpMenu
        // Show on every Space and over full-screen apps: a clipboard is needed
        // wherever the user happens to be, and following them across Spaces is
        // less surprising than vanishing.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Never in the window menu or Exposé — it is a transient surface.
        isExcludedFromWindowsMenu = true
        animationBehavior = .utilityWindow
        // The panel is dismissed explicitly (Esc, Enter, click-outside); a
        // system close would bypass focus restoration.
        isMovableByWindowBackground = true
    }

    /// Borderless windows refuse key status by default, which would leave the
    /// entire keyboard-first interaction model dead on arrival.
    override var canBecomeKey: Bool { true }
    /// Never main: that is what would steal the menu bar from the app behind.
    override var canBecomeMain: Bool { false }

    /// Esc must reach the key handler rather than being swallowed as "cancel".
    override func cancelOperation(_ sender: Any?) {}
}

/// The frosted backing.
///
/// `NSVisualEffectView` rather than SwiftUI's `.ultraThinMaterial`: only the
/// AppKit view exposes `.behindWindow` blending, which is what samples the
/// desktop behind the panel. The SwiftUI material samples the window's own
/// content and reads as flat grey over a transparent window.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = Token.Radius.xl

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
    }
}

/// The app shell: glass, hairline border, and the 1 px top edge-glow from
/// `docs/ui-design.md` §4.1.
///
/// ## The scrim goes on top of the glass, not under it
///
/// This used to read `.background(VisualEffectBackground()).background(base)`,
/// which stacks the panel's own colour *behind* the vibrancy view — where a
/// `.behindWindow` effect, which paints its own blurred backdrop, hides it
/// completely. The tint contributed nothing, and the panel was only ever as
/// opaque as `.hudWindow` happened to be. Over a dark desktop that looks
/// deliberate. Over a white IDE or a documentation page it bleeds through and
/// the 95 %-luminance text loses its contrast.
///
/// Putting the tint above the glass gives the panel a contrast floor that does
/// not depend on what is behind it, and makes ``PanelTint`` a real control
/// rather than a constant nobody could see.
struct AppShell<Content: View>: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                ZStack {
                    VisualEffectBackground()
                    theme.scrim
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: metrics.radiusXL, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radiusXL, style: .continuous)
                    .strokeBorder(Token.Border.shell, lineWidth: 0.5)
            }
            .overlay(alignment: .top) {
                // The edge glow. A 1 px gradient reads as a lit bevel; a border
                // would read as a frame — §6: "try a hairline first".
                LinearGradient(
                    colors: [Token.Bevel.edgeGlow, Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
                .padding(.horizontal, metrics.radiusXL)
            }
    }
}
