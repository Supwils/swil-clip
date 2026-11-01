import Foundation
import Testing

@testable import SwilClipCore

@Suite("Inline edit — keys and reducer")
struct InlineEditKeyTests {
    private let ids = ["a", "b", "c"]

    @Test("⇧E edits, bare e still expands")
    func shiftEEdits() {
        func map(_ modifiers: KeyModifiers) -> KeyCommand? {
            KeyMapping.command(
                keyCode: 14, characters: modifiers.contains(.shift) ? "E" : "e",
                charactersIgnoringModifiers: "e", modifiers: modifiers, isSearching: false
            )
        }
        #expect(map([]) == .toggleExpand)
        #expect(map(.shift) == .editInline)
    }

    @Test("while searching, ⇧E is just a capital E in the query")
    func shiftEIsTextWhileSearching() {
        let command = KeyMapping.command(
            keyCode: 14, characters: "E", charactersIgnoringModifiers: "e",
            modifiers: .shift, isSearching: true
        )
        #expect(command == .appendToQuery("E"))
    }

    @Test("the editor claims only ⌘⏎ and a bare ⎋")
    func editorKeys() {
        #expect(KeyMapping.inlineEditCommand(keyCode: KeyCode.return, modifiers: .command) == .save)
        #expect(KeyMapping.inlineEditCommand(keyCode: KeyCode.enter, modifiers: .command) == .save)
        #expect(KeyMapping.inlineEditCommand(keyCode: KeyCode.escape, modifiers: []) == .cancel)
        // A bare Return is a newline, and arrows move the caret: both belong to
        // the text view, not to the panel.
        #expect(KeyMapping.inlineEditCommand(keyCode: KeyCode.return, modifiers: []) == nil)
        #expect(KeyMapping.inlineEditCommand(keyCode: KeyCode.upArrow, modifiers: []) == nil)
        #expect(KeyMapping.inlineEditCommand(keyCode: KeyCode.escape, modifiers: .shift) == nil)
    }

    @Test("editing a collapsed row expands it")
    func editExpands() {
        let start = SelectionReducer.State(selectedID: "b")
        let outcome = SelectionReducer.reduce(start, .editInline, visibleIDs: ids)
        #expect(outcome.state.expandedID == "b")
        #expect(outcome.effect == .editInline(id: "b"))
    }

    /// `e` toggles; `⇧E` must not, or pressing it on an open row would hide the
    /// very text it was asked to edit.
    @Test("editing an expanded row keeps it expanded")
    func editNeverCollapses() {
        let start = SelectionReducer.State(selectedID: "b", expandedID: "b")
        let outcome = SelectionReducer.reduce(start, .editInline, visibleIDs: ids)
        #expect(outcome.state.expandedID == "b")
    }

    @Test("a selection the filter hid cannot be edited")
    func hiddenSelectionIsInert() {
        let start = SelectionReducer.State(selectedID: "z")
        let outcome = SelectionReducer.reduce(start, .editInline, visibleIDs: ids)
        #expect(outcome.effect == nil)
        #expect(outcome.state.expandedID == nil)
    }

    @Test("the new key is in the shortcut reference")
    func documented() {
        #expect(ShortcutReference.documentedActions.contains(KeyCommand.editInline.documentedAction))
    }
}

@Suite("Inline edit — LocalStore")
struct InlineEditStoreTests {
    @Test("rewrites the text in place, keeping id and position")
    func updatesInPlace() async throws {
        let temp = try TempStore()
        let old = Date(timeIntervalSince1970: 1_000)
        let item = try await temp.store.recordText("first draft", limit: 50, now: old)
        try await temp.store.recordText("newer", limit: 50, now: old.addingTimeInterval(60))

        try await temp.store.updateText(id: item!.id, to: "second draft\nwith a body")

        let clips = try await temp.store.allClips()
        #expect(clips.map(\.id).last == item!.id, "an edit must not lift the row to the top")
        let edited = clips.first { $0.id == item!.id }!
        #expect(edited.createdAt == old)
        #expect(edited.preview == PreviewText.derive(from: "second draft\nwith a body"))
        #expect(try await temp.store.text(for: item!.id) == "second draft\nwith a body")
    }

    @Test("stores exactly what it is given, so undo is a true inverse")
    func noTrimming() async throws {
        let temp = try TempStore()
        let item = try await temp.store.recordText("x", limit: 50)
        try await temp.store.updateText(id: item!.id, to: "  padded  \n")
        #expect(try await temp.store.text(for: item!.id) == "  padded  \n")
    }

    @Test("refuses blank text, images, and rows that are gone")
    func refusals() async throws {
        let temp = try TempStore()
        let text = try await temp.store.recordText("keep me", limit: 50)
        let image = try await temp.store.recordImage(
            Data(repeating: 1, count: 16), width: 1, height: 1, format: "png", limit: 50
        )

        await #expect(throws: LocalStore.EditFailure.emptyText) {
            try await temp.store.updateText(id: text!.id, to: " \n\t")
        }
        await #expect(throws: LocalStore.EditFailure.notText(id: image!.id)) {
            try await temp.store.updateText(id: image!.id, to: "caption")
        }
        await #expect(throws: LocalStore.EditFailure.notFound(id: "nope")) {
            try await temp.store.updateText(id: "nope", to: "anything")
        }
        #expect(try await temp.store.text(for: text!.id) == "keep me", "a refusal writes nothing")
    }
}
