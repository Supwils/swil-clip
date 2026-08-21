import Foundation

/// One-shot import of the v1 (Tauri) history into the v2 database.
///
/// ## Why this file is written defensively
///
/// This code runs exactly once per machine, against the only copy of data the
/// author has been accumulating since March. There is no second attempt to get
/// it right, and a mistake here is not a crash — it is an empty panel and a
/// `migrated_at` marker that stops anyone from noticing. So:
///
/// - the v1 file is **read only**. It is never written, moved or deleted, and it
///   stays on disk afterwards as the fallback copy;
/// - a decrypt or parse failure **aborts** the import and leaves the marker
///   unset, so the next launch tries again. Importing "as many as parsed" would
///   record success over a partial result;
/// - the whole insert runs in one transaction.
///
/// ## Format, verified against the live file rather than assumed
///
/// `~/Library/Application Support/com.supwilsoft.swilclip/clipboard_history.json`
/// is a `tauri-plugin-store` document with two keys: `settings` and
/// `history_enc`. The latter is base64 of `nonce‖ciphertext‖tag`, which is
/// byte-identical to CryptoKit's `combined` layout — so ``FieldCipher`` opens a
/// v1 blob directly, with no re-framing. `history` (plaintext) may appear
/// instead on databases that predate encryption.
public struct LegacyImporter: Sendable {
    /// Meta key recording that the import already ran.
    public static let markerKey = "legacy_import_completed_at"

    public enum Failure: Error, CustomStringConvertible {
        case unreadableFile(underlying: String)
        case malformedDocument
        case undecryptable(underlying: String)
        case malformedHistory(underlying: String)

        public var description: String {
            switch self {
            case .unreadableFile(let why): "cannot read the v1 history file: \(why)"
            case .malformedDocument: "the v1 history file is not a store document"
            case .undecryptable(let why): "cannot decrypt the v1 history: \(why)"
            case .malformedHistory(let why): "cannot parse the v1 history: \(why)"
            }
        }
    }

    public struct Summary: Equatable, Sendable {
        public var imported: Int
        public var skippedImages: Int
        public var legacySettings: LegacySettings?

        public init(imported: Int = 0, skippedImages: Int = 0, legacySettings: LegacySettings? = nil) {
            self.imported = imported
            self.skippedImages = skippedImages
            self.legacySettings = legacySettings
        }
    }

    /// v1's user preferences, carried across so the hotkey the author's fingers
    /// already know keeps working after the switch.
    public struct LegacySettings: Equatable, Sendable, Decodable {
        public var globalShortcut: String?
        public var maxHistory: Int?
        public var autoPaste: Bool?
    }

    // MARK: - Decoding

    /// One v1 record. Field names are serde `camelCase`, matching
    /// `tauri/src-tauri/src/clipboard/types.rs`.
    public struct LegacyClip: Decodable, Sendable {
        public let id: String
        public let clipType: String
        public let content: String
        public let preview: String
        /// Milliseconds since the epoch.
        public let timestamp: Int64
        public let pinned: Bool?
        public let appName: String?
        public let imageWidth: Int?
        public let imageHeight: Int?
        public let imageFormat: String?
    }

    private struct StoreDocument: Decodable {
        let history_enc: String?
        let history: [LegacyClip]?
        let settings: LegacySettings?
    }

    public init() {}

    /// Decrypt and decode a v1 store document. Pure — no filesystem, no store —
    /// so the format contract is testable without a Keychain or an install.
    public func decode(
        document: Data,
        cipher: FieldCipher
    ) throws -> (clips: [LegacyClip], settings: LegacySettings?) {
        let parsed: StoreDocument
        do {
            parsed = try JSONDecoder().decode(StoreDocument.self, from: document)
        } catch {
            throw Failure.malformedDocument
        }

        if let encoded = parsed.history_enc {
            guard let blob = Data(base64Encoded: encoded) else {
                throw Failure.undecryptable(underlying: "history_enc is not valid base64")
            }
            let plaintext: Data
            do {
                plaintext = try cipher.open(blob)
            } catch {
                throw Failure.undecryptable(underlying: String(describing: error))
            }
            do {
                return (try JSONDecoder().decode([LegacyClip].self, from: plaintext), parsed.settings)
            } catch {
                throw Failure.malformedHistory(underlying: String(describing: error))
            }
        }

        // Pre-encryption builds stored the array in the clear.
        if let plain = parsed.history { return (plain, parsed.settings) }

        // A document with neither key is an empty history, not a failure.
        return ([], parsed.settings)
    }

