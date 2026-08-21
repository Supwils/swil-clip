import Foundation

public enum ClipKind: String, Sendable, Codable, CaseIterable {
    case text
    case image
}

/// One entry in the clipboard history, as the UI sees it.
///
/// ## Why images are not in here
///
/// v1 stored images as base64 inside the same record the list rendered from, so
/// drawing a row of forty entries meant holding forty full images in memory —
/// tens of megabytes for a 340×480 panel that shows text.
///
/// Here, image bytes live in a sealed sidecar file and are read only when the
/// row is actually pasted or expanded. Text is kept inline because it is small
/// (hundreds of bytes) and searching needs it anyway. The result is that the
/// resident set scales with how much *text* you have copied, not how many
/// screenshots.
public struct ClipItem: Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: ClipKind
    /// Single-line, truncated form used for list rendering. Always present.
    public let preview: String
    /// Full text, for text clips only. `nil` for images — see the type docs.
    public let text: String?
    /// Location of the sealed image bytes, relative to the blob directory.
    public let blobPath: String?
    /// A small encoded preview of an image clip — a few kilobytes, generated at
    /// capture. Small enough to ride along in the row and be held for the whole
    /// list, which is the entire difference between this and v1's base64.
    public let thumbnail: Data?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let imageFormat: String?
    /// Bundle name of the app that was frontmost at capture time.
    public let sourceApp: String?
    public let isPinned: Bool
    public let createdAt: Date
    /// This row's ciphertext could not be opened.
    ///
    /// Surfaced rather than swallowed. Decoding already falls back to an empty
    /// preview so one bad row cannot take down the list — but an empty row with
    /// a timestamp is indistinguishable from a clip that was always empty, and
    /// "the app silently lost my content" is the exact shape this project
    /// treats as worse than a crash. The flag lets the row say so.
    public let isUnreadable: Bool

    public init(
        id: String = UUID().uuidString,
        kind: ClipKind,
        preview: String,
        text: String? = nil,
        blobPath: String? = nil,
        thumbnail: Data? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        imageFormat: String? = nil,
        sourceApp: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        isUnreadable: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.text = text
        self.blobPath = blobPath
        self.thumbnail = thumbnail
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.imageFormat = imageFormat
        self.sourceApp = sourceApp
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.isUnreadable = isUnreadable
    }

    /// Dimensions as shown under an image preview, when both are known.
    public var pixelSizeLabel: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        let format = imageFormat?.uppercased() ?? "IMAGE"
        return "\(pixelWidth)×\(pixelHeight) \(format)"
    }

    /// The text a paste should place on the pasteboard. `nil` for images, whose
    /// bytes must be read from the sidecar file instead.
    public var pasteableText: String? { kind == .text ? text : nil }

    /// The buttons this row draws, in render order.
    ///
    /// `ClipRowView` builds its action cluster from this array and
    /// ``SelectionReducer`` is handed the same one, so "the third button" means
    /// exactly one thing to both. An image has no text to save as a prompt,
    /// which is why the count differs — and why focus travels by ``RowAction``
    /// rather than by index.
    public var rowActions: [RowAction] {
        kind == .text ? [.pin, .promote, .expand, .delete] : [.pin, .expand, .delete]
    }
}

// MARK: - Preview derivation

public enum PreviewText {
    /// Characters retained for the list preview. Long enough that a truncated
    /// row stays identifiable, short enough that previews never dominate memory.
    public static let limit = 200

    /// Collapse a clip into the single line the list renders.
    ///
    /// Runs of whitespace — including the newlines that make multi-line code and
    /// long prompts unreadable in a one-line row — become single spaces.
    public static func derive(from raw: String, limit: Int = PreviewText.limit) -> String {
        var collapsed = ""
        collapsed.reserveCapacity(min(raw.count, limit))
        var pendingSpace = false
        var seenNonSpace = false

        for character in raw {
            if character.isWhitespace {
                if seenNonSpace { pendingSpace = true }
                continue
            }
            if pendingSpace {
                collapsed.append(" ")
                pendingSpace = false
            }
            collapsed.append(character)
            seenNonSpace = true
            if collapsed.count >= limit { break }
        }
        return collapsed
    }
}
