import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore
@testable import SwilClipUI

/// A model on a throwaway store, with no window server anywhere in reach.
///
/// This fixture is the payoff of the target split: `AppModel` holds the undo
/// stack and the per-tab state machine, which between them are the largest
/// data-loss surface in the app and the place SW-06 lived.
@MainActor
final class TempModel {
    let root: URL
    let settings: Settings
    let model: AppModel

    init(sourceApp: @escaping @MainActor () -> String? = { nil }) throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-ui-tests-\(UUID().uuidString)", isDirectory: true)
        let locations = StorageLocations(root: root)
        let store = try LocalStore(locations: locations, key: SymmetricKey(size: .bits256))
        // A scratch domain, so a test never reads or writes the real prefs.
        let suite = UserDefaults(suiteName: "swilclip-tests-\(UUID().uuidString)")!
        settings = Settings(defaults: suite)
        model = AppModel(store: store, settings: settings, sourceApp: sourceApp)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("AppModel")
struct AppModelTests {
    @MainActor
    @Test("the source-app name is injected, not read from NSWorkspace")
    func sourceAppIsASeam() async throws {
        let temp = try TempModel(sourceApp: { "Xcode" })
        await temp.model.recordForTesting(text: "git rebase -i HEAD~3")
        await temp.model.refresh()
        #expect(temp.model.clips.count == 1)
        #expect(temp.model.clips.first?.sourceApp == "Xcode")
    }

    @MainActor
    @Test("with no source-app provider the clip simply has none")
    func sourceAppIsOptional() async throws {
        let temp = try TempModel()
        await temp.model.recordForTesting(text: "plain")
        await temp.model.refresh()
        #expect(temp.model.clips.first?.sourceApp == nil)
    }
}

@Suite("AppModel — tabs")
struct AppModelTabTests {
    @MainActor
    @Test("the tab list is clipboard plus each collection, in stored order")
    func tabsFollowCollections() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        #expect(temp.model.tabs == [
            .clipboard,
            .collection(LibraryCollection.Seed.prompts),
            .collection(LibraryCollection.Seed.personal),
        ])
        #expect(temp.model.firstCollectionID == LibraryCollection.Seed.prompts)
    }

    @MainActor
    @Test("each tab keeps its own cursor and query across a switch")
    func perTabStateSurvives() async throws {
        let temp = try TempModel()
        await temp.model.recordForTesting(text: "one")
        await temp.model.recordForTesting(text: "two")
        await temp.model.refresh()

        temp.model.handle(.selectID(temp.model.visibleIDs[1]))
        temp.model.handle(.beginSearch)
        // A query that matches both rows, so the filter cannot move the cursor
        // out from under the assertion — that would be `reconcileSelection`
        // doing its job, not the handover failing.
        temp.model.handle(.appendToQuery("o"))
        let clipID = temp.model.selection.selectedID
        #expect(clipID != nil)

        temp.model.handle(.switchTab)
        #expect(temp.model.selection.tab == .collection(LibraryCollection.Seed.prompts))
        #expect(temp.model.selection.query.isEmpty, "the other tab's search must not follow")

        temp.model.handle(.switchTabBackward)
        #expect(temp.model.selection.tab == .clipboard)
        #expect(temp.model.selection.query == "o", "returning resumes what you were doing")
        #expect(temp.model.selection.selectedID == clipID)
    }

    /// The tab-level version of "a selection pointing at a row that no longer
    /// exists". A stale parked entry would hand a resurrected id a stranger's
    /// cursor.
    @MainActor
    @Test("deleting the current collection drops to clipboard and prunes its parked state")
    func deletedTabIsReconciled() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        temp.model.handle(.switchTab)
        temp.model.handle(.switchTab)
        #expect(temp.model.selection.tab == .collection(LibraryCollection.Seed.personal))

        try await temp.model.deleteCollection(
            id: LibraryCollection.Seed.personal, movingEntriesTo: nil
        )

        #expect(temp.model.selection.tab == .clipboard)
        #expect(temp.model.tabs.count == 2)
        #expect(
            temp.model.parkedTabsForTesting == [.clipboard, .collection(LibraryCollection.Seed.prompts)]
                || temp.model.parkedTabsForTesting == [.clipboard],
            "no entry may survive for a tab that no longer exists"
        )
        #expect(!temp.model.parkedTabsForTesting.contains(.collection(LibraryCollection.Seed.personal)))
    }

    @MainActor
    @Test("entries are scoped to the tab that is showing")
    func entriesAreScopedToTheTab() async throws {
        let temp = try TempModel()
        try await temp.model.createEntryForTesting(
            collectionID: LibraryCollection.Seed.personal,
            title: "GitHub", body: "https://github.com/supwils"
        )
        try await temp.model.createEntryForTesting(
            collectionID: LibraryCollection.Seed.prompts,
            title: "Handoff", body: "session handoff"
        )
        await temp.model.refresh()

        temp.model.handle(.switchTab)
        #expect(temp.model.visibleEntries.map(\.title) == ["Handoff"])
        temp.model.handle(.switchTab)
        #expect(temp.model.visibleEntries.map(\.title) == ["GitHub"])
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.personal) == 1)
    }
}

