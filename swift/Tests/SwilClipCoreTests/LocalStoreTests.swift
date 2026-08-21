import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore

/// A throwaway store rooted in a temp directory, torn down with the test.
///
/// Real files and a real SQLite connection on purpose. An in-memory fake would
/// pass while the parts that actually break — WAL, sidecar writes, the schema
/// itself — went untested.
struct TempStore: ~Copyable {
    let locations: StorageLocations
    let key: SymmetricKey
    let store: LocalStore

    init() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-tests-\(UUID().uuidString)", isDirectory: true)
        self.locations = StorageLocations(root: root)
        self.key = SymmetricKey(size: .bits256)
        self.store = try LocalStore(locations: locations, key: key)
    }

    var cipher: FieldCipher { FieldCipher(key: key) }

    deinit {
        try? FileManager.default.removeItem(at: locations.root)
    }
}

@Suite("LocalStore — clips")
struct LocalStoreClipTests {
    @Test("records a text clip and reads it back")
    func recordsText() async throws {
        let temp = try TempStore()
        try await temp.store.recordText("git rebase -i HEAD~3", limit: 50)

        let clips = try await temp.store.allClips()
        #expect(clips.count == 1)
        #expect(clips[0].kind == .text)
        #expect(clips[0].text == "git rebase -i HEAD~3")
        #expect(clips[0].preview == "git rebase -i HEAD~3")
    }

    @Test("ignores blank and whitespace-only content")
    func ignoresBlank() async throws {
        let temp = try TempStore()
        #expect(try await temp.store.recordText("", limit: 50) == nil)
        #expect(try await temp.store.recordText("   \n\t ", limit: 50) == nil)
        #expect(try await temp.store.clipCount() == 0)
    }

    @Test("re-copying keeps the original id instead of minting a new one")
    func deduplicationPreservesIdentity() async throws {
        // SC-08: v1 deleted and re-inserted on a repeat copy, which changed the
        // id and re-encoded the payload. Promotion must happen in place.
        let temp = try TempStore()
        let first = try await temp.store.recordText("same text", limit: 50)
        let second = try await temp.store.recordText(
            "same text", limit: 50, now: Date().addingTimeInterval(60)
        )

        #expect(try await temp.store.clipCount() == 1)
        #expect(first?.id == second?.id)
    }

    @Test("re-copying moves the entry back to the top")
    func deduplicationPromotes() async throws {
        let temp = try TempStore()
        let base = Date()
        try await temp.store.recordText("older", limit: 50, now: base)
        try await temp.store.recordText("newer", limit: 50, now: base.addingTimeInterval(10))
        try await temp.store.recordText("older", limit: 50, now: base.addingTimeInterval(20))

        let clips = try await temp.store.allClips()
        #expect(clips.map(\.text) == ["older", "newer"])
    }

    @Test("pinned clips sort above unpinned ones")
    func pinnedSortFirst() async throws {
        let temp = try TempStore()
        let base = Date()
        let old = try await temp.store.recordText("old", limit: 50, now: base)
        try await temp.store.recordText("new", limit: 50, now: base.addingTimeInterval(10))
        try await temp.store.setPinned(true, id: old!.id)

        let clips = try await temp.store.allClips()
        #expect(clips.map(\.text) == ["old", "new"])
        #expect(clips[0].isPinned)
    }

    @Test("eviction trims to the limit, oldest first")
    func evictionTrimsOldest() async throws {
        let temp = try TempStore()
        let base = Date()
        for index in 0..<10 {
            try await temp.store.recordText(
                "entry \(index)", limit: 5, now: base.addingTimeInterval(Double(index))
            )
        }
        let clips = try await temp.store.allClips()
        #expect(clips.count == 5)
        #expect(clips.first?.text == "entry 9")
        #expect(clips.last?.text == "entry 5")
    }

