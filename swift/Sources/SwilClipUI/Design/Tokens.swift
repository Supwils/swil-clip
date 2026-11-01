import AppKit
import SwiftUI
import SwilClipCore

/// **Brushed Quartz** — the design system defined in `docs/ui-design.md`, ported
/// to SwiftUI value-for-value from `tauri/src/global.css`.
///
/// That document is canonical and its §7 values were A/B'd against the running
/// app, so nothing here is re-derived by eye: an 11.5 pt row is 11.5 because it
/// was chosen over 12 and 13, not because it looked about right.
///
/// The one deliberate deviation is the typeface. §5.7 names Geist, which was a
/// web-era workaround for a WebView that could not reach SF at variable weights.
/// A native app can, and the document's own reference points — Spotlight and
/// Raycast — are SF Pro. Using the system font honours §5.7's actual purpose
/// (no network fetches, works offline) with fewer fonts and no bundled asset.
enum Token {}

// MARK: - Colour

extension Token {
    /// One colour in the form the CSS wrote it, so `docs/ui-design.md` §2 and
    /// this file can still be diffed by eye.
    struct HSL: Sendable, Equatable {
        var hue: Double
        var saturation: Double
        var lightness: Double
        var alpha: Double = 1

        init(_ hue: Double, _ saturation: Double, _ lightness: Double, _ alpha: Double = 1) {
            self.hue = hue
            self.saturation = saturation
            self.lightness = lightness
            self.alpha = alpha
        }

        var nsColor: NSColor {
            let (r, g, b) = AccentPalette.rgb(
                hue: hue, saturation: saturation, lightness: lightness
            )
            return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        }
    }

    static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double, _ alpha: Double = 1)
        -> Color
    {
        Color(nsColor: HSL(hue, saturation, lightness, alpha).nsColor)
    }

    /// A colour that resolves itself against whichever appearance is active.
    ///
    /// ## Why `NSColor(name:dynamicProvider:)` and not `@Environment(\.colorScheme)`
    ///
    /// The dynamic provider is resolved by AppKit at draw time, which means one
    /// declaration serves SwiftUI views, the `NSVisualEffectView` behind them,
    /// and the menu-bar menu alike — and none of them has to observe anything.
    /// Reading `colorScheme` instead would mean every view that wants a colour
    /// also needs an environment read, and the AppKit surfaces would need a
    /// parallel path. There is no asset catalogue here to hold a colour set, and
    /// adding one to a script-assembled bundle would buy nothing this does not.
    static func adaptive(dark: HSL, light: HSL) -> Color {
        adaptive(dark: dark.nsColor, light: light.nsColor)
    }

    static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Light-mode counterparts are not inversions.
    ///
    /// Flipping lightness around 50 gives a palette that is technically legible
    /// and looks nothing like macOS: the greys go muddy and the glass turns
    /// grey-blue. Each value below was chosen for its *role* on a light ground —
    /// a hover that is a shade darker than rest rather than lighter, borders
    /// that darken instead of lighten, a bevel that has to be much stronger to
    /// register at all. The dark column is untouched: those values were A/B'd.
    enum Surface {
        /// The panel's own colour, **opaque**. ``AppShell`` applies the alpha,
        /// because how much of the desktop shows through is a user setting now
        /// (``PanelTint``) rather than a constant baked in here.
        static let base = adaptive(dark: HSL(220, 22, 11), light: HSL(220, 26, 97))
        /// Icon chips, nested cards.
        static let soft = adaptive(dark: HSL(220, 18, 16, 0.55), light: HSL(220, 16, 86, 0.66))
        /// Row hover — assistive only; never follows the keyboard cursor.
        static let hover = adaptive(dark: HSL(220, 16, 22, 0.55), light: HSL(220, 14, 80, 0.5))
        /// Inputs, code blocks.
        static let sunk = adaptive(dark: HSL(220, 28, 6, 0.55), light: HSL(220, 20, 92, 0.8))
        static let popover = adaptive(dark: HSL(220, 24, 8, 0.92), light: HSL(220, 26, 98, 0.95))
    }

    /// Five steps of luminance. Pick by **role**, never because a step "looks
    /// right" — that is how a scale turns into a pile of greys.
    enum Foreground {
        /// Primary text: clip previews, dialog bodies.
        static let primary = adaptive(dark: HSL(220, 14, 95), light: HSL(220, 20, 14))
        /// Brand wordmark, hero numerals. Rare.
        static let strong = adaptive(dark: HSL(0, 0, 100), light: HSL(220, 24, 6))
        /// Secondary labels.
        static let muted = adaptive(dark: HSL(220, 10, 64), light: HSL(220, 9, 38))
        /// Tertiary captions.
        static let subtle = adaptive(dark: HSL(220, 8, 46), light: HSL(220, 8, 50))
        /// Placeholders, timestamps, decoration.
        static let faint = adaptive(dark: HSL(220, 8, 32), light: HSL(220, 7, 62))
    }

    enum Border {
        /// App-shell outer hairline.
        static let shell = adaptive(dark: HSL(220, 14, 32, 0.42), light: HSL(220, 16, 58, 0.42))
        /// Divider rules, input borders.
        static let subtle = adaptive(dark: HSL(220, 12, 26, 0.32), light: HSL(220, 12, 56, 0.30))
        /// Hover / focus emphasis.
        static let strong = adaptive(dark: HSL(220, 16, 42, 0.55), light: HSL(220, 14, 46, 0.42))
    }

    /// The "lit from above" highlights — §4.1's edge glow and §4.7's keycap.
    ///
    /// On dark glass a white sliver at 18 % reads as a bevel. On light glass it
    /// is invisible, and the same illusion needs the highlight pushed hard and
    /// the shadow pulled back, or the keycap flattens into a grey box.
    enum Bevel {
        static let edgeGlow = adaptive(
            dark: NSColor(white: 1, alpha: 0.18), light: NSColor(white: 1, alpha: 0.85)
        )
        static let keycapTop = adaptive(
            dark: NSColor(white: 1, alpha: 0.14), light: NSColor(white: 1, alpha: 0.85)
        )
        static let keycapBottom = adaptive(
            dark: NSColor(white: 0, alpha: 0.22), light: NSColor(white: 0, alpha: 0.12)
        )
    }

    enum Status {
        static let destructive = adaptive(dark: HSL(358, 76, 62), light: HSL(358, 68, 46))
        static let destructiveSoft = adaptive(
            dark: HSL(358, 76, 62, 0.14), light: HSL(358, 70, 54, 0.13)
        )
    }
}