@Suite("AppModel — save targets")
struct SaveTargetTests {
    @MainActor
    @Test("⇧S lands in the first collection, and says so")
    func promoteTargetsTheFirstCollection() async throws {
        let temp = try TempModel()
        await temp.model.recordForTesting(text: "https://github.com/supwils")
        await temp.model.refresh()
        temp.model.handle(.selectID(temp.model.visibleIDs[0]))

        temp.model.handle(.promoteToPrompt)
        try await Task.sleep(for: .milliseconds(80))

        #expect(temp.model.entryCount(in: LibraryCollection.Seed.prompts) == 1)
        #expect(temp.model.statusMessage?.contains("Prompts") == true)
        #expect(temp.model.clips.count == 1, "promoting never removes the clip")
    }

    /// The rule is "the first collection in tab order", and the order is drawn
    /// across the top bar — so reordering *is* the way to change the target.
    @MainActor
    @Test("reordering the collections retargets ⇧S")
    func reorderingRetargets() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        try await temp.model.reorderCollections([
            LibraryCollection.Seed.personal, LibraryCollection.Seed.prompts,
        ])
        #expect(temp.model.firstCollectionID == LibraryCollection.Seed.personal)

        await temp.model.recordForTesting(text: "https://github.com/supwils")
        await temp.model.refresh()
        temp.model.handle(.selectID(temp.model.visibleIDs[0]))

        temp.model.handle(.promoteToPrompt)
        try await Task.sleep(for: .milliseconds(80))
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.personal) == 1)
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.prompts) == 0)
    }

    /// Deleting every collection is reachable under the equality model, so it is
    /// defined rather than assumed away. Nothing is auto-created: the user
    /// deleted them on purpose, and a tool that silently rebuilds one is a tool
    /// that argues with you.
    @MainActor
    @Test("with no collections at all, saving points at Settings instead of guessing")
    func zeroCollections() async throws {
        let temp = try TempModel()
        try await temp.model.deleteCollection(
            id: LibraryCollection.Seed.prompts, movingEntriesTo: nil
        )
        try await temp.model.deleteCollection(
            id: LibraryCollection.Seed.personal, movingEntriesTo: nil
        )
        await temp.model.recordForTesting(text: "orphan")
        await temp.model.refresh()

        #expect(temp.model.tabs == [.clipboard])
        #expect(temp.model.firstCollectionID == nil)
        #expect(temp.model.selection.tab.topBarItems == [.tabs, .settings], "no ＋ to press")

        temp.model.handle(.selectID(temp.model.visibleIDs[0]))
        temp.model.handle(.promoteToPrompt)
        try await Task.sleep(for: .milliseconds(80))
        #expect(temp.model.statusMessage == temp.settings.strings.statusNoCollections)

        temp.model.clearStatus()
        temp.model.handle(.newItem)
        #expect(temp.model.statusMessage == temp.settings.strings.statusNoCollections)
    }

    /// `⇥` has nowhere to go with one tab, and the reducer says so by emitting
    /// no effect — otherwise the host would park the clipboard's state onto
    /// itself on every press.
    @MainActor
    @Test("switching tabs with only the clipboard left is inert")
    func switchingWithOneTab() async throws {
        let temp = try TempModel()
        try await temp.model.deleteCollection(
            id: LibraryCollection.Seed.prompts, movingEntriesTo: nil
        )
        try await temp.model.deleteCollection(
            id: LibraryCollection.Seed.personal, movingEntriesTo: nil
        )
        temp.model.handle(.switchTab)
        #expect(temp.model.selection.tab == .clipboard)
    }
}

