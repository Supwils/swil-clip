import Foundation

/// The language the interface is drawn in, as the user chose it.
///
/// ## Why this is not `String(localized:)` and `.lproj`
///
/// The Foundation route resolves against `Locale.preferredLanguages`, which is
/// a *system* setting. This app offers an in-app switch, and the only supported
/// way to make `String(localized:)` follow one is to load a specific `.lproj`
/// bundle by hand and look strings up in it — a well-known hack that silently
/// falls back to the key when a translation is missing.
///
/// A typed catalog instead (see ``Strings``): a missing translation is a
/// compile error rather than a key leaking onto the screen, the switch is a
/// plain value with no bundle surgery, and both languages sit on the same line
/// so a change to one is visibly a change to the other. Two languages, one
/// author, no translators — the tooling that `.strings` files buy has nobody to
/// serve here, and the correctness it costs is real.
public enum AppLanguage: String, CaseIterable, Sendable, Identifiable, Codable {
    /// Follow whatever macOS is set to. The default, and the only value that
    /// can change meaning without the user touching anything.
    case system
    case english
    case chinese

    public var id: String { rawValue }

    /// The language actually used to draw the UI.
    ///
    /// - Parameter preferredLanguages: injected so this is testable without a
    ///   process-wide locale. Defaults to the real system preference.
    public func resolved(
        preferring preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ResolvedLanguage {
        switch self {
        case .english: return .english
        case .chinese: return .chinese
        case .system:
            // Match on the language subtag alone: zh-Hans, zh-Hant, zh-Hans-CN
            // and bare zh all mean the same thing for a two-language app.
            let first = preferredLanguages.first?.lowercased() ?? "en"
            return first.hasPrefix("zh") ? .chinese : .english
        }
    }
}

/// What ``AppLanguage`` collapses to once `.system` has been resolved. Every
/// string in ``Strings`` exists in exactly these.
public enum ResolvedLanguage: String, CaseIterable, Sendable {
    case english
    case chinese
}
