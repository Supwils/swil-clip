import Testing

@testable import SwilClipCore

@Suite("Expansion scrolling")
struct ExpansionScrollTests {
    private let ids = ["a", "b", "c"]
    private let step = KeyMapping.expansionScrollStep

    private func map(_ keyCode: UInt16, _ modifiers: KeyModifiers) -> KeyCommand? {
        KeyMapping.command(
            keyCode: keyCode, characters: nil, charactersIgnoringModifiers: nil,
            modifiers: modifiers, isSearching: false
        )
    }

    @Test("⇧↑ / ⇧↓ scroll; ⌘ still jumps; bare arrows still move")
    func mapping() {
        #expect(map(KeyCode.downArrow, .shift) == .scrollExpansion(lines: step))
        #expect(map(KeyCode.upArrow, .shift) == .scrollExpansion(lines: -step))
        #expect(map(KeyCode.downArrow, [.command, .shift]) == .moveToLast)
        #expect(map(KeyCode.downArrow, []) == .moveDown)
    }

    @Test("the expanded, selected row receives the scroll and nothing else changes")
    func scrollsTheOpenRow() {
        let start = SelectionReducer.State(selectedID: "b", expandedID: "b")
        let outcome = SelectionReducer.reduce(start, .scrollExpansion(lines: step), visibleIDs: ids)
        #expect(outcome.effect == .scrollExpansion(id: "b", lines: step))
        #expect(outcome.state == start)
    }

    /// Holding ⇧ out of habit must not freeze the list.
    @Test("with nothing expanded, the shifted arrow is a plain arrow")
    func fallsBackToMoving() {
        let start = SelectionReducer.State(selectedID: "b")
        let down = SelectionReducer.reduce(start, .scrollExpansion(lines: step), visibleIDs: ids)
        #expect(down.state.selectedID == "c")
        #expect(down.effect == nil)
        let up = SelectionReducer.reduce(start, .scrollExpansion(lines: -step), visibleIDs: ids)
        #expect(up.state.selectedID == "a")
    }

    /// The cursor moved off the open row: scrolling a row you are not on would
    /// be scrolling something out of sight.
    @Test("an expansion elsewhere in the list is not scrolled")
    func onlyTheSelectedRow() {
        let start = SelectionReducer.State(selectedID: "a", expandedID: "c")
        let outcome = SelectionReducer.reduce(start, .scrollExpansion(lines: step), visibleIDs: ids)
        #expect(outcome.effect == nil)
        #expect(outcome.state.selectedID == "b")
    }

    @Test("documented in the shortcut reference")
    func documented() {
        let action = KeyCommand.scrollExpansion(lines: 1).documentedAction
        #expect(ShortcutReference.documentedActions.contains(action))
    }
}