    // MARK: - Import

    /// Run the import if it has not run before. Returns `nil` when there is
    /// nothing to do — no v1 file, or the marker is already set.
    @discardableResult
    public func importIfNeeded(
        into store: LocalStore,
        from url: URL?,
        cipher: FieldCipher,
        limit: Int
    ) async throws -> Summary? {
        if try await store.metaValue(Self.markerKey) != nil { return nil }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }

        let document: Data
        do {
            document = try Data(contentsOf: url)
        } catch {
            throw Failure.unreadableFile(underlying: error.localizedDescription)
        }

        let decoded = try decode(document: document, cipher: cipher)
        let summary = try await store.importLegacy(decoded.clips, limit: limit)

        // Only now — after every row landed — is the import recorded as done.
        try await store.setMetaValue(
            ISO8601DateFormatter().string(from: Date()), for: Self.markerKey
        )
        return Summary(
            imported: summary.imported,
            skippedImages: summary.skippedImages,
            legacySettings: decoded.settings
        )
    }
}

extension LocalStore {
    /// Insert decoded v1 rows, preserving ids, timestamps and pin state.
    ///
    /// Ids are preserved deliberately: if the import ever has to be re-run
    /// against a partially populated database, `INSERT OR REPLACE` converges
    /// instead of duplicating.
    ///
    /// Public so `scripts/recover-from-v1.swift` can reuse it: the v1 file is
    /// never written or deleted, which makes it a permanent fallback for any row
    /// that later goes missing from v2. A recovered row goes in through exactly
    /// this path, so it is indistinguishable from a migrated one.
    public func importLegacy(
        _ clips: [LegacyImporter.LegacyClip],
        limit: Int
    ) throws -> (imported: Int, skippedImages: Int) {
        var imported = 0
        var skippedImages = 0

        try database.transaction {
            for legacy in clips {
                let createdAt = Date(timeIntervalSince1970: Double(legacy.timestamp) / 1000)
                let isPinned = legacy.pinned ?? false

                if legacy.clipType == ClipKind.image.rawValue {
                    // v1 held image bytes as base64 inside the blob. Decode once
                    // here and write a sealed sidecar, so the new store never
                    // carries a base64 payload in a row it renders from.
                    guard let bytes = Data(base64Encoded: legacy.content), !bytes.isEmpty else {
                        skippedImages += 1
                        continue
                    }
                    let fileName = "\(legacy.id).bin"
                    try cipher.seal(bytes).write(
                        to: locations.blobsURL.appendingPathComponent(fileName), options: .atomic
                    )
                    let item = ClipItem(
                        id: legacy.id,
                        kind: .image,
                        preview: legacy.preview.isEmpty
                            ? (legacy.imageFormat?.uppercased() ?? "IMAGE")
                            : legacy.preview,
                        blobPath: fileName,
                        pixelWidth: legacy.imageWidth,
                        pixelHeight: legacy.imageHeight,
                        imageFormat: legacy.imageFormat,
                        sourceApp: legacy.appName,
                        isPinned: isPinned,
                        createdAt: createdAt
                    )
                    try insertRaw(item, content: Data(item.preview.utf8))
                } else {
                    let item = ClipItem(
                        id: legacy.id,
                        kind: .text,
                        preview: legacy.preview.isEmpty
                            ? PreviewText.derive(from: legacy.content)
                            : legacy.preview,
                        text: legacy.content,
                        sourceApp: legacy.appName,
                        isPinned: isPinned,
                        createdAt: createdAt
                    )
                    try insertRaw(item, content: Data(legacy.content.utf8))
                }
                imported += 1
            }
        }

        // Trim only after everything landed, so eviction sees true recency
        // ordering rather than insertion order.
        try enforceLimit(limit)
        return (imported, skippedImages)
    }
}
