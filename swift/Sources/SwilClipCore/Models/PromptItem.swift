import Foundation

/// A curated, long-lived instruction — the tier history eviction never touches.
///
/// Two fields, on purpose. The 2026-05-28 draft specified `{{variables}}` and
/// tags; neither is built. Nothing in the real corpus uses a variable, and at
/// this corpus size a tag is just one more decision to make while saving —
/// friction that decides whether a personal tool actually gets used.
public struct PromptItem: Sendable, Identifiable, Equatable {
    public let id: String
    public var title: String
    public var body: String
    public var isPinned: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Single-line form for the list row.
    public var preview: String { PreviewText.derive(from: body) }

    /// The buttons this row draws, in render order. See ``ClipItem/rowActions``.
    /// A prompt is editable where a clip is promotable.
    public var rowActions: [RowAction] { [.pin, .edit, .expand, .delete] }
}

// MARK: - Title derivation

public enum PromptTitle {
    /// Titles longer than this are truncated. Chosen so a title still fits the
    /// 340 pt panel at 11.5 pt without eliding mid-word for typical entries.
    public static let limit = 24

    /// Propose a title from a prompt body.
    ///
    /// Saving must cost one keystroke, so the editor pre-fills this and puts the
    /// cursor on it. Accepting is `⏎`; overriding is just typing.
    ///
    /// The first line is used when there is one, because that is where these
    /// instructions carry their subject. Leading list/quote/heading punctuation
    /// is stripped so a bullet does not become the title.
    public static func propose(from body: String, limit: Int = PromptTitle.limit) -> String {
        let firstLine = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""

        var candidate = firstLine.trimmingCharacters(in: .whitespaces)
        // Strip markdown-ish leaders: "# ", "- ", "* ", "> ", "1. "
        candidate = candidate.replacing(
            /^(?:#{1,6}\s+|[-*+>]\s+|\d+[.)]\s+)/,
            with: ""
        )
        if candidate.isEmpty {
            candidate = PreviewText.derive(from: body, limit: limit)
        }
        if candidate.isEmpty { return "Untitled" }

        if candidate.count > limit {
            return String(candidate.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return candidate
    }
}
