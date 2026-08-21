import Foundation

/// Light, dark, or whatever the Mac is set to.
///
/// A floating panel sits on top of whatever app the user is in, so following
/// the system is the least surprising default — the same reason ``AppLanguage``
/// defaults to `.system`. The override exists because this panel is *not* an
/// ordinary window: someone who keeps macOS in Light may still want a dark
/// overlay, since a dark panel reads as "this is on top of your work" rather
/// than "this is part of it".
public enum Appearance: String, CaseIterable, Sendable, Identifiable, Codable {
    case system
    case light
    case dark

    public var id: String { rawValue }
}

/// How much the panel's own tint covers what is behind the glass.
///
/// ## Why this is a tint and not a blur radius
///
/// `NSVisualEffectView` picks a *material*, not a blur radius — AppKit exposes
/// no public knob for "blur harder", and the private one is not worth a
/// notarised app's stability. What actually decides whether a bright window
/// behind the panel bleeds through is the opacity of the panel's own colour
/// layer sitting **on top of** the glass. That is a real number, it is ours,
/// and this is it.
///
/// See `AppShell`: the tint used to sit *under* the vibrancy view, where it
/// contributed nothing at all.
public enum PanelTint: String, CaseIterable, Sendable, Identifiable, Codable {
    /// Most of the desktop shows through. Beautiful over a dark, calm backdrop;
    /// unreadable over a white document.
    case sheer
    /// The default. Frosted enough that text keeps its contrast over anything.
    case standard
    /// Nearly opaque. For bright IDEs, white web pages, and shared screens.
    case solid

    public var id: String { rawValue }

    /// Alpha of the panel's colour layer over the vibrancy view.
    public var scrimOpacity: Double {
        switch self {
        case .sheer: 0.55
        case .standard: 0.78
        case .solid: 0.94
        }
    }
}
