import Foundation

/// The one colour in the interface, as a hue.
///
/// ## Why only a hue
///
/// `docs/ui-design.md` §1 is explicit: hierarchy comes from luminance, and
/// colour means "this is selected" and nothing else. Letting the user pick a
/// free RGB value would let them pick a pale grey that stops meaning selection,
/// or a neon that fights every luminance step around it.
///
/// So the *ratios* stay ratified — saturation 84, lightness 62 in dark and 48
/// in light, exactly the relationships the azure was A/B'd at — and the hue is
/// the single degree of freedom. Every choice lands somewhere the design system
/// already works. The swatch the user picks is the colour they get; nothing is
/// silently corrected behind their back.
public enum AccentPalette {
    /// Brushed Quartz cool azure — `hsl(214, 84%, 62%)`, the ratified default.
    public static let defaultHue: Double = 214

    /// Saturation and lightness, held constant so a hue change cannot walk the
    /// accent out of its role. Lightness differs by appearance: 62 glows on
    /// dark glass and washes out on light, 48 is the reverse.
    public static let saturation: Double = 84
    public static let darkLightness: Double = 62
    public static let lightLightness: Double = 48

    public struct Preset: Sendable, Identifiable, Equatable {
        public let id: String
        public let hue: Double
    }

    /// Eight hues far enough apart to be told apart in a 24 pt swatch.
    public static let presets: [Preset] = [
        Preset(id: "azure", hue: defaultHue),
        Preset(id: "indigo", hue: 248),
        Preset(id: "violet", hue: 276),
        Preset(id: "magenta", hue: 318),
        Preset(id: "rose", hue: 350),
        Preset(id: "amber", hue: 38),
        Preset(id: "lime", hue: 92),
        Preset(id: "teal", hue: 172),
    ]

    /// Wrap any angle into `0..<360`, so a slider that runs off either end and
    /// a value restored from an older build both land somewhere valid.
    public static func normalized(_ hue: Double) -> Double {
        guard hue.isFinite else { return defaultHue }
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Whether text on top of this accent should be black rather than white.
    ///
    /// At a fixed saturation and lightness the *hue* still swings perceived
    /// brightness enormously — `hsl(92, 84%, 62%)` is a highlighter and
    /// `hsl(248, 84%, 62%)` is nearly navy. White-on-lime is unreadable, so the
    /// label colour is derived rather than assumed. WCAG relative luminance,
    /// thresholded where white and black are equally legible.
    public static func prefersDarkLabel(hue: Double, lightness: Double) -> Bool {
        relativeLuminance(hue: normalized(hue), saturation: saturation, lightness: lightness) > 0.42
    }

    /// sRGB relative luminance (WCAG 2.1) of an HSL triple.
    static func relativeLuminance(hue: Double, saturation: Double, lightness: Double) -> Double {
        let (r, g, b) = rgb(hue: hue, saturation: saturation, lightness: lightness)
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// HSL → RGB, in the same form the CSS used, so `Token.hsl` and this agree.
    public static func rgb(hue: Double, saturation: Double, lightness: Double)
        -> (red: Double, green: Double, blue: Double)
    {
        let s = saturation / 100, l = lightness / 100
        let c = (1 - abs(2 * l - 1)) * s
        let hPrime = normalized(hue) / 60
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) =
            switch hPrime {
            case ..<1: (c, x, 0)
            case ..<2: (x, c, 0)
            case ..<3: (0, c, x)
            case ..<4: (0, x, c)
            case ..<5: (x, 0, c)
            default: (c, 0, x)
            }
        let m = l - c / 2
        return (r1 + m, g1 + m, b1 + m)
    }
}
