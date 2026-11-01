import AppKit
import SwiftUI
import SwilClipCore

/// The two colour decisions the user owns: which hue means "selected", and how
/// much of the desktop shows through the glass.
///
/// ## Why this is in the environment and `Token` is not
///
/// `Token.Surface`, `Token.Foreground` and friends resolve themselves against
/// the active appearance, so they can stay static — nothing has to hand them
/// down. The accent cannot: it depends on a *preference*, and a static that
/// reads `UserDefaults` would be a second source of truth for a value
/// `@Observable` already tracks, and would not invalidate a single view when it
/// changed. So it travels the same road as ``Metrics`` and ``Strings``:
/// injected once at the root of each window, read by whoever draws with it.
///
/// The consequence worth stating: there is deliberately **no**
/// `Token.Accent.base` any more. If a colour that means "selected" could be
/// reached without the environment, some view would eventually reach for it and
/// quietly keep the old azure while the rest of the panel changed hue.
struct Theme: Equatable, Sendable {
    var accentHue: Double = AccentPalette.defaultHue
    var tint: PanelTint = .standard

    init(accentHue: Double = AccentPalette.defaultHue, tint: PanelTint = .standard) {
        self.accentHue = AccentPalette.normalized(accentHue)
        self.tint = tint
    }

    // MARK: - Accent ramp
    //
    // Saturation and lightness come from AccentPalette and never vary: the hue
    // is the only degree of freedom, which is what keeps every choice inside
    // the design system rather than merely inside the colour space.

    /// Selected-row rail, focus ring, active tab badge, primary buttons.
    var accent: Color { accentColor() }
    /// Selected icon chip tint.
    var accentSoft: Color { accentColor(alpha: 0.16) }
    /// Soft accent backgrounds (`--color-accent-muted`, §2.4).
    ///
    /// Its own saturation and lightness — 70/50, not the 84/62 the rest of the
    /// ramp uses — because that is what the CSS shipped. No view draws with it
    /// today; it is kept faithful rather than dropped so the next soft accent
    /// state is a lookup instead of an invention.
    var accentMuted: Color {
        Token.adaptive(
            dark: Token.HSL(accentHue, 70, 50, 0.22),
            light: Token.HSL(accentHue, 70, 44, 0.20)
        )
    }
    /// Focus ring on a recording shortcut field.
    var accentRing: Color { accentColor(alpha: 0.45) }

    /// Fill behind the selected row — a wider, softer step than ``accent`` so a
    /// 16 % wash still reads as tinted rather than as grey.
    var selectionFill: Color {
        Token.adaptive(
            dark: Token.HSL(accentHue, 64, 52, 0.16),
            light: Token.HSL(accentHue, 64, 46, 0.13)
        )
    }

    /// Text drawn *on* ``accent``.
    ///
    /// Derived, not assumed: at a fixed saturation and lightness the hue still
    /// swings perceived brightness from navy to highlighter, and white on lime
    /// is unreadable. See ``AccentPalette/prefersDarkLabel(hue:lightness:)``.
    var onAccent: Color {
        let dark = AccentPalette.prefersDarkLabel(
            hue: accentHue, lightness: AccentPalette.darkLightness
        )
        let light = AccentPalette.prefersDarkLabel(
            hue: accentHue, lightness: AccentPalette.lightLightness
        )
        return Token.adaptive(dark: label(dark), light: label(light))
    }

    // MARK: - Glass

    /// The panel's own colour layer, at the opacity the user chose.
    ///
    /// This sits **on top of** the vibrancy view — see ``AppShell``. It is the
    /// only thing standing between a white window behind the panel and the
    /// panel's own text, so it is also the only real answer to "the background
    /// does not cover a bright app".
    var scrim: Color { Token.Surface.base.opacity(tint.scrimOpacity) }

    /// The colour a given hue actually produces, for swatches and the hue
    /// spectrum. Shared with ``accent`` so the chip the user clicks is exactly
    /// the colour they get — a picker that shows one colour and applies another
    /// is worse than no picker.
    static func swatch(hue: Double) -> Color {
        Token.adaptive(
            dark: Token.HSL(hue, AccentPalette.saturation, AccentPalette.darkLightness),
            light: Token.HSL(hue, AccentPalette.saturation, AccentPalette.lightLightness)
        )
    }

    // MARK: - Private

    private func accentColor(alpha: Double = 1) -> Color {
        Token.adaptive(
            dark: Token.HSL(
                accentHue, AccentPalette.saturation, AccentPalette.darkLightness, alpha
            ),
            light: Token.HSL(
                accentHue, AccentPalette.saturation, AccentPalette.lightLightness, alpha
            )
        )
    }

    private func label(_ preferDark: Bool) -> NSColor {
        // Not pure black / pure white: both are harsher than the surrounding
        // luminance ramp, and the panel has no other pure values in it.
        preferDark
            ? Token.HSL(220, 30, 10).nsColor
            : Token.HSL(0, 0, 100).nsColor
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Appearance

extension Appearance {
    /// `nil` means "inherit", which is exactly what `.system` wants.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Push the choice at `NSApp`, which covers the panel, both sheets and the
    /// `NSVisualEffectView` in one assignment — the vibrancy material picks its
    /// own light or dark variant from the appearance it inherits.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
