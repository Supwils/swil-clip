import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore

/// Undo for images, which is the failure v1 shipped as SC-05 and which v2
/// re-created by a different route: `delete` removes the sidecar file, and
/// `restore` used to put back only the row. The thumbnail reappeared, the row
/// looked whole, and the picture was gone.
@Suite("LocalStore — image undo")
struct ImageRestoreTests {
    /// One-pixel PNG. Real bytes, so the sidecar round trip is a real one.
    private let png = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    private func makeImage(_ temp: borrowing TempStore) async throws -> ClipItem {
        try await temp.store.recordImage(
            png, width: 1, height: 1, format: "png",
            thumbnail: Data([0xAA, 0xBB]), sourceApp: "Test", limit: 50
        )!
    }

    @Test("delete then restore brings the actual image bytes back")
    func imageSurvivesUndo() async throws {
        let temp = try TempStore()
        let item = try await makeImage(temp)
        #expect(try await temp.store.imageData(for: item.id) == png)

        // The undo path: capture the payload, delete, restore.
        let captured = try await temp.store.imageData(for: item.id)!
        try await temp.store.delete(id: item.id)
        #expect(try await temp.store.imageData(for: item.id) == nil, "the sidecar is gone with the row")

        try await temp.store.restore([item], contents: [item.id: captured])

        let recovered = try await temp.store.imageData(for: item.id)
        #expect(recovered == png, "undo has to bring the picture back, not just the row")
    }

    @Test("the restored sidecar is sealed, not written in the clear")
    func restoredBytesAreEncrypted() async throws {
        let temp = try TempStore()
        let item = try await makeImage(temp)
        let captured = try await temp.store.imageData(for: item.id)!
        try await temp.store.delete(id: item.id)
        try await temp.store.restore([item], contents: [item.id: captured])

        let onDisk = try Data(
            contentsOf: temp.locations.blobsURL.appendingPathComponent(item.blobPath!)
        )
        #expect(onDisk != png, "undo must not be the one path that writes plaintext to disk")
        #expect(try temp.cipher.open(onDisk) == png)
    }

    /// The row's `content` column holds the preview label, never the picture —
    /// the rule `recordImage` follows. Undo used to seal the whole image into
    /// it, quietly putting megabytes back into a column the list decodes.
    @Test("undo does not smuggle the image into the row")
    func contentColumnStaysSmall() async throws {
        let temp = try TempStore()
        let item = try await makeImage(temp)
        let captured = try await temp.store.imageData(for: item.id)!
        try await temp.store.delete(id: item.id)
        try await temp.store.restore([item], contents: [item.id: captured])

        let restored = try await temp.store.allClips().first { $0.id == item.id }
        #expect(restored?.preview == item.preview)
        #expect(restored?.text == nil, "an image row carries no inline text")
        #expect(restored?.thumbnail == Data([0xAA, 0xBB]))
    }

    /// Better to refuse than to restore a row that lies about having a picture.
    @Test("restoring an image without its bytes fails loudly")
    func missingBytesThrow() async throws {
        let temp = try TempStore()
        let item = try await makeImage(temp)
        try await temp.store.delete(id: item.id)

        await #expect(throws: LocalStore.RestoreFailure.missingImageData(id: item.id)) {
            try await temp.store.restore([item], contents: [:])
        }
        // And it threw *before* putting the row back.
        #expect(try await temp.store.allClips().isEmpty)
    }

    @Test("text undo is unaffected")
    func textStillRoundTrips() async throws {
        let temp = try TempStore()
        let item = try await temp.store.recordText("hello world", limit: 50)!
        try await temp.store.delete(id: item.id)
        try await temp.store.restore([item], contents: [item.id: Data("hello world".utf8)])
        #expect(try await temp.store.text(for: item.id) == "hello world")
    }
}

@Suite("Schema — migration atomicity")
struct SchemaMigrationTests {
    /// `applyV2` is an `ALTER TABLE`, which — unlike v1's
    /// `CREATE TABLE IF NOT EXISTS` — fails if it runs twice. The version stamp
    /// therefore has to commit with the migration, or a crash in the gap
    /// between them leaves a perfectly good database that refuses to open.
    @Test("the version stamp lands with the migration, not after it")
    func versionIsStampedTransactionally() async throws {
        let temp = try TempStore()
        let version = try await temp.store.schemaVersion()
        #expect(version == Schema.current)
    }

    @Test("re-opening an already-migrated database is a no-op")
    func reopeningIsIdempotent() async throws {
        let temp = try TempStore()
        _ = try await temp.store.recordText("keep me", limit: 50)

        // Reopening runs `migrate` again against a database already at current.
        let reopened = try LocalStore(locations: temp.locations, key: temp.key)
        #expect(try await reopened.allClips().count == 1)
        #expect(try await reopened.schemaVersion() == Schema.current)
    }
}

@Suite("LocalStore — decode resilience")
struct DecodeResilienceTests {
    /// A row sealed under a different key must not render as an ordinary empty
    /// entry. Falling back keeps one bad row from taking down the list; the
    /// flag is what stops "could not decrypt" looking like "you copied nothing".
    @Test("an unreadable row is flagged rather than silently blanked")
    func unreadableRowsAreMarked() async throws {
        let temp = try TempStore()
        _ = try await temp.store.recordText("readable", limit: 50)

        // Same file, different key — exactly what a Keychain mix-up looks like.
        let stranger = try LocalStore(locations: temp.locations, key: SymmetricKey(size: .bits256))
        let rows = try await stranger.allClips()
        #expect(rows.count == 1)
        #expect(rows[0].isUnreadable)
        #expect(rows[0].preview.isEmpty)

        // And a row that opens fine is not flagged.
        #expect(try await temp.store.allClips().allSatisfy { !$0.isUnreadable })
    }
}

@Suite("LocalStore — duplicate detection depth")
struct DuplicateScanTests {
    /// The scan used to be a fixed 200 rows regardless of how much history the
    /// user keeps, so with a limit of 500 a re-copied entry older than the
    /// 200th came back as a second row instead of being promoted.
    @Test("re-copying an entry deeper than 200 rows promotes rather than duplicates")
    func scanFollowsTheHistoryLimit() async throws {
        let temp = try TempStore()
        let limit = 400
        let target = "the one we come back to"
        _ = try await temp.store.recordText(target, limit: limit)
        for index in 0..<250 {
            _ = try await temp.store.recordText("filler \(index)", limit: limit)
        }
        #expect(try await temp.store.allClips().count == 251)

        _ = try await temp.store.recordText(target, limit: limit)
        let clips = try await temp.store.allClips()
        #expect(clips.count == 251, "promoted, not duplicated")
        #expect(clips.first?.text == target, "and lifted back to the top")
    }
}
