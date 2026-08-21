import Foundation

/// The prompt library: the curated tier that history eviction never touches.
///
/// Every stored field is sealed. A prompt body is often the most sensitive thing
/// in the app — it is what the author writes into an AI tool — and it lives here
/// far longer than any clipboard entry does.
extension LocalStore {
    private static var promptColumns: String {
        "id, title, body, is_pinned, created_at, updated_at"
    }

    // MARK: - Reading

    /// Every prompt, pinned first then most-recently-edited.
    ///
    /// Bodies are decrypted eagerly, unlike image clips. The library is curated
    /// and small — tens of entries of a few hundred characters — and search has
    /// to match the body, not just the title.
    public func allPrompts() throws -> [PromptItem] {
        try database.query(
            """
            SELECT \(Self.promptColumns) FROM prompt
            ORDER BY is_pinned DESC, updated_at DESC
            """
        ) { try decodePrompt($0) }
    }

    public func prompt(id: String) throws -> PromptItem? {
        try database.queryOne(
            "SELECT \(Self.promptColumns) FROM prompt WHERE id = ?", [.text(id)]
        ) { try decodePrompt($0) }
    }

    public func promptCount() throws -> Int {
        try database.queryOne("SELECT COUNT(*) FROM prompt") { Int($0.int(0)) } ?? 0
    }

    // MARK: - Writing

    @discardableResult
    public func createPrompt(
        title: String? = nil,
        body: String,
        now: Date = Date()
    ) throws -> PromptItem? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }

        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = PromptItem(
            title: (resolvedTitle?.isEmpty == false)
                ? resolvedTitle!
                : PromptTitle.propose(from: trimmedBody),
            body: trimmedBody,
            createdAt: now,
            updatedAt: now
        )
        try upsert(item)
        return item
    }

    public func updatePrompt(_ item: PromptItem, now: Date = Date()) throws {
        var updated = item
        updated.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.title.isEmpty { updated.title = PromptTitle.propose(from: updated.body) }
        updated.updatedAt = now
        try upsert(updated)
    }

    public func deletePrompt(id: String) throws {
        try database.execute("DELETE FROM prompt WHERE id = ?", [.text(id)])
    }

    /// Pin or unpin a prompt. Unpinning bumps it to the top of the unpinned
    /// group, for the same reason clips do — see ``LocalStore/setPinned(_:id:now:)``.
    /// Prompts sort by `updated_at`, so that is the column to move.
    public func setPromptPinned(_ pinned: Bool, id: String, now: Date = Date()) throws {
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
    public func restorePromptPinState(id: String, isPinned: Bool, orderDate: Date) throws {
        try database.execute(
            "UPDATE prompt SET is_pinned = ?, updated_at = ? WHERE id = ?",
            [.bool(isPinned), .date(orderDate), .text(id)]
        )
    }

    /// Restore deleted prompts — the undo path, mirroring clips.
    public func restorePrompts(_ items: [PromptItem]) throws {
        try database.transaction {
            for item in items { try upsert(item) }
        }
    }

    /// Promote a clipboard entry into the library — the `⇧S` action.
    ///
    /// This is the reason the two tiers share one app. Something worth keeping
    /// is already in history by the time you decide that; promoting it should
    /// not mean retyping it, and it does not mean leaving history either — the
    /// clip stays where it was.
    @discardableResult
    public func promoteToPrompt(clipID: String, now: Date = Date()) throws -> PromptItem? {
        guard let body = try text(for: clipID) else { return nil }
        return try createPrompt(body: body, now: now)
    }

    // MARK: - Internals

    private func upsert(_ item: PromptItem) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO prompt
              (id, title, body, is_pinned, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id),
                .blob(try cipher.seal(item.title)),
                .blob(try cipher.seal(item.body)),
                .bool(item.isPinned),
                .date(item.createdAt),
                .date(item.updatedAt),
            ]
        )
    }

    private func decodePrompt(_ row: Row) throws -> PromptItem {
        PromptItem(
            id: row.text(0),
            title: (try? cipher.openString(row.blob(1))) ?? "",
            body: (try? cipher.openString(row.blob(2))) ?? "",
            isPinned: row.bool(3),
            createdAt: row.date(4),
            updatedAt: row.date(5)
        )
    }
}
