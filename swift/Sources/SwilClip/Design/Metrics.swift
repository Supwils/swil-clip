import SwiftUI
import SwilClipCore

/// How large the panel is.
///
/// The 340×480 default was tuned on a laptop display and is genuinely cramped on
/// a 4K/5K screen, where 340 points is a narrow strip. Rather than only growing
/// the window — which would show more rows at the same tiny text size — each
/// preset scales the *whole* design system, so 11.5 pt row text becomes 14.4 pt
/// at Large and the density stays exactly as designed.
enum PanelSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Multiplier applied to every dimension and font size.
    ///
    /// 1.25 and 1.5 rather than 1.5 and 2.0: the jump to double is far past what
    /// a utility panel wants, and 1.25 is the step where a 27-inch display stops
    /// feeling like it is rendering a phone UI.
    var scale: CGFloat {
        switch self {
        case .small: 1.0
        case .medium: 1.25
        case .large: 1.5
        }
    }

    func label(_ strings: Strings) -> String {
        switch self {
        case .small: strings.panelSizeSmall
        case .medium: strings.panelSizeMedium
        case .large: strings.panelSizeLarge
        }
    }

    /// Shown next to each option so the choice is concrete rather than abstract.
    /// Not localised: it is two numbers.
    var dimensionLabel: String {
        let metrics = Metrics(size: self)
        return "\(Int(metrics.panelWidth))×\(Int(metrics.panelHeight))"
    }
}

/// Every dimension and font in the panel, scaled.
///
/// The base values come from `docs/ui-design.md` and are unchanged — this type
/// only multiplies. Views read it from the environment instead of touching
/// ``Token`` directly, so a size change is one value and not a sweep through
/// every file.
///
/// Fonts are scaled by *point size*, never by `scaleEffect`. Scaling a rendered
/// layer resamples the glyphs and produces the soft, slightly wrong text that
/// makes a scaled app look cheap; asking for a larger font renders it sharply.
struct Metrics: Equatable, Sendable {
    let size: PanelSize
    let scale: CGFloat

    init(size: PanelSize) {
        self.size = size
        self.scale = size.scale
    }

    // MARK: Panel

    var panelWidth: CGFloat { round(Token.Panel.width * scale) }
    var panelHeight: CGFloat { round(Token.Panel.height * scale) }
    var dragRegionHeight: CGFloat { round(Token.Panel.dragRegionHeight * scale) }

    // MARK: Space

    var edge: CGFloat { round(Token.Space.edge * scale) }
    var row: CGFloat { round(Token.Space.row * scale) }
    var rowGap: CGFloat { max(1, round(Token.Space.rowGap * scale)) }
    var rowVertical: CGFloat { round(Token.Space.rowVertical * scale) }
    var actionCluster: CGFloat { round(Token.Space.actionCluster * scale) }

    /// Row action buttons, and the chip that carries the type glyph.
    var actionButton: CGFloat { round(20 * scale) }
    var chip: CGFloat { round(20 * scale) }
    var chipGlyph: CGFloat { 11 * scale }
    var actionGlyph: CGFloat { 10 * scale }

    // MARK: Radius

    var radiusXS: CGFloat { round(Token.Radius.xs * scale) }
    var radiusSM: CGFloat { round(Token.Radius.sm * scale) }
    var radiusMD: CGFloat { round(Token.Radius.md * scale) }
    var radiusXL: CGFloat { round(Token.Radius.xl * scale) }

    /// Hairlines stay hairlines. A 0.5 pt rule scaled to 0.75 stops landing on a
    /// pixel boundary and renders as a fuzzy grey band instead of a crisp line.
    var hairline: CGFloat { 0.5 }

    // MARK: Type

    func font(_ points: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: points * scale, weight: weight)
    }

    var rowFont: Font { font(11.5) }
    var rowMonoFont: Font { .system(size: 11.5 * scale, weight: .regular, design: .monospaced) }
    var rowTitleFont: Font { font(11.5, weight: .medium) }
    var microFont: Font { font(9) }
    var metaFont: Font { font(9.5).monospacedDigit() }
    var groupHeadingFont: Font { font(9, weight: .semibold) }
    var brandFont: Font { font(10.5, weight: .semibold) }
    var badgeFont: Font { font(8.5, weight: .medium).monospacedDigit() }
    var keycapFont: Font { .system(size: 9 * scale, weight: .medium, design: .monospaced) }
    var bodyFont: Font { font(12) }
    var expandedFont: Font { font(11.5) }

    var keycapMinSize: CGFloat { round(14 * scale) }
    var pinGlyph: CGFloat { 8 * scale }
    /// Height cap for an expanded row's content.
    var expansionMaxHeight: CGFloat { round(180 * scale) }
    var footerHeight: CGFloat { round(28 * scale) }
}

// MARK: - Environment

private struct MetricsKey: EnvironmentKey {
    static let defaultValue = Metrics(size: .small)
}

/// The catalog every view draws its words from.
///
/// Injected alongside ``Metrics`` rather than read from `Settings` in each
/// view: a row should no more know where the language preference lives than it
/// knows where the panel width does. The default is English, which only the
/// previews and a view rendered outside the panel would ever see.
private struct StringsKey: EnvironmentKey {
    static let defaultValue = Strings(.english)
}

extension EnvironmentValues {
    var metrics: Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }

    var strings: Strings {
        get { self[StringsKey.self] }
        set { self[StringsKey.self] = newValue }
    }
}

/// Puts the settings-derived environment into a view tree that does not inherit
/// the panel's.
///
/// The settings sheet and the prompt editor are separate `NSHostingView`s in
/// their own windows, so `.environment` on the panel does not reach them. This
/// wrapper reads `settings.strings` and `settings.theme` inside its own `body`,
/// which is what makes them *reactive* rather than values captured when the
/// sheet was built.
///
/// `Metrics` is deliberately absent: the sheets are fixed-size and do not scale
/// with the panel. The light/dark appearance is absent too — that one rides on
/// `NSApp.appearance`, so every window gets it without being handed anything.
struct Localized<Content: View>: View {
    let settings: Settings
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.strings, settings.strings)
            .environment(\.theme, settings.theme)
    }
}

// MARK: - Pinnable rows

/// Rows that can sit in the pinned group. Lets the list find the boundary
/// between the two groups without duplicating the test per tab.
protocol PinnableRow {
    var isPinned: Bool { get }
}

extension ClipItem: PinnableRow {}
extension PromptItem: PinnableRow {}
