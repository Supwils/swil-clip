import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore

/// Migration runs exactly once, against the only copy of the data that exists.
/// A bug here is not a crash — it is an empty panel plus a marker that stops
/// anyone from noticing. These tests are the reason the import is allowed to run
/// unattended.
@Suite("LegacyImporter")
struct LegacyImporterTests {

    // MARK: - Fixtures

    /// Build a v1 store document in the real on-disk shape: a
    /// `tauri-plugin-store` object whose `history_enc` is base64 of
    /// `nonce‖ciphertext‖tag`.
    private func makeDocument(
        clips: [[String: Any]],
        cipher: FieldCipher,
        settings: [String: Any]? = nil
    ) throws -> Data {
        let historyJSON = try JSONSerialization.data(withJSONObject: clips)
        let sealed = try cipher.seal(historyJSON)
        var document: [String: Any] = ["history_enc": sealed.base64EncodedString()]
        if let settings { document["settings"] = settings }
        return try JSONSerialization.data(withJSONObject: document)
    }

    private func textClip(
        id: String,
        content: String,
        timestamp: Int64 = 1_700_000_000_000,
        pinned: Bool = false,
        appName: String? = nil
    ) -> [String: Any] {
        var clip: [String: Any] = [
            "id": id,
            "clipType": "text",
            "content": content,
            "preview": content,
            "timestamp": timestamp,
            "pinned": pinned,
        ]
        if let appName { clip["appName"] = appName }
        return clip
    }

    private func imageClip(
        id: String,
        bytes: Data,
        timestamp: Int64 = 1_700_000_000_000
    ) -> [String: Any] {
        [
            "id": id,
            "clipType": "image",
            "content": bytes.base64EncodedString(),
            "preview": "",
            "timestamp": timestamp,
            "pinned": false,
            "imageWidth": 1280,
            "imageHeight": 830,
            "imageFormat": "png",
        ]
    }

    // MARK: - Format contract

    @Test("opens a v1 blob directly — the Rust and CryptoKit layouts match")
    func rustBlobLayoutIsCompatible() throws {
        // v1 (Rust `aes-gcm`) wrote nonce‖ciphertext‖tag; CryptoKit's `combined`
        // is the same bytes in the same order. If that ever stopped being true,
        // every migration would fail — so it is asserted, not assumed.
        let cipher = FieldCipher(key: SymmetricKey(size: .bits256))
        let document = try makeDocument(
            clips: [textClip(id: "a", content: "hello")], cipher: cipher
        )
        let decoded = try LegacyImporter().decode(document: document, cipher: cipher)
        #expect(decoded.clips.count == 1)
        #expect(decoded.clips[0].content == "hello")
    }

    @Test("reads a pre-encryption plaintext history")
    func readsPlaintextHistory() throws {
        // Builds older than the encryption change stored the array in the clear.
        let document = try JSONSerialization.data(withJSONObject: [
            "history": [textClip(id: "a", content: "old plaintext")]
        ])
        let decoded = try LegacyImporter().decode(
            document: document, cipher: FieldCipher(key: SymmetricKey(size: .bits256))
        )
        #expect(decoded.clips.map(\.content) == ["old plaintext"])
    }

    @Test("a document with neither key is an empty history, not a failure")
    func emptyDocumentIsNotAnError() throws {
        let document = try JSONSerialization.data(withJSONObject: ["settings": [:]])
        let decoded = try LegacyImporter().decode(
            document: document, cipher: FieldCipher(key: SymmetricKey(size: .bits256))
        )
        #expect(decoded.clips.isEmpty)
    }

    @Test("carries v1 settings across so the hotkey keeps working")
    func carriesSettings() throws {
        let cipher = FieldCipher(key: SymmetricKey(size: .bits256))
        let document = try makeDocument(
            clips: [],
            cipher: cipher,
            settings: ["globalShortcut": "cmd+shift+v", "maxHistory": 200, "autoPaste": true]
        )
        let decoded = try LegacyImporter().decode(document: document, cipher: cipher)
        #expect(decoded.settings?.globalShortcut == "cmd+shift+v")
        #expect(decoded.settings?.maxHistory == 200)
        #expect(decoded.settings?.autoPaste == true)
    }