// MARK: - Space, radius, motion

extension Token {
    /// The spatial system. Header, footer and list use these and nothing else —
    /// §5.1 is explicit that ad-hoc insets are a bug, not a style choice.
    enum Space {
        /// Outer horizontal inset on the panel.
        static let edge: CGFloat = 12
        /// Inner horizontal padding on list rows.
        static let row: CGFloat = 10
        /// Vertical gap between rows.
        static let rowGap: CGFloat = 2
        /// Ratified in §7: 4, not 5, 6 or 7.
        static let rowVertical: CGFloat = 4
        /// Width reserved on the right of every row so the preview's truncation
        /// point never moves when a row is hovered (§5.2).
        ///
        /// §7 ratified **66** — but that value was derived for a three-action
        /// row (3 × 20 + 2 × 2 gap + 2 breathing). v2's clipboard rows carry a
        /// fourth action, "save as prompt", so the same formula now yields 88.
        /// Computing it keeps the rule intact instead of leaving a constant that
        /// silently under-reserves and lets buttons sit on top of the text —
        /// the exact failure §5.2 exists to prevent.
        static func actionCluster(buttons: Int) -> CGFloat {
            let button: CGFloat = 20, gap: CGFloat = 2, breathing: CGFloat = 2
            return CGFloat(buttons) * button + CGFloat(max(0, buttons - 1)) * gap + breathing
        }

        /// Clipboard and prompt rows both show four actions.
        static let actionCluster: CGFloat = actionCluster(buttons: 4)
    }

    enum Radius {
        /// Keycaps, swatches.
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        /// Buttons, rows, input groups.
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        /// App shell.
        static let xl: CGFloat = 14
    }

    /// Panel geometry, unchanged from v1 — the 340 pt width is part of the
    /// product's visual identity, not an arbitrary number.
    enum Panel {
        static let width: CGFloat = 340
        static let height: CGFloat = 480
        /// Invisible strip at the top that drags the window.
        static let dragRegionHeight: CGFloat = 20
        static let rowHeight: CGFloat = 32
    }

    /// Apple-style spring — never bounce, never elastic. 100–200 ms; anything
    /// slower reads as sluggish in a tool used dozens of times a day.
    enum Motion {
        static let spring = SwiftUI.Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.18)
        static let quick = SwiftUI.Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12)

        /// Every animation must be defeasible by Reduce Motion (§5.6).
        static func gated(_ animation: SwiftUI.Animation) -> SwiftUI.Animation? {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
        }
    }
}

// MARK: - Type scale

extension Token {
    /// Compact by necessity: the panel is 340×480 and density is a feature.
    /// Numerics are always tabular so timestamps and counts stop jittering.
    enum Typography {
        /// Clip preview body — 11.5, ratified over 12 and 13.
        static let row = Font.system(size: 11.5, weight: .regular)
        static let rowMono = Font.system(size: 11.5, weight: .regular, design: .monospaced)
        /// Prompt titles carry slightly more weight; they are names, not content.
        static let rowTitle = Font.system(size: 11.5, weight: .medium)
        /// Image dimensions.
        static let micro = Font.system(size: 9, weight: .regular)
        /// Timestamps and meta.
        static let meta = Font.system(size: 9.5, weight: .regular).monospacedDigit()
        /// Group headings — uppercase, tracked out.
        static let groupHeading = Font.system(size: 9, weight: .semibold)
        /// Brand wordmark.
        static let brand = Font.system(size: 10.5, weight: .semibold)
        static let badge = Font.system(size: 8.5, weight: .medium).monospacedDigit()
        /// Keycaps.
        static let keycap = Font.system(size: 9, weight: .medium, design: .monospaced)
        static let sectionLabel = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 12, weight: .regular)
        static let expanded = Font.system(size: 11.5, weight: .regular)
    }
}