    @Test("pinned clips never count toward the limit and are never evicted")
    func pinnedSurviveEviction() async throws {
        // Pinning has to mean something. If a pinned entry can be evicted, the
        // feature is decoration.
        let temp = try TempStore()
        let base = Date()
        let keeper = try await temp.store.recordText("keep me", limit: 3, now: base)
        try await temp.store.setPinned(true, id: keeper!.id)

        for index in 0..<10 {
            try await temp.store.recordText(
                "noise \(index)", limit: 3, now: base.addingTimeInterval(Double(index + 1))
            )
        }

        let clips = try await temp.store.allClips()
        #expect(clips.contains { $0.id == keeper!.id })
        #expect(clips.filter { !$0.isPinned }.count == 3)
    }

    @Test("stores image bytes in a sidecar file, not in the row")
    func imagesLiveOutsideTheRow() async throws {
        // The row a list renders from must never carry megabytes.
        let temp = try TempStore()
        let bytes = Data(repeating: 0x7F, count: 64 * 1024)
        let item = try await temp.store.recordImage(
            bytes, width: 1280, height: 830, format: "png", limit: 50
        )

        let clips = try await temp.store.allClips()
        #expect(clips.count == 1)
        #expect(clips[0].kind == .image)
        #expect(clips[0].text == nil, "an image row must not carry its payload")
        #expect(clips[0].pixelSizeLabel == "1280×830 PNG")

        let restored = try await temp.store.imageData(for: item!.id)
        #expect(restored == bytes)
    }

    @Test("the sidecar file on disk is encrypted, not the raw image")
    func sidecarIsSealed() async throws {
        let temp = try TempStore()
        let bytes = Data("PLAINTEXT-MARKER".utf8)
        let item = try await temp.store.recordImage(
            bytes, width: 2, height: 2, format: "png", limit: 50
        )
        let onDisk = try Data(
            contentsOf: temp.locations.blobsURL.appendingPathComponent("\(item!.id).bin")
        )
        #expect(onDisk != bytes)
        #expect(onDisk.range(of: bytes) == nil, "the plaintext must not appear on disk")
    }

    @Test("deleting a clip removes its sidecar file too")
    func deleteRemovesSidecar() async throws {
        let temp = try TempStore()
        let item = try await temp.store.recordImage(
            Data(repeating: 1, count: 128), width: 4, height: 4, format: "png", limit: 50
        )
        let path = temp.locations.blobsURL.appendingPathComponent("\(item!.id).bin")
        #expect(FileManager.default.fileExists(atPath: path.path))

        try await temp.store.delete(id: item!.id)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(try await temp.store.clipCount() == 0)
    }

    @Test("clearUnpinned returns what it removed and spares pinned rows")
    func clearUnpinnedIsUndoable() async throws {
        let temp = try TempStore()
        let pinned = try await temp.store.recordText("pinned", limit: 50)
        try await temp.store.setPinned(true, id: pinned!.id)
        try await temp.store.recordText("doomed a", limit: 50)
        try await temp.store.recordText("doomed b", limit: 50)

        let removed = try await temp.store.clearUnpinned()
        #expect(removed.count == 2)
        #expect(try await temp.store.clipCount() == 1)

        // Undo restores exactly what was reported — including, unlike v1, images.
        try await temp.store.restore(removed, contents: [:])
        #expect(try await temp.store.clipCount() == 3)
    }

    @Test("row content is encrypted on disk")
    func rowsAreSealed() async throws {
        let temp = try TempStore()
        try await temp.store.recordText("sk-live-SECRET-TOKEN", limit: 50)

        let raw = try Data(contentsOf: temp.locations.databaseURL)
        #expect(raw.range(of: Data("sk-live-SECRET-TOKEN".utf8)) == nil,
                "plaintext found in the database file")
    }

    @Test("a reopened database keeps its rows")
    func persistsAcrossReopen() async throws {
        let temp = try TempStore()
        try await temp.store.recordText("survives", limit: 50)

        let reopened = try LocalStore(locations: temp.locations, key: temp.key)
        let clips = try await reopened.allClips()
        #expect(clips.map(\.text) == ["survives"])
    }
}

