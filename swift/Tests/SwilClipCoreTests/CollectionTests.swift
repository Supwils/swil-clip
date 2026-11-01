import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore

@Suite("CollectionSymbol")
struct CollectionSymbolTests {
    /// A row written by a future version — or a corrupted one — must still draw
    /// something. A tab with no glyph reads as a layout bug, and the same rule
    /// already governs `ClipItem.isUnreadable`: never render "nothing" for
    /// "could not read".
    @Test("an unknown stored value degrades to the default glyph")
    func unknownFallsBack() {
        #expect(CollectionSymbol.fallback("text.quote") == .textQuote)
        #expect(CollectionSymbol.fallback("person") == .person)
        #expect(CollectionSymbol.fallback("nonsense.symbol") == .textQuote)
        #expect(CollectionSymbol.fallback("") == .textQuote)
    }

    @Test("every case carries a distinct, non-empty SF Symbol name")
    func namesAreWellFormed() {
        let names = CollectionSymbol.allCases.map(\.rawValue)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
        #expect(CollectionSymbol.allCases.count >= 8, "a picker with too few options is not a picker")
    }
}

@Suite("LibraryEntry")
struct LibraryEntryTests {
    @Test("an item knows which collection it belongs to")
    func carriesItsCollection() {
        let item = LibraryEntry(
            collectionID: "personal", title: "GitHub", body: "https://github.com/supwils"
        )
        #expect(item.collectionID == "personal")
        #expect(item.preview == "https://github.com/supwils")
    }

    /// Unchanged from the prompt era, and asserted so the rename cannot quietly
    /// change what the row draws — focus travels by `RowAction` identity, so a
    /// reordering here would slide `⏎` from "edit" onto "expand".
    @Test("the row still draws pin, edit, expand, delete in that order")
    func rowActionsAreUnchanged() {
        let item = LibraryEntry(collectionID: "prompts", title: "t", body: "b")
        #expect(item.rowActions == [.pin, .edit, .expand, .delete])
    }

    @Test("items default into the seeded prompts collection")
    func defaultsToSeed() {
        #expect(LibraryEntry(title: "t", body: "b").collectionID == LibraryCollection.Seed.prompts)
    }
}

@Suite("Schema v3")
struct SchemaV3Tests {
    @Test("existing prompts land in the seeded prompts collection, unmoved")
    func existingPromptsKeepTheirHome() async throws {
        let temp = try TempStore()
        let created = try await temp.store.createEntry(collectionID: LibraryCollection.Seed.prompts, title: "Handoff", body: "session handoff")!

        let items = try await temp.store.allEntries()
        #expect(items.count == 1)
        #expect(items[0].id == created.id)
        #expect(items[0].collectionID == LibraryCollection.Seed.prompts)
    }

    @Test("both collections are seeded, in order, with the supplied names")
    func seedsTwoCollections() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(
            locations: StorageLocations(root: root),
            key: SymmetricKey(size: .bits256),
            seedNames: .init(prompts: "提示词", personal: "个人")
        )

        let collections = try await store.allCollections()
        #expect(collections.map(\.id) == [
            LibraryCollection.Seed.prompts, LibraryCollection.Seed.personal,
        ])
        #expect(collections.map(\.name) == ["提示词", "个人"])
        #expect(collections.map(\.position) == [0, 1])
        #expect(collections[0].symbol == .textQuote)
        #expect(collections[1].symbol == .person)
        #expect(collections.allSatisfy { !$0.isUnreadable })
    }

    @Test("the version stamp is committed with the migration, not after it")
    func versionIsStampedInsideTheTransaction() async throws {
        let temp = try TempStore()
        #expect(try await temp.store.schemaVersion() == 3)
    }

    /// The rule at the top of `Schema.swift`: `ALTER TABLE` is not idempotent,
    /// so a second run on an already-migrated file must be a no-op rather than
    /// an error that bricks a perfectly good database.
    @Test("re-opening a v3 database does not re-run the migration")
    func migrationIsNotRerun() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-remigrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256)

        let first = try LocalStore(locations: StorageLocations(root: root), key: key)
        try await first.createEntry(collectionID: LibraryCollection.Seed.prompts, title: "keep", body: "keep me")

        let second = try LocalStore(locations: StorageLocations(root: root), key: key)
        #expect(try await second.schemaVersion() == 3)
        #expect(try await second.allEntries().count == 1)
        #expect(try await second.allCollections().count == 2, "seeding must not duplicate")
    }
}

@Suite("LocalStore — collections")
struct LocalStoreCollectionTests {
    @Test("creates, renames and re-icons a collection")
    func crudRoundTrip() async throws {
        let temp = try TempStore()
        var made = try await temp.store.createCollection(name: "Work", symbol: .briefcase)!
        #expect(made.position == 2, "new collections go to the end")

        made.name = "Client work"
        made.symbol = .link
        try await temp.store.updateCollection(made)

        let back = try await temp.store.allCollections().first { $0.id == made.id }
        #expect(back?.name == "Client work")
        #expect(back?.symbol == .link)
    }

