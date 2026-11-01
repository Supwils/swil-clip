import Foundation

/// One user-managed tab: a named, ordered home for ``LibraryEntry``s.
///
/// ## Why there is no `isBuiltIn`
///
/// Clipboard is the only special tab, and its specialness is real — it lives in
/// another table, the pasteboard poller writes it, it evicts, and it is
/// read-only. Everything else is one of these, and every one of these obeys
/// identical rules.
///
/// The migration seeds two of them (Prompts, Personal) and then forgets that it
/// did. A flag marking them would be a mechanism built for two rows, and it
/// would create a state the user cannot see — *have I renamed this?* — which is
/// the shape of every bug this project has shipped. It would also contradict
/// the change it belongs to: code carrying `isBuiltIn` on Prompts is code still
/// asserting Prompts is special.
///
/// ## Why the name is not a `Strings` property
///
/// It is user data, not interface copy. ``Strings`` is compile-time exhaustive
/// precisely because interface copy must exist in both languages; a name the
/// user typed exists in exactly one, theirs. The seeded names are written once,
/// in whatever language the app was in when the migration ran, and they are
/// ordinary user data from that moment on — they do not follow a later language
/// switch, and renaming is two seconds in Settings.
public struct LibraryCollection: Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var symbol: CollectionSymbol
    /// Dense `0..<n`, rewritten wholesale on reorder. With a hard cap of five
    /// collections there is no case for fractional indexing.
    public var position: Int
    public let createdAt: Date
    /// This row's sealed name could not be opened.
    ///
    /// Surfaced rather than swallowed, for the same reason as
    /// ``ClipItem/isUnreadable``: a blank tab is indistinguishable from one the
    /// app lost, and "the app silently lost my content" is the failure this
    /// project treats as worse than a crash.
    public let isUnreadable: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        symbol: CollectionSymbol = .textQuote,
        position: Int,
        createdAt: Date = Date(),
        isUnreadable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.position = position
        self.createdAt = createdAt
        self.isUnreadable = isUnreadable
    }

    /// The ids the migration seeds.
    ///
    /// Constants rather than literals scattered through the store, because
    /// `prompt.collection_id`'s column default is one of them and the two must
    /// not drift.
    public enum Seed {
        public static let prompts = "prompts"
        public static let personal = "personal"
    }

    /// Hard cap on collections, from the physical width of the Small panel.
    ///
    /// 340 pt fits about six stops once the top bar's `⇥`, `＋` and `⚙` are
    /// accounted for, and `TabBar` degrades to icons before that. Not a taste
    /// judgement — change it only alongside a measurement.
    public static let maximumCount = 5
}

/// The glyphs a collection may wear.
///
/// A closed set rather than a bare `String`, so an unknown value from a
/// corrupted row degrades to ``textQuote`` instead of drawing nothing.
///
/// Storing an SF Symbol name in this AppKit-free module is the same trade
/// ``ShortcutEntry/symbol`` already makes, with the same justification: it is an
/// identifier for something printed, chosen once, next to the thing it belongs
/// to. Splitting it into a parallel table in a view is how the two drift apart.
public enum CollectionSymbol: String, CaseIterable, Sendable, Identifiable {
    case textQuote = "text.quote"
    case person = "person"
    case briefcase = "briefcase"
    case link = "link"
    case terminal = "terminal"
    case curlybraces = "curlybraces"
    case envelope = "envelope"
    case creditcard = "creditcard"
    case key = "key"
    case star = "star"
    case flag = "flag"
    case tag = "tag"

    public var id: String { rawValue }

    public static func fallback(_ raw: String) -> CollectionSymbol {
        CollectionSymbol(rawValue: raw) ?? .textQuote
    }
}
