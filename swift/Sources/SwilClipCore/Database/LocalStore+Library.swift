import Foundation

/// The prompt library: the curated tier that history eviction never touches.
///
/// Every stored field is sealed. A prompt body is often the most sensitive thing
/// in the app — it is what the author writes into an AI tool — and it lives here
/// far longer than any clipboard entry does.
extension LocalStore {
    private static var entryColumns: String {
        "id, title, body, is_pinned, created_at, updated_at, collection_id"
    }

    // MARK: - Reading

    /// Every prompt, pinned first then most-recently-edited.
    ///
    /// Bodies are decrypted eagerly, unlike image clips. The library is curated
    /// and small — tens of entries of a few hundred characters — and search has
    /// to match the body, not just the title.
    public func allEntries() throws -> [LibraryEntry] {
        try database.query(
            """
            SELECT \(Self.entryColumns) FROM prompt
            ORDER BY is_pinned DESC, updated_at DESC
            """
        ) { try decodeEntry($0) }
    }

    /// One collection's entries, in render order.
    ///
    /// Scoped in SQL rather than filtered in Swift, so `idx_prompt_collection`
    /// earns its keep and the ordering is the one the list actually draws.
    public func entries(in collectionID: String) throws -> [LibraryEntry] {
        try database.query(
            """
            SELECT \(Self.entryColumns) FROM prompt
            WHERE collection_id = ?
            ORDER BY is_pinned DESC, updated_at DESC
            """,
            [.text(collectionID)]
        ) { try decodeEntry($0) }
    }

    public func entry(id: String) throws -> LibraryEntry? {
        try database.queryOne(
            "SELECT \(Self.entryColumns) FROM prompt WHERE id = ?", [.text(id)]
        ) { try decodeEntry($0) }
    }

    public func entryCount() throws -> Int {
        try database.queryOne("SELECT COUNT(*) FROM prompt") { Int($0.int(0)) } ?? 0
    }

    // MARK: - Writing

    @discardableResult
    public func createEntry(
        collectionID: String,
        title: String? = nil,
        body: String,
        now: Date = Date()
    ) throws -> LibraryEntry? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }

        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LibraryEntry(
            collectionID: collectionID,
            title: (resolvedTitle?.isEmpty == false)
                ? resolvedTitle!
                : PromptTitle.propose(from: trimmedBody),
            body: trimmedBody,
            createdAt: now,
            updatedAt: now
        )
        try upsertEntry(item)
        return item
    }

    public func updateEntry(_ item: LibraryEntry, now: Date = Date()) throws {
        var updated = item
        updated.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.title.isEmpty { updated.title = PromptTitle.propose(from: updated.body) }
        updated.updatedAt = now
        try upsertEntry(updated)
    }

    public func deleteEntry(id: String) throws {
        try database.execute("DELETE FROM prompt WHERE id = ?", [.text(id)])
    }

    /// Pin or unpin a prompt. Unpinning bumps it to the top of the unpinned
    /// group, for the same reason clips do — see ``LocalStore/setPinned(_:id:now:)``.
    /// Prompts sort by `updated_at`, so that is the column to move.
    public func setEntryPinned(_ pinned: Bool, id: String, now: Date = Date()) throws {
        if pinned {
            try database.execute(
                "UPDATE prompt SET is_pinned = 1 WHERE id = ?", [.text(id)]
            )
        } else {
            try database.execute(
                "UPDATE prompt SET is_pinned = 0, updated_at = ? WHERE id = ?",
                [.date(now), .text(id)]
            )
        }
    }

    /// Restore a prompt's pin state and ordering position — see
    /// ``LocalStore/restorePinState(id:isPinned:orderDate:)``.
    public func restoreEntryPinState(id: String, isPinned: Bool, orderDate: Date) throws {
        try database.execute(
            "UPDATE prompt SET is_pinned = ?, updated_at = ? WHERE id = ?",
            [.bool(isPinned), .date(orderDate), .text(id)]
        )
    }

    /// Restore deleted prompts — the undo path, mirroring clips.
    public func restoreEntries(_ items: [LibraryEntry]) throws {
        try database.transaction {
            for item in items { try upsertEntry(item) }
        }
    }

    /// Promote a clipboard entry into a collection — the `⇧S` action.
    ///
    /// This is the reason the two tiers share one app. Something worth keeping
    /// is already in history by the time you decide that; promoting it should
    /// not mean retyping it, and it does not mean leaving history either — the
    /// clip stays where it was.
    ///
    /// Takes the destination rather than assuming one. *Which* collection `⇧S`
    /// aims at is the caller's rule — the first one in tab order — and keeping
    /// that rule in the caller means the store has no second opinion to drift
    /// from the panel.
    @discardableResult
    public func promote(
        clipID: String,
        into collectionID: String,
        now: Date = Date()
    ) throws -> LibraryEntry? {
        guard let body = try text(for: clipID) else { return nil }
        return try createEntry(collectionID: collectionID, body: body, now: now)
    }

    // MARK: - Internals

    func upsertEntry(_ item: LibraryEntry) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO prompt
              (id, title, body, is_pinned, created_at, updated_at, collection_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id),
                .blob(try cipher.seal(item.title)),
                .blob(try cipher.seal(item.body)),
                .bool(item.isPinned),
                .date(item.createdAt),
                .date(item.updatedAt),
                .text(item.collectionID),
            ]
        )
    }

    private func decodeEntry(_ row: Row) throws -> LibraryEntry {
        LibraryEntry(
            id: row.text(0),
            collectionID: row.text(6),
            title: (try? cipher.openString(row.blob(1))) ?? "",
            body: (try? cipher.openString(row.blob(2))) ?? "",
            isPinned: row.bool(3),
            createdAt: row.date(4),
            updatedAt: row.date(5)
        )
    }
}