    @Test("refuses to create past the cap")
    func honoursTheCap() async throws {
        let temp = try TempStore()
        for index in 0..<(LibraryCollection.maximumCount - 2) {
            #expect(try await temp.store.createCollection(name: "C\(index)", symbol: .tag) != nil)
        }
        #expect(try await temp.store.createCollection(name: "one too many", symbol: .tag) == nil)
        #expect(try await temp.store.allCollections().count == LibraryCollection.maximumCount)
    }

    @Test("reordering rewrites positions densely")
    func reorderIsDense() async throws {
        let temp = try TempStore()
        let work = try await temp.store.createCollection(name: "Work", symbol: .briefcase)!
        try await temp.store.reorderCollections([
            work.id, LibraryCollection.Seed.personal, LibraryCollection.Seed.prompts,
        ])

        let ordered = try await temp.store.allCollections()
        #expect(ordered.map(\.id) == [
            work.id, LibraryCollection.Seed.personal, LibraryCollection.Seed.prompts,
        ])
        #expect(ordered.map(\.position) == [0, 1, 2])
    }

    @Test("entries are read back scoped to their collection")
    func entriesAreScoped() async throws {
        let temp = try TempStore()
        try await temp.store.createEntry(
            collectionID: LibraryCollection.Seed.prompts, body: "a prompt"
        )
        try await temp.store.createEntry(
            collectionID: LibraryCollection.Seed.personal,
            title: "GitHub", body: "https://github.com/supwils"
        )

        #expect(try await temp.store.entries(in: LibraryCollection.Seed.prompts).count == 1)
        let personal = try await temp.store.entries(in: LibraryCollection.Seed.personal)
        #expect(personal.count == 1)
        #expect(personal[0].title == "GitHub")
        #expect(try await temp.store.allEntries().count == 2)
    }

    @Test("deleting a collection can move its entries instead of losing them")
    func deleteMovesEntries() async throws {
        let temp = try TempStore()
        try await temp.store.createEntry(
            collectionID: LibraryCollection.Seed.personal,
            title: "GitHub", body: "https://github.com/supwils"
        )

        try await temp.store.deleteCollection(
            id: LibraryCollection.Seed.personal,
            movingEntriesTo: LibraryCollection.Seed.prompts
        )

        #expect(try await temp.store.allCollections().map(\.id) == [LibraryCollection.Seed.prompts])
        let moved = try await temp.store.entries(in: LibraryCollection.Seed.prompts)
        #expect(moved.count == 1, "the entry survived the tab it lived in")
        #expect(moved[0].title == "GitHub")
    }

    @Test("deleting a collection outright takes its entries with it")
    func deleteRemovesEntries() async throws {
        let temp = try TempStore()
        try await temp.store.createEntry(
            collectionID: LibraryCollection.Seed.personal, body: "throwaway"
        )
        try await temp.store.deleteCollection(
            id: LibraryCollection.Seed.personal, movingEntriesTo: nil
        )
        #expect(try await temp.store.allEntries().isEmpty)
    }

    /// CLAUDE.md §5.1: undo has to be a real inverse. Restoring the collection
    /// without restoring membership leaves the tab back but empty.
    @Test("restore puts the collection and its membership back")
    func restoreIsARealInverse() async throws {
        let temp = try TempStore()
        try await temp.store.createEntry(
            collectionID: LibraryCollection.Seed.personal,
            title: "GitHub", body: "https://github.com/supwils"
        )

        let doomed = try await temp.store.allCollections()
            .first { $0.id == LibraryCollection.Seed.personal }!
        let members = try await temp.store.entries(in: LibraryCollection.Seed.personal)

        try await temp.store.deleteCollection(
            id: doomed.id, movingEntriesTo: LibraryCollection.Seed.prompts
        )
        try await temp.store.restoreCollection(doomed, entries: members)

        let back = try await temp.store.allCollections()
        #expect(back.map(\.id) == [
            LibraryCollection.Seed.prompts, LibraryCollection.Seed.personal,
        ])
        #expect(try await temp.store.entries(in: LibraryCollection.Seed.personal).count == 1)
        #expect(try await temp.store.entries(in: LibraryCollection.Seed.prompts).isEmpty)
    }

    @Test("a name that will not decrypt is marked unreadable, never blank")
    func unreadableNames() async throws {
        let temp = try TempStore()
        try await temp.store.corruptCollectionNameForTesting(id: LibraryCollection.Seed.personal)
        let broken = try await temp.store.allCollections()
            .first { $0.id == LibraryCollection.Seed.personal }!
        #expect(broken.isUnreadable)
        #expect(broken.name.isEmpty, "the view supplies the placeholder, not the store")
    }

    @Test("promote lands a clip in the collection it is told, not a hard-coded one")
    func promoteTargetsACollection() async throws {
        let temp = try TempStore()
        let clip = try await temp.store.recordText("https://github.com/supwils", limit: 50)!
        let made = try await temp.store.promote(
            clipID: clip.id, into: LibraryCollection.Seed.personal
        )
        #expect(made?.collectionID == LibraryCollection.Seed.personal)
        #expect(try await temp.store.clipCount() == 1, "promoting does not remove the clip")
    }
}