@Suite("LocalStore — prompts")
struct LocalStorePromptTests {
    @Test("creates a prompt with a title derived from the body")
    func createsWithDerivedTitle() async throws {
        let temp = try TempStore()
        let prompt = try await temp.store.createPrompt(
            body: "请优化语言描述，降低AI感，非流水账，使用偏正式的措辞"
        )
        // 24 characters, then an ellipsis — the panel is 340 pt wide.
        #expect(prompt?.title == "请优化语言描述，降低AI感，非流水账，使用偏正式…")
        #expect(prompt?.body.hasPrefix("请优化语言描述") == true)
    }

    @Test("an explicit title wins over the derived one")
    func explicitTitleWins() async throws {
        let temp = try TempStore()
        let prompt = try await temp.store.createPrompt(title: "简历优化", body: "请根据岗位要求…")
        #expect(prompt?.title == "简历优化")
    }

    @Test("refuses an empty body")
    func refusesEmptyBody() async throws {
        let temp = try TempStore()
        #expect(try await temp.store.createPrompt(body: "   \n ") == nil)
        #expect(try await temp.store.promptCount() == 0)
    }

    @Test("prompts are exempt from history eviction")
    func promptsSurviveClipChurn() async throws {
        // The entire reason the library exists: things worth keeping must not be
        // washed away by the 50-entry window.
        let temp = try TempStore()
        try await temp.store.createPrompt(body: "long-lived instruction")
        for index in 0..<200 {
            try await temp.store.recordText("churn \(index)", limit: 5)
        }
        #expect(try await temp.store.promptCount() == 1)
        #expect(try await temp.store.clipCount() == 5)
    }

    @Test("editing updates the body and bumps updatedAt")
    func editingBumpsTimestamp() async throws {
        let temp = try TempStore()
        var prompt = try await temp.store.createPrompt(body: "original")!
        let originalUpdate = prompt.updatedAt

        prompt.body = "revised"
        let later = originalUpdate.addingTimeInterval(60)
        try await temp.store.updatePrompt(prompt, now: later)

        let reloaded = try await temp.store.prompt(id: prompt.id)
        #expect(reloaded?.body == "revised")
        #expect(reloaded!.updatedAt > originalUpdate)
    }

    @Test("⇧S promotes a clip into the library without removing it from history")
    func promotionKeepsTheClip() async throws {
        // The action the merged panel exists for. Promotion is additive: the
        // clip stays where it was, so nothing is lost by pressing it.
        let temp = try TempStore()
        let clip = try await temp.store.recordText(
            "请整理下我们这轮session的工作，并做好工作交接", limit: 50
        )!

        let prompt = try await temp.store.promoteToPrompt(clipID: clip.id)

        #expect(prompt?.body == "请整理下我们这轮session的工作，并做好工作交接")
        #expect(prompt?.title.hasPrefix("请整理下我们这轮session") == true)
        #expect(try await temp.store.clipCount() == 1, "promotion must not consume the clip")
    }

    @Test("promoting an image clip is a no-op rather than an error")
    func promotingAnImageDoesNothing() async throws {
        let temp = try TempStore()
        let image = try await temp.store.recordImage(
            Data(repeating: 9, count: 32), width: 1, height: 1, format: "png", limit: 50
        )!
        #expect(try await temp.store.promoteToPrompt(clipID: image.id) == nil)
        #expect(try await temp.store.promptCount() == 0)
    }

    @Test("prompt bodies are encrypted on disk")
    func promptsAreSealed() async throws {
        // A prompt body is often the most sensitive text in the app, and it
        // lives far longer than any clipboard entry.
        let temp = try TempStore()
        try await temp.store.createPrompt(body: "PROPRIETARY-PROMPT-BODY")

        let raw = try Data(contentsOf: temp.locations.databaseURL)
        #expect(raw.range(of: Data("PROPRIETARY-PROMPT-BODY".utf8)) == nil)
    }

    @Test("pinned prompts sort first")
    func pinnedPromptsSortFirst() async throws {
        let temp = try TempStore()
        let base = Date()
        let first = try await temp.store.createPrompt(body: "alpha", now: base)!
        try await temp.store.createPrompt(body: "beta", now: base.addingTimeInterval(10))
        try await temp.store.setPromptPinned(true, id: first.id)

        let prompts = try await temp.store.allPrompts()
        #expect(prompts.map(\.body) == ["alpha", "beta"])
    }
}