// MARK: - Collections

extension LocalStore {
    /// Every collection, in the order the tab bar draws them.
    public func allCollections() throws -> [LibraryCollection] {
        try database.query(
            "SELECT id, name, symbol, position, created_at FROM collection ORDER BY position ASC"
        ) { row in
            let opened = try? cipher.openString(row.blob(1))
            return LibraryCollection(
                id: row.text(0),
                // Empty rather than a placeholder: the store does not write
                // interface copy. The view pairs `isUnreadable` with a dash.
                name: opened ?? "",
                symbol: CollectionSymbol.fallback(row.text(2)),
                position: Int(row.int(3)),
                createdAt: row.date(4),
                isUnreadable: opened == nil
            )
        }
    }

    /// Create a collection at the end of the order.
    ///
    /// Returns `nil` at the cap rather than throwing: "you already have five
    /// tabs" is a state the `＋` greys out for, not an error anyone needs a
    /// dialog about.
    @discardableResult
    public func createCollection(
        name: String,
        symbol: CollectionSymbol,
        now: Date = Date()
    ) throws -> LibraryCollection? {
        let existing = try allCollections()
        guard existing.count < LibraryCollection.maximumCount else { return nil }

        let collection = LibraryCollection(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol,
            position: existing.count,
            createdAt: now
        )
        try insert(collection)
        return collection
    }

    public func updateCollection(_ collection: LibraryCollection) throws {
        try database.execute(
            "UPDATE collection SET name = ?, symbol = ?, position = ? WHERE id = ?",
            [
                .blob(
                    try cipher.seal(
                        collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                ),
                .text(collection.symbol.rawValue),
                .integer(Int64(collection.position)),
                .text(collection.id),
            ]
        )
    }

    /// Rewrite the whole order densely, in one transaction.
    ///
    /// Wholesale rather than by delta: five rows is nothing, and a partial
    /// rewrite is how two collections end up sharing a position and the tab bar
    /// starts flickering between two orders.
    public func reorderCollections(_ orderedIDs: [String]) throws {
        try database.transaction {
            for (position, id) in orderedIDs.enumerated() {
                try database.execute(
                    "UPDATE collection SET position = ? WHERE id = ?",
                    [.integer(Int64(position)), .text(id)]
                )
            }
        }
    }

    /// Delete a collection, either moving its members or taking them with it.
    ///
    /// One transaction, because the in-between state — a `collection_id`
    /// pointing at a row that is gone — is entries present in the file and
    /// reachable from no tab. SQLite will not catch that for us: the column
    /// carries no foreign key, because `ALTER TABLE ADD COLUMN` only accepts one
    /// when the default is NULL and this default has to be `'prompts'`. So this
    /// method *is* the integrity boundary.
    ///
    /// - Parameter destination: where the members go, or `nil` to delete them.
    public func deleteCollection(id: String, movingEntriesTo destination: String?) throws {
        try database.transaction {
            if let destination {
                try database.execute(
                    "UPDATE prompt SET collection_id = ? WHERE collection_id = ?",
                    [.text(destination), .text(id)]
                )
            } else {
                try database.execute(
                    "DELETE FROM prompt WHERE collection_id = ?", [.text(id)]
                )
            }
            try database.execute("DELETE FROM collection WHERE id = ?", [.text(id)])
        }
    }

    /// The inverse of ``deleteCollection(id:movingEntriesTo:)``.
    ///
    /// The collection goes back first, then its members, so no entry is ever
    /// momentarily homeless. `entries` is the snapshot taken *before* the
    /// deletion, which is what lets one method undo both paths: rows that were
    /// deleted are re-inserted, and rows that were moved have their
    /// `collection_id` rewritten back.
    public func restoreCollection(
        _ collection: LibraryCollection,
        entries: [LibraryEntry]
    ) throws {
        try database.transaction {
            try insert(collection)
            for entry in entries { try upsertEntry(entry) }
        }
    }

    private func insert(_ collection: LibraryCollection) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO collection (id, name, symbol, position, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                .text(collection.id),
                .blob(try cipher.seal(collection.name)),
                .text(collection.symbol.rawValue),
                .integer(Int64(collection.position)),
                .date(collection.createdAt),
            ]
        )
    }

    /// Test-only: replace a collection's sealed name with bytes this key cannot
    /// open, so the unreadable path is exercised rather than reasoned about.
    func corruptCollectionNameForTesting(id: String) throws {
        try database.execute(
            "UPDATE collection SET name = ? WHERE id = ?",
            [.blob(Data([0x00, 0x01, 0x02, 0x03])), .text(id)]
        )
    }
}