    // MARK: - Refusing to destroy data

    @Test("a wrong key aborts rather than importing an empty history")
    func wrongKeyAborts() throws {
        // The failure that would be catastrophic: treat "cannot decrypt" as
        // "nothing to import", set the marker, and the history is gone.
        let realCipher = FieldCipher(key: SymmetricKey(size: .bits256))
        let document = try makeDocument(
            clips: [textClip(id: "a", content: "precious")], cipher: realCipher
        )
        let wrongCipher = FieldCipher(key: SymmetricKey(size: .bits256))

        #expect(throws: LegacyImporter.Failure.self) {
            _ = try LegacyImporter().decode(document: document, cipher: wrongCipher)
        }
    }

    @Test("corrupt base64 aborts")
    func corruptBase64Aborts() throws {
        let document = try JSONSerialization.data(withJSONObject: ["history_enc": "!!!not-base64!!!"])
        #expect(throws: LegacyImporter.Failure.self) {
            _ = try LegacyImporter().decode(
                document: document, cipher: FieldCipher(key: SymmetricKey(size: .bits256))
            )
        }
    }

    @Test("a decrypt failure leaves the marker unset so the next launch retries")
    func failureLeavesMarkerUnset() async throws {
        let temp = try TempStore()
        let document = try makeDocument(
            clips: [textClip(id: "a", content: "precious")],
            cipher: FieldCipher(key: SymmetricKey(size: .bits256))
        )
        let url = temp.locations.root.appendingPathComponent("legacy.json")
        try temp.locations.createDirectories()
        try document.write(to: url)

        await #expect(throws: LegacyImporter.Failure.self) {
            _ = try await LegacyImporter().importIfNeeded(
                into: temp.store, from: url, cipher: temp.cipher, limit: 50
            )
        }
        #expect(try await temp.store.metaValue(LegacyImporter.markerKey) == nil)
        #expect(try await temp.store.clipCount() == 0)
    }

    // MARK: - Importing

    @Test("imports text and image clips, preserving ids, order and pin state")
    func importsFaithfully() async throws {
        let temp = try TempStore()
        let imageBytes = Data(repeating: 0x42, count: 4096)
        let document = try makeDocument(
            clips: [
                textClip(id: "t1", content: "newest", timestamp: 1_700_000_030_000, appName: "Ghostty"),
                imageClip(id: "i1", bytes: imageBytes, timestamp: 1_700_000_020_000),
                textClip(id: "t2", content: "pinned one", timestamp: 1_700_000_010_000, pinned: true),
            ],
            cipher: temp.cipher
        )
        let url = temp.locations.root.appendingPathComponent("legacy.json")
        try temp.locations.createDirectories()
        try document.write(to: url)

        let summary = try await LegacyImporter().importIfNeeded(
            into: temp.store, from: url, cipher: temp.cipher, limit: 50
        )

        #expect(summary?.imported == 3)
        #expect(summary?.skippedImages == 0)

        let clips = try await temp.store.allClips()
        #expect(clips.count == 3)
        // Pinned floats to the top regardless of age; the rest are newest-first.
        #expect(clips.map(\.id) == ["t2", "t1", "i1"])
        #expect(clips[0].isPinned)
        #expect(clips[1].text == "newest")
        #expect(clips[1].sourceApp == "Ghostty")
        // v1 timestamps are milliseconds; a seconds/milliseconds mix-up would
        // date every entry to 1970 and is invisible without this assertion.
        #expect(abs(clips[1].createdAt.timeIntervalSince1970 - 1_700_000_030) < 0.001)
    }

    @Test("image payloads move from base64-in-row to sealed sidecar files")
    func imagesBecomeSidecars() async throws {
        let temp = try TempStore()
        let imageBytes = Data((0..<8192).map { UInt8($0 % 251) })
        let document = try makeDocument(
            clips: [imageClip(id: "i1", bytes: imageBytes)], cipher: temp.cipher
        )
        let url = temp.locations.root.appendingPathComponent("legacy.json")
        try temp.locations.createDirectories()
        try document.write(to: url)

        try await LegacyImporter().importIfNeeded(
            into: temp.store, from: url, cipher: temp.cipher, limit: 50
        )

        let restored = try await temp.store.imageData(for: "i1")
        #expect(restored == imageBytes, "image bytes must survive the format change intact")

        let clips = try await temp.store.allClips()
        #expect(clips[0].pixelSizeLabel == "1280×830 PNG")
        #expect(clips[0].text == nil)
    }

    @Test("skips an undecodable image instead of aborting the whole import")
    func skipsBadImage() async throws {
        // One corrupt row must not cost the user every other row.
        let temp = try TempStore()
        var broken = imageClip(id: "bad", bytes: Data())
        broken["content"] = "!!!!not base64!!!!"
        let document = try makeDocument(
            clips: [broken, textClip(id: "good", content: "fine")], cipher: temp.cipher
        )
        let url = temp.locations.root.appendingPathComponent("legacy.json")
        try temp.locations.createDirectories()
        try document.write(to: url)

        let summary = try await LegacyImporter().importIfNeeded(
            into: temp.store, from: url, cipher: temp.cipher, limit: 50
        )
        #expect(summary?.imported == 1)
        #expect(summary?.skippedImages == 1)
        #expect(try await temp.store.clipCount() == 1)
    }

    @Test("runs once — a second call is a no-op")
    func runsOnlyOnce() async throws {
        let temp = try TempStore()
        let document = try makeDocument(
            clips: [textClip(id: "t1", content: "once")], cipher: temp.cipher
        )
        let url = temp.locations.root.appendingPathComponent("legacy.json")
        try temp.locations.createDirectories()
        try document.write(to: url)

        let first = try await LegacyImporter().importIfNeeded(
            into: temp.store, from: url, cipher: temp.cipher, limit: 50
        )
        let second = try await LegacyImporter().importIfNeeded(
            into: temp.store, from: url, cipher: temp.cipher, limit: 50
        )

        #expect(first?.imported == 1)
        #expect(second == nil)
        #expect(try await temp.store.clipCount() == 1)
    }

    @Test("never modifies the v1 file")
    func leavesTheSourceUntouched() async throws {
        // The v1 file stays as the fallback copy. Nothing here may write to it.
        let temp = try TempStore()
        let document = try makeDocument(
            clips: [textClip(id: "t1", content: "keep")], cipher: temp.cipher
        )
        let url = temp.locations.root.appendingPathComponent("legacy.json")
        try temp.locations.createDirectories()
        try document.write(to: url)
        let before = try Data(contentsOf: url)

        try await LegacyImporter().importIfNeeded(
            into: temp.store, from: url, cipher: temp.cipher, limit: 50
        )

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("a missing v1 file is a no-op, not a failure")
    func missingFileIsFine() async throws {
        let temp = try TempStore()
        let summary = try await LegacyImporter().importIfNeeded(
            into: temp.store,
            from: temp.locations.root.appendingPathComponent("nope.json"),
            cipher: temp.cipher,
            limit: 50
        )
        #expect(summary == nil)
    }

    @Test("applies the history limit after importing, by true recency")
    func appliesLimitAfterImport() async throws {
        let temp = try TempStore()
        let clips = (0..<20).map {
            textClip(id: "t\($0)", content: "entry \($0)", timestamp: 1_700_000_000_000 + Int64($0) * 1000)
        }
        let document = try makeDocument(clips: clips, cipher: temp.cipher)
        let url = temp.locations.root.appendingPathComponent("legacy.json")
        try temp.locations.createDirectories()
        try document.write(to: url)

        try await LegacyImporter().importIfNeeded(
            into: temp.store, from: url, cipher: temp.cipher, limit: 5
        )

        let stored = try await temp.store.allClips()
        #expect(stored.count == 5)
        #expect(stored.first?.text == "entry 19", "the newest must survive the trim")
    }
}