/// Pin/unpin ordering — the behaviour that keeps the selection under your eye.
@Suite("LocalStore — pin ordering")
struct LocalStorePinOrderingTests {
    @Test("unpinning lifts the entry to the top of the unpinned group")
    func unpinningPromotesToTop() async throws {
        // Without this, unpinning drops a row back to wherever its age puts it —
        // often hundreds of entries down — taking the selection off screen with
        // it. You unpinned it because you were looking at it.
        let temp = try TempStore()
        let base = Date()
        let old = try await temp.store.recordText("old and pinned", limit: 50, now: base)!
        for index in 1...5 {
            try await temp.store.recordText(
                "newer \(index)", limit: 50, now: base.addingTimeInterval(Double(index))
            )
        }
        try await temp.store.setPinned(true, id: old.id)
        #expect(try await temp.store.allClips().first?.id == old.id)

        try await temp.store.setPinned(
            false, id: old.id, now: base.addingTimeInterval(100)
        )

        let clips = try await temp.store.allClips()
        #expect(clips.first?.id == old.id, "unpinned entry must stay at the top")
        #expect(clips.first?.isPinned == false)
    }

    @Test("pinning leaves the entry's age alone")
    func pinningPreservesAge() async throws {
        // The pinned group is small enough to scan, and age is what orders it.
        // Rewriting the timestamp would shuffle the group on every pin.
        let temp = try TempStore()
        let base = Date()
        let item = try await temp.store.recordText("keep my age", limit: 50, now: base)!

        try await temp.store.setPinned(true, id: item.id)

        let stored = try await temp.store.allClips().first
        #expect(abs(stored!.createdAt.timeIntervalSince(base)) < 0.001)
    }

    @Test("pinned entries still sort above the promoted unpinned one")
    func pinnedStayAbove() async throws {
        let temp = try TempStore()
        let base = Date()
        let keeper = try await temp.store.recordText("stays pinned", limit: 50, now: base)!
        let mover = try await temp.store.recordText(
            "gets unpinned", limit: 50, now: base.addingTimeInterval(1)
        )!
        try await temp.store.setPinned(true, id: keeper.id)
        try await temp.store.setPinned(true, id: mover.id)

        try await temp.store.setPinned(
            false, id: mover.id, now: base.addingTimeInterval(100)
        )

        let clips = try await temp.store.allClips()
        #expect(clips.map(\.id) == [keeper.id, mover.id])
        #expect(clips[0].isPinned)
        #expect(!clips[1].isPinned)
    }

    @Test("an unpinned entry is not immediately evicted by the next capture")
    func unpinningDoesNotBecomeADelayedDelete() async throws {
        // Observed in the wild before the fix: unpinning kept the entry's old
        // timestamp, so it landed among the *oldest* unpinned rows and the next
        // few captures evicted it. Unpin looked like a display change and was
        // actually a delayed delete.
        let temp = try TempStore()
        let base = Date()
        let keeper = try await temp.store.recordText("was pinned", limit: 5, now: base)!
        try await temp.store.setPinned(true, id: keeper.id)

        // Fill the unpinned window right up to the limit.
        for index in 1...5 {
            try await temp.store.recordText(
                "filler \(index)", limit: 5, now: base.addingTimeInterval(Double(index))
            )
        }
        try await temp.store.setPinned(
            false, id: keeper.id, now: base.addingTimeInterval(10)
        )

        // A few more captures, each of which evicts the oldest unpinned row.
        for index in 6...9 {
            try await temp.store.recordText(
                "after \(index)", limit: 5, now: base.addingTimeInterval(Double(index) + 10)
            )
        }

        let clips = try await temp.store.allClips()
        #expect(
            clips.contains { $0.id == keeper.id },
            "an entry unpinned moments ago must not be evicted before newer ones"
        )
    }

    @Test("unpinning a prompt lifts it to the top of the library too")
    func unpinningPromptPromotes() async throws {
        let temp = try TempStore()
        let base = Date()
        let old = try await temp.store.createPrompt(body: "old prompt", now: base)!
        try await temp.store.createPrompt(body: "newer prompt", now: base.addingTimeInterval(10))
        try await temp.store.setPromptPinned(true, id: old.id)

        try await temp.store.setPromptPinned(
            false, id: old.id, now: base.addingTimeInterval(100)
        )

        #expect(try await temp.store.allPrompts().first?.id == old.id)
    }
}