@Suite("AppModel — collection management")
struct CollectionManagementTests {
    @MainActor
    @Test("creating a collection adds a tab at the end")
    func createAppendsATab() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        #expect(await temp.model.createCollection(name: "Work", symbol: .briefcase))
        #expect(temp.model.tabs.count == 4)
        #expect(temp.model.collections.last?.name == "Work")
        #expect(temp.model.collections.last?.symbol == .briefcase)
    }

    @MainActor
    @Test("the cap is enforced rather than silently ignored")
    func capIsEnforced() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        for index in 0..<(LibraryCollection.maximumCount - 2) {
            #expect(await temp.model.createCollection(name: "C\(index)", symbol: .tag))
        }
        #expect(await temp.model.createCollection(name: "over", symbol: .tag) == false)
        #expect(temp.model.collections.count == LibraryCollection.maximumCount)
    }

    @MainActor
    @Test("renaming a collection renames its tab, and its entries stay put")
    func renameKeepsMembership() async throws {
        let temp = try TempModel()
        try await temp.model.createEntryForTesting(
            collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "u"
        )
        await temp.model.refresh()

        var personal = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!
        personal.name = "Me"
        personal.symbol = .link
        await temp.model.updateCollection(personal)

        let back = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!
        #expect(back.name == "Me")
        #expect(back.symbol == .link)
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.personal) == 1)
    }
}

@Suite("AppModel — collection undo")
struct CollectionUndoTests {
    @MainActor
    @Test("undo brings back a collection whose entries were deleted with it")
    func undoAfterHardDelete() async throws {
        let temp = try TempModel()
        try await temp.model.createEntryForTesting(
            collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "u"
        )
        await temp.model.refresh()
        let doomed = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!

        await temp.model.deleteCollectionWithUndo(doomed, movingEntriesTo: nil)
        #expect(temp.model.tabs.count == 2)
        #expect(temp.model.entries.isEmpty)
        #expect(temp.model.canUndo)

        temp.model.handle(.undo)
        try await Task.sleep(for: .milliseconds(80))
        #expect(temp.model.tabs.count == 3)
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.personal) == 1)
    }

    /// One operation covers both buttons, because the snapshot is taken before
    /// the change and `LibraryEntry` carries its own `collectionID`: deleted
    /// rows are re-inserted, moved rows have their membership rewritten back.
    @MainActor
    @Test("undo also un-moves entries that were relocated instead of deleted")
    func undoAfterMove() async throws {
        let temp = try TempModel()
        try await temp.model.createEntryForTesting(
            collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "u"
        )
        await temp.model.refresh()
        let doomed = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!

        await temp.model.deleteCollectionWithUndo(
            doomed, movingEntriesTo: LibraryCollection.Seed.prompts
        )
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.prompts) == 1)

        temp.model.handle(.undo)
        try await Task.sleep(for: .milliseconds(80))
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.personal) == 1)
        #expect(temp.model.entryCount(in: LibraryCollection.Seed.prompts) == 0)
    }

    /// The order the collection comes back in matters: it is what the tab bar
    /// draws from, and a restored tab landing in the wrong place is the pin
    /// round-trip's failure wearing a different hat.
    @MainActor
    @Test("a restored collection comes back in its original position")
    func restoreKeepsPosition() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        let doomed = temp.model.collections.first { $0.id == LibraryCollection.Seed.prompts }!
        #expect(doomed.position == 0)

        await temp.model.deleteCollectionWithUndo(doomed, movingEntriesTo: nil)
        temp.model.handle(.undo)
        try await Task.sleep(for: .milliseconds(80))
        #expect(temp.model.collections.map(\.id) == [
            LibraryCollection.Seed.prompts, LibraryCollection.Seed.personal,
        ])
    }
}
