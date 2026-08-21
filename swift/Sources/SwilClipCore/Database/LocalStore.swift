import CryptoKit
import Foundation

/// Persistence for both tiers: clipboard history and the prompt library.
///
/// One actor, one SQLite connection, two tables. The spec sketched separate
/// `ClipStore` and `PromptStore` types; they were merged because two actors
/// sharing one connection would break the single-owner invariant that makes the
/// connection safe, and two connections would add WAL lock contention to buy
/// nothing. Clip and prompt operations live in separate files under one actor.
///
/// ## What changed from v1, and why it matters
///
/// v1 serialised the whole history, sealed it as one blob and wrote the lot on
/// every single mutation. Measured on Apple Silicon in release: 0.7 ms for 50
/// text entries, but **167 ms** once screenshots were in play — and ~90 % of
/// that was encryption, not disk. Three separate caps existed only to keep that
/// number survivable.
///
/// Here a write touches one row. The caps are gone; `historyLimit` is now a
/// preference about how much history is useful, not a brake on a hot loop.
///
/// An `actor` because the pasteboard poller writes every 500 ms while the panel
/// reads. That is the one real concurrency hazard in the app, and giving the
/// connection a single owner removes it by construction rather than by lock
/// discipline.
public actor LocalStore {
    let database: Database
    let cipher: FieldCipher
    let locations: StorageLocations

    public init(locations: StorageLocations, key: SymmetricKey) throws {
        try locations.createDirectories()
        self.locations = locations
        self.database = try Database(path: locations.databaseURL.path)
        self.cipher = FieldCipher(key: key)
        try Schema.migrate(database)
    }

    // MARK: - Reading

    private static let selectColumns = """
        id, kind, content, preview, blob_path, width, height, image_format,
        source_app, is_pinned, created_at, thumbnail
        """

    /// Every clip, in render order: pinned first, then newest first.
    ///
    /// Image payloads are *not* read here — only the sealed preview. Loading a
    /// list of forty rows must not mean decrypting forty screenshots, which is
    /// the difference between a panel that opens instantly and one that stutters.
    public func allClips() throws -> [ClipItem] {
        try database.query(
            """
            SELECT \(Self.selectColumns) FROM clip
            ORDER BY is_pinned DESC, created_at DESC
            """
        ) { try decodeClip($0) }
    }

    /// The full text of a clip, decrypted on demand.
    public func text(for id: String) throws -> String? {
        let sealed = try database.queryOne(
            "SELECT content, kind FROM clip WHERE id = ?", [.text(id)]
        ) { (blob: $0.blob(0), kind: $0.text(1)) }
        guard let sealed, sealed.kind == ClipKind.text.rawValue else { return nil }
        return try cipher.openString(sealed.blob)
    }

    /// The decrypted bytes of an image clip, read from its sidecar file.
    public func imageData(for id: String) throws -> Data? {
        let path = try database.queryOne(
            "SELECT blob_path FROM clip WHERE id = ?", [.text(id)]
        ) { $0.optionalText(0) }
        guard let path = path ?? nil else { return nil }
        let url = locations.blobsURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try cipher.open(try Data(contentsOf: url))
    }

    /// The schema version the file itself carries. Exposed so a test can assert
    /// the migration and its stamp are one commit rather than two.
    public func schemaVersion() throws -> Int32 {
        try database.queryOne("PRAGMA user_version") { Int32($0.int(0)) } ?? 0
    }

    public func clipCount() throws -> Int {
        try database.queryOne("SELECT COUNT(*) FROM clip") { Int($0.int(0)) } ?? 0
    }

    // MARK: - Writing

    /// Record a text clip, or promote the existing identical one.
    ///
    /// Re-copying something already in history moves it to the top **in place**,
    /// keeping its id. v1 deleted and re-inserted, which minted a new id and
    /// re-encoded the payload — the cause of SC-08, and the reason a pasted
    /// image cost a full re-encrypt every time.
    @discardableResult
    public func recordText(
        _ raw: String,
        sourceApp: String? = nil,
        limit: Int,
        now: Date = Date()
    ) throws -> ClipItem? {
        let trimmed = raw
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if let existing = try findText(matching: trimmed, limit: limit) {
            try touch(id: existing, at: now)
            return try clip(id: existing)
        }

        let item = ClipItem(
            kind: .text,
            preview: PreviewText.derive(from: trimmed),
            text: trimmed,
            sourceApp: sourceApp,
            createdAt: now
        )
        try insertRaw(item, content: Data(trimmed.utf8))
        try enforceLimit(limit)
        return item
    }

    /// Record an image clip. Bytes go to a sealed sidecar file; the row keeps
    /// only the path and the dimensions read from the decoded image.
    @discardableResult
    public func recordImage(
        _ bytes: Data,
        width: Int?,
        height: Int?,
        format: String,
        thumbnail: Data? = nil,
        sourceApp: String? = nil,
        limit: Int,
        now: Date = Date()
    ) throws -> ClipItem? {
        guard !bytes.isEmpty else { return nil }

        let id = UUID().uuidString
        let fileName = "\(id).bin"
        try cipher.seal(bytes).write(
            to: locations.blobsURL.appendingPathComponent(fileName), options: .atomic
        )

        let dimensions = [width, height].compactMap { $0 }
        let preview = dimensions.count == 2
            ? "\(width!)×\(height!) \(format.uppercased())"
            : format.uppercased()

        let item = ClipItem(
            id: id,
            kind: .image,
            preview: preview,
            blobPath: fileName,
            thumbnail: thumbnail,
            pixelWidth: width,
            pixelHeight: height,
            imageFormat: format,
            sourceApp: sourceApp,
            createdAt: now
        )
        // The row's `content` column holds the sealed preview label rather than
        // the image, so no code path can accidentally load megabytes while
        // rendering a list.
        try insertRaw(item, content: Data(preview.utf8))
        try enforceLimit(limit)
        return item
    }

    public func delete(id: String) throws {
        try removeBlob(for: id)
        try database.execute("DELETE FROM clip WHERE id = ?", [.text(id)])
    }

    /// Put a clip's pin state and ordering position back exactly as they were.
    ///
    /// Both, not just the flag: unpinning rewrites `created_at` to lift the row
    /// to the top of its group, so an undo that restored only `is_pinned` would
    /// leave the entry pinned but sorted as if it had just been copied. Undo has
    /// to be a real inverse or it is a second mutation wearing undo's name.
    public func restorePinState(id: String, isPinned: Bool, orderDate: Date) throws {
        try database.execute(
            "UPDATE clip SET is_pinned = ?, created_at = ? WHERE id = ?",
            [.bool(isPinned), .date(orderDate), .text(id)]
        )
    }

    /// Restore previously deleted clips — the undo path.
    ///
    /// ## Images need their sidecar written back, not just their row
    ///
    /// This used to re-insert the row and stop there. `delete` removes the
    /// sidecar file first, so the restored row came back with a `blob_path`
    /// pointing at a file that no longer existed: the thumbnail reappeared (it
    /// is a column), the row looked fine, and expanding or pasting it produced
    /// nothing. That is SC-05's symptom exactly — undo reporting success while
    /// the image is gone — reached by a different mechanism than v1's.
    ///
    /// The bytes handed in here are plaintext, the same shape ``imageData``
    /// returns, so they are sealed on the way back to disk. The `content`
    /// column gets the preview label rather than the image, matching what
    /// ``recordImage`` writes — otherwise undo would quietly move megabytes
    /// into the row that the list has to decode.
    ///
    /// Sidecars are written *before* the transaction: if the bytes are missing
    /// this throws, and it throws while the row is still absent rather than
    /// after restoring one that lies about having a picture.
    public func restore(_ items: [ClipItem], contents: [String: Data]) throws {
        for item in items where item.kind == .image {
            guard let path = item.blobPath else { continue }
            guard let bytes = contents[item.id] else {
                throw RestoreFailure.missingImageData(id: item.id)
            }
            try cipher.seal(bytes).write(
                to: locations.blobsURL.appendingPathComponent(path), options: .atomic
            )
        }
        try database.transaction {
            for item in items {
                let content = item.kind == .image
                    ? Data(item.preview.utf8)
                    : (contents[item.id] ?? Data(item.preview.utf8))
                try insertRaw(item, content: content)
            }
        }
    }

    /// Undo refusing to half-succeed.
    public enum RestoreFailure: Error, Equatable, CustomStringConvertible {
        /// An image row was captured for undo without its bytes. Restoring it
        /// would produce a row whose picture cannot be opened.
        case missingImageData(id: String)

        public var description: String {
            switch self {
            case .missingImageData: "the image bytes for this entry are no longer available"
            }
        }
    }

    /// Pin or unpin a clip.
    ///
    /// **Unpinning also moves the entry to the top of the unpinned group.**
    ///
    /// Without that, unpinning drops the row back to wherever its age puts it —
    /// often hundreds of entries down — and the selection follows it off the
    /// screen. You unpinned something because you were looking at it, so it
    /// should still be under your eye afterwards.
    ///
    /// Rewriting `created_at` is consistent with what the column already means
    /// here: re-copying an existing clip promotes it to the top the same way
    /// (see ``recordText``). The timestamp tracks last activity, not first
    /// capture, and unpinning is activity.
    ///
    /// Pinning does **not** touch it: a pinned row keeps its real age, because
    /// the pinned group is small enough to scan and age is what orders it.
    public func setPinned(_ pinned: Bool, id: String, now: Date = Date()) throws {
        if pinned {
            try database.execute(
                "UPDATE clip SET is_pinned = 1 WHERE id = ?", [.text(id)]
            )
        } else {
            try database.execute(
                "UPDATE clip SET is_pinned = 0, created_at = ? WHERE id = ?",
                [.date(now), .text(id)]
            )
        }
    }

    /// Delete every unpinned clip, returning what was removed so it can be undone.
    public func clearUnpinned() throws -> [ClipItem] {
        let doomed = try database.query(
            "SELECT \(Self.selectColumns) FROM clip WHERE is_pinned = 0"
        ) { try decodeClip($0) }
        for item in doomed { try removeBlob(for: item.id) }
        try database.execute("DELETE FROM clip WHERE is_pinned = 0")
        return doomed
    }

    // MARK: - Internals

    private func clip(id: String) throws -> ClipItem? {
        try database.queryOne(
            "SELECT \(Self.selectColumns) FROM clip WHERE id = ?", [.text(id)]
        ) { try decodeClip($0) }
    }

    func insertRaw(_ item: ClipItem, content: Data) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO clip
              (id, kind, content, preview, blob_path, width, height, image_format,
               source_app, is_pinned, created_at, thumbnail)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id),
                .text(item.kind.rawValue),
                .blob(try cipher.seal(content)),
                .blob(try cipher.seal(item.preview)),
                .optionalText(item.blobPath),
                .optionalInt(item.pixelWidth),
                .optionalInt(item.pixelHeight),
                .optionalText(item.imageFormat),
                .optionalText(item.sourceApp),
                .bool(item.isPinned),
                .date(item.createdAt),
                // Sealed like everything else: a thumbnail of a screenshot is
                // still a picture of whatever was on screen.
                //
                // A seal failure lands on `.null`, not on an empty blob: the
                // backfill looks for `thumbnail IS NULL`, so a zero-length blob
                // would read as "already has one" and the row would never get a
                // preview again.
                try item.thumbnail.map { .blob(try cipher.seal($0)) } ?? .null,
            ]
        )
    }

    /// Attach (or replace) an image clip's thumbnail.
    ///
    /// Used by the one-time backfill for rows captured before thumbnails
    /// existed. Generating one needs an image decoder, which lives in the app
    /// target — this module stays free of AppKit.
    public func setThumbnail(_ thumbnail: Data, id: String) throws {
        try database.execute(
            "UPDATE clip SET thumbnail = ? WHERE id = ?",
            [.blob(try cipher.seal(thumbnail)), .text(id)]
        )
    }

    /// Image rows that have no thumbnail yet, newest first.
    ///
    /// Bounded by `limit` so a backfill over a large history cannot stall
    /// startup; the remainder is picked up on the next launch.
    public func imageRowsMissingThumbnail(limit: Int = 40) throws -> [(id: String, blobPath: String)] {
        try database.query(
            """
            SELECT id, blob_path FROM clip
            WHERE kind = 'image' AND thumbnail IS NULL AND blob_path IS NOT NULL
            ORDER BY created_at DESC LIMIT ?
            """,
            [.integer(Int64(limit))]
        ) { (id: $0.text(0), blobPath: $0.text(1)) }
    }

    /// The decrypted bytes behind a known sidecar path, for the backfill.
    public func imageData(atBlobPath path: String) throws -> Data? {
        let url = locations.blobsURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try cipher.open(try Data(contentsOf: url))
    }

    /// Find a text clip with identical content.
    ///
    /// Content is encrypted, so this cannot be a `WHERE content = ?` — every
    /// ciphertext is unique by design. Text rows are small and few, so decrypting
    /// them is cheaper than the alternative of storing a searchable hash, which
    /// would leak equality across the whole history to anyone reading the file.
    /// - Parameter limit: how far back to look, in rows.
    ///
    ///   Passed rather than hard-coded: this used to scan a fixed 200, so with
    ///   a history of 500 or 1000 a re-copied entry older than the 200th would
    ///   be inserted as a duplicate instead of promoted. Using the history limit
    ///   makes the scan exactly as deep as the history is — and at the default
    ///   of 50 it is four times cheaper than the constant it replaces.
    private func findText(matching raw: String, limit: Int) throws -> String? {
        let candidates = try database.query(
            """
            SELECT id, content FROM clip
            WHERE kind = 'text' ORDER BY created_at DESC LIMIT ?
            """,
            [.integer(Int64(max(limit, 1)))]
        ) { (id: $0.text(0), content: $0.blob(1)) }

        for candidate in candidates
        where (try? cipher.openString(candidate.content)) == raw {
            return candidate.id
        }
        return nil
    }

    private func touch(id: String, at now: Date) throws {
        try database.execute(
            "UPDATE clip SET created_at = ? WHERE id = ?", [.date(now), .text(id)]
        )
    }

    private func removeBlob(for id: String) throws {
        let path = try database.queryOne(
            "SELECT blob_path FROM clip WHERE id = ?", [.text(id)]
        ) { $0.optionalText(0) }
        guard let path = path ?? nil else { return }
        try? FileManager.default.removeItem(at: locations.blobsURL.appendingPathComponent(path))
    }

    /// Trim unpinned history to `limit`.
    ///
    /// Pinned rows never count toward it and are never evicted — that is what
    /// makes pinning meaningful rather than decorative.
    func enforceLimit(_ limit: Int) throws {
        guard limit > 0 else { return }
        let doomed = try database.query(
            """
            SELECT id FROM clip WHERE is_pinned = 0
            ORDER BY created_at DESC LIMIT -1 OFFSET ?
            """,
            [.integer(Int64(limit))]
        ) { $0.text(0) }
        guard !doomed.isEmpty else { return }
        for id in doomed { try delete(id: id) }
    }

    private func decodeClip(_ row: Row) throws -> ClipItem {
        let kind = ClipKind(rawValue: row.text(1)) ?? .text
        // One unreadable row must not take down the whole list, so this falls
        // back rather than throwing — but the fact is carried out with it, so
        // the row can say "could not decrypt" instead of rendering as blank.
        let opened = try? cipher.openString(row.blob(3))
        let preview = opened ?? ""
        // Text is small and search needs it, so it rides along. Image payloads
        // never do — see the type documentation on ClipItem.
        let text: String? = kind == .text ? try? cipher.openString(row.blob(2)) : nil

        return ClipItem(
            id: row.text(0),
            kind: kind,
            preview: preview,
            text: text,
            blobPath: row.optionalText(4),
            thumbnail: row.isNull(11) ? nil : (try? cipher.open(row.blob(11))),
            pixelWidth: row.optionalInt(5),
            pixelHeight: row.optionalInt(6),
            imageFormat: row.optionalText(7),
            sourceApp: row.optionalText(8),
            isPinned: row.bool(9),
            createdAt: row.date(10),
            isUnreadable: opened == nil
        )
    }

    // MARK: - Meta

    public func metaValue(_ key: String) throws -> String? {
        try database.queryOne("SELECT value FROM meta WHERE key = ?", [.text(key)]) { $0.text(0) }
    }

    public func setMetaValue(_ value: String, for key: String) throws {
        try database.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", [.text(key), .text(value)]
        )
    }
}