/// Image thumbnails — the row-level preview, and its lifetime.
@Suite("LocalStore — thumbnails")
struct LocalStoreThumbnailTests {
    private let thumb = Data("fake-jpeg-bytes".utf8)

    @Test("a recorded image carries its thumbnail back out")
    func roundTripsThumbnail() async throws {
        let temp = try TempStore()
        try await temp.store.recordImage(
            Data(repeating: 7, count: 2048), width: 100, height: 80,
            format: "png", thumbnail: thumb, limit: 50
        )
        #expect(try await temp.store.allClips().first?.thumbnail == thumb)
    }

    @Test("the thumbnail is encrypted on disk like everything else")
    func thumbnailIsSealed() async throws {
        // A thumbnail of a screenshot is still a picture of whatever was on
        // screen. Storing it in the clear would undo the point of the store.
        let temp = try TempStore()
        let marker = Data("THUMB-PLAINTEXT-MARKER".utf8)
        try await temp.store.recordImage(
            Data(repeating: 3, count: 512), width: 10, height: 10,
            format: "png", thumbnail: marker, limit: 50
        )
        let raw = try Data(contentsOf: temp.locations.databaseURL)
        #expect(raw.range(of: marker) == nil)
    }

    @Test("deleting the clip takes the thumbnail with it")
    func deletingRemovesThumbnail() async throws {
        // The thumbnail is a column, not a sidecar, so cleanup is a property of
        // the schema rather than something the delete path has to remember.
        let temp = try TempStore()
        let item = try await temp.store.recordImage(
            Data(repeating: 5, count: 512), width: 10, height: 10,
            format: "png", thumbnail: thumb, limit: 50
        )!
        try await temp.store.delete(id: item.id)

        let raw = try Data(contentsOf: temp.locations.databaseURL)
        #expect(raw.range(of: thumb) == nil)
        #expect(try await temp.store.clipCount() == 0)
    }

    @Test("eviction takes thumbnails with it too")
    func evictionRemovesThumbnail() async throws {
        let temp = try TempStore()
        let base = Date()
        try await temp.store.recordImage(
            Data(repeating: 9, count: 512), width: 10, height: 10,
            format: "png", thumbnail: thumb, limit: 2, now: base
        )
        for index in 1...5 {
            try await temp.store.recordText(
                "filler \(index)", limit: 2, now: base.addingTimeInterval(Double(index))
            )
        }
        #expect(try await temp.store.clipCount() == 2)
        let raw = try Data(contentsOf: temp.locations.databaseURL)
        #expect(raw.range(of: thumb) == nil)
    }

    @Test("rows without a thumbnail are reported for backfill, then stop being")
    func backfillQueue() async throws {
        let temp = try TempStore()
        let item = try await temp.store.recordImage(
            Data(repeating: 1, count: 512), width: 10, height: 10,
            format: "png", thumbnail: nil, limit: 50
        )!

        let pending = try await temp.store.imageRowsMissingThumbnail()
        #expect(pending.map(\.id) == [item.id])

        try await temp.store.setThumbnail(thumb, id: item.id)

        #expect(try await temp.store.imageRowsMissingThumbnail().isEmpty)
        #expect(try await temp.store.allClips().first?.thumbnail == thumb)
    }

    @Test("text rows are never queued for a thumbnail")
    func textRowsAreNotQueued() async throws {
        let temp = try TempStore()
        try await temp.store.recordText("just text", limit: 50)
        #expect(try await temp.store.imageRowsMissingThumbnail().isEmpty)
    }
}

