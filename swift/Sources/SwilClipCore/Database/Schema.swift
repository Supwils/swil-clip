import Foundation

/// Versioned schema, applied forward only.
///
/// `user_version` is SQLite's own header field, so the version travels with the
/// file and cannot drift from it. Each migration is append-only: a shipped one
/// is never edited, because a database in the wild has already run it.
public enum Schema {
    public static let current: Int32 = 2

    public static func migrate(_ database: Database) throws {
        let version = try database.queryOne("PRAGMA user_version") { Int32($0.int(0)) } ?? 0
        guard version < current else { return }

        // The stamp goes *inside* the transaction with the work it describes.
        // Outside it, a crash between the commit and the stamp leaves a database
        // carrying v2's column while still claiming v0 — and the next launch
        // re-runs `applyV2`, whose `ALTER TABLE` is not idempotent the way v1's
        // `CREATE TABLE IF NOT EXISTS` is. The app would then refuse to start,
        // on a database that was in fact perfectly fine.
        //
        // `user_version` lives in the file header and is written transactionally,
        // so this is atomic with the migration rather than merely adjacent to it.
        try database.transaction {
            if version < 1 { try applyV1(database) }
            if version < 2 { try applyV2(database) }
            // PRAGMA cannot be parameterised, and `current` is a compile-time
            // constant rather than input, so interpolation is safe here.
            try database.execute("PRAGMA user_version = \(current)")
        }
    }

    /// Adds the row-level image thumbnail.
    ///
    /// A separate migration rather than an edit to `applyV1`, because databases
    /// in the wild have already run v1 — the rule at the top of this file. The
    /// column is nullable: rows captured before this migration have no
    /// thumbnail, and the app backfills them once at startup.
    private static func applyV2(_ database: Database) throws {
        try database.execute("ALTER TABLE clip ADD COLUMN thumbnail BLOB")
    }

    private static func applyV1(_ database: Database) throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS clip (
              id          TEXT PRIMARY KEY,
              kind        TEXT    NOT NULL,
              content     BLOB    NOT NULL,
              preview     BLOB    NOT NULL,
              blob_path   TEXT,
              width       INTEGER,
              height      INTEGER,
              image_format TEXT,
              source_app  TEXT,
              is_pinned   INTEGER NOT NULL DEFAULT 0,
              created_at  INTEGER NOT NULL
            )
            """
        )
        // Pinned rows sort above everything, then by recency — the exact order
        // the list renders, so reads never sort in Swift.
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_clip_order ON clip(is_pinned DESC, created_at DESC)"
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS prompt (
              id          TEXT PRIMARY KEY,
              title       BLOB    NOT NULL,
              body        BLOB    NOT NULL,
              is_pinned   INTEGER NOT NULL DEFAULT 0,
              created_at  INTEGER NOT NULL,
              updated_at  INTEGER NOT NULL
            )
            """
        )
        try database.execute(
            "CREATE INDEX IF NOT EXISTS idx_prompt_order ON prompt(is_pinned DESC, updated_at DESC)"
        )
        // One-row bookkeeping: whether the v1 JSON history has been imported.
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS meta (
              key   TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
            """
        )
    }
}

/// Where the app keeps its files.
///
/// v2 uses its own directory. The frozen v1 app stays installed during the
/// transition, and v1 dev builds already share a directory with v1 release
/// builds — a known property of this project. Letting a frozen build and a live
/// one touch the same bytes is how a "safe" archive corrupts current data.
public struct StorageLocations: Sendable {
    public let root: URL
    public var databaseURL: URL { root.appendingPathComponent("swilclip.sqlite") }
    public var blobsURL: URL { root.appendingPathComponent("blobs", isDirectory: true) }

    /// The v1 history file, written by `tauri-plugin-store` under the app's
    /// bundle identifier. Read during migration, never written or deleted.
    ///
    /// The path and both key names are verified against the live file rather
    /// than assumed: migration runs exactly once, so a wrong guess here silently
    /// discards the entire history instead of failing.
    public var legacyHistoryURL: URL? {
        guard
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            )
        else { return nil }
        return support
            .appendingPathComponent("com.supwilsoft.swilclip", isDirectory: true)
            .appendingPathComponent("clipboard_history.json")
    }

    public init(root: URL) { self.root = root }

    public static func standard(
        directoryName: String = "SwilClipSwift"
    ) throws -> StorageLocations {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return StorageLocations(root: support.appendingPathComponent(directoryName, isDirectory: true))
    }

    public func createDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    }
}