/// Undoing a pin change has to be a real inverse, not a second mutation.
@Suite("LocalStore — pin undo")
struct LocalStorePinUndoTests {
    @Test("undoing an unpin restores both the flag and the original position")
    func undoUnpinRestoresOrdering() async throws {
        // Unpinning rewrites the sort key to lift the row to the top of its
        // group. An undo that put back only `is_pinned` would leave the entry
        // pinned but ordered as though it had just been copied — the pinned
        // group would silently reshuffle every time someone pressed u.
        let temp = try TempStore()
        let base = Date()
        let item = try await temp.store.recordText("old and pinned", limit: 50, now: base)!
        for index in 1...3 {
            try await temp.store.recordText(
                "newer \(index)", limit: 50, now: base.addingTimeInterval(Double(index))
            )
        }
        try await temp.store.setPinned(true, id: item.id)
        let before = try await temp.store.allClips().first { $0.id == item.id }!

        try await temp.store.setPinned(false, id: item.id, now: base.addingTimeInterval(500))
        try await temp.store.restorePinState(
            id: item.id, isPinned: before.isPinned, orderDate: before.createdAt
        )

        let after = try await temp.store.allClips().first { $0.id == item.id }!
        #expect(after.isPinned)
        #expect(abs(after.createdAt.timeIntervalSince(before.createdAt)) < 0.001,
                "the original sort position must come back too")
    }

    @Test("undoing a pin puts the entry back where it was in history")
    func undoPinRestoresPosition() async throws {
        let temp = try TempStore()
        let base = Date()
        let item = try await temp.store.recordText("middle of history", limit: 50, now: base)!
        try await temp.store.recordText("newer", limit: 50, now: base.addingTimeInterval(10))
        let before = try await temp.store.allClips().first { $0.id == item.id }!

        try await temp.store.setPinned(true, id: item.id)
        try await temp.store.restorePinState(
            id: item.id, isPinned: before.isPinned, orderDate: before.createdAt
        )

        let clips = try await temp.store.allClips()
        #expect(clips.first?.text == "newer", "the unpinned entry must not stay on top")
        #expect(clips.first { $0.id == item.id }?.isPinned == false)
    }

    @Test("prompt pin undo restores the flag and updatedAt")
    func undoPromptPin() async throws {
        let temp = try TempStore()
        let base = Date()
        let prompt = try await temp.store.createPrompt(body: "a prompt", now: base)!
        try await temp.store.createPrompt(body: "another", now: base.addingTimeInterval(10))
        try await temp.store.setPromptPinned(true, id: prompt.id)

        try await temp.store.setPromptPinned(
            false, id: prompt.id, now: base.addingTimeInterval(500)
        )
        try await temp.store.restorePromptPinState(
            id: prompt.id, isPinned: true, orderDate: base
        )

        let restored = try await temp.store.prompt(id: prompt.id)!
        #expect(restored.isPinned)
        #expect(abs(restored.updatedAt.timeIntervalSince(base)) < 0.001)
    }

    @Test("pin, unpin, then two undos returns to the exact starting state")
    func doubleUndoIsIdempotent() async throws {
        // The property that matters: undo composes. Two changes and two undos
        // must land back on the original row state, byte for byte.
        let temp = try TempStore()
        let base = Date()
        let item = try await temp.store.recordText("subject", limit: 50, now: base)!
        let original = try await temp.store.allClips().first { $0.id == item.id }!

        let afterPinSnapshot = (original.isPinned, original.createdAt)
        try await temp.store.setPinned(true, id: item.id)
        let pinned = try await temp.store.allClips().first { $0.id == item.id }!
        try await temp.store.setPinned(false, id: item.id, now: base.addingTimeInterval(900))

        try await temp.store.restorePinState(
            id: item.id, isPinned: pinned.isPinned, orderDate: pinned.createdAt
        )
        try await temp.store.restorePinState(
            id: item.id, isPinned: afterPinSnapshot.0, orderDate: afterPinSnapshot.1
        )

        let final = try await temp.store.allClips().first { $0.id == item.id }!
        #expect(final.isPinned == original.isPinned)
        #expect(abs(final.createdAt.timeIntervalSince(original.createdAt)) < 0.001)
    }
}
