import Testing

@testable import SwilClipCore

@Suite("KeyMapping")
struct KeyMappingTests {
    private func map(
        _ keyCode: UInt16,
        characters: String? = nil,
        base: String? = nil,
        modifiers: KeyModifiers = [],
        isSearching: Bool = false
    ) -> KeyCommand? {
        KeyMapping.command(
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: base ?? characters,
            modifiers: modifiers,
            isSearching: isSearching
        )
    }

    // MARK: - Structural keys

    @Test("arrows navigate, and gain jump behaviour with command")
    func arrows() {
        #expect(map(KeyCode.upArrow) == .moveUp)
        #expect(map(KeyCode.downArrow) == .moveDown)
        #expect(map(KeyCode.upArrow, modifiers: .command) == .moveToFirst)
        #expect(map(KeyCode.downArrow, modifiers: .command) == .moveToLast)
        #expect(map(KeyCode.home) == .moveToFirst)
        #expect(map(KeyCode.end) == .moveToLast)
    }

    @Test("structural keys work identically in both modes")
    func structuralKeysAreModeless() {
        // Arrow keys and Return must not become text just because a query is
        // open — that would make search a trap you can only leave with the mouse.
        for searching in [false, true] {
            #expect(map(KeyCode.upArrow, isSearching: searching) == .moveUp)
            #expect(map(KeyCode.return, isSearching: searching) == .confirm)
            #expect(map(KeyCode.enter, isSearching: searching) == .confirm)
            #expect(map(KeyCode.escape, isSearching: searching) == .dismiss)
            #expect(map(KeyCode.tab, isSearching: searching) == .switchTab)
        }
    }

    @Test("backspace edits the query only while searching")
    func backspaceIsModal() {
        #expect(map(KeyCode.delete, isSearching: true) == .deleteQueryCharacter)
        // Outside search it does nothing: a stray backspace must never be a
        // destructive action on the selected row.
        #expect(map(KeyCode.delete, isSearching: false) == nil)
    }

    // MARK: - Navigate mode

    @Test("letters are commands outside search")
    func lettersAreCommands() {
        #expect(map(1, characters: "s") == .beginSearch)
        #expect(map(2, characters: "d") == .deleteItem)
        #expect(map(35, characters: "p") == .togglePin)
        #expect(map(14, characters: "e") == .toggleExpand)
        #expect(map(32, characters: "u") == .undo)
        #expect(map(45, characters: "n") == .newPrompt)
    }

    @Test("⇧S promotes rather than opening search")
    func shiftSPromotes() {
        // The one shifted command. `charactersIgnoringModifiers` is what makes
        // it resolve to "s" even though the event's text is "S".
        #expect(map(1, characters: "S", base: "s", modifiers: .shift) == .promoteToPrompt)
        #expect(map(1, characters: "s", base: "s") == .beginSearch)
    }

    @Test("an unassigned printable key starts search with that character")
    func typeToFind() {
        // Type-to-find, the way every macOS list behaves.
        #expect(map(5, characters: "g") == .appendToQuery("g"))
        #expect(map(18, characters: "1") == .appendToQuery("1"))
    }

    // MARK: - Search mode

    @Test("letters become query text once searching")
    func lettersBecomeText() {
        #expect(map(2, characters: "d", isSearching: true) == .appendToQuery("d"))
        #expect(map(45, characters: "n", isSearching: true) == .appendToQuery("n"))
    }

    @Test("composed CJK input reaches the query intact")
    func cjkInput() {
        // `characters` already carries the input method's composition, so no
        // separate path is needed — but that only holds if the mapping uses
        // `characters` rather than the key code, which is what this pins down.
        #expect(map(0, characters: "简", isSearching: true) == .appendToQuery("简"))
        #expect(map(0, characters: "请", isSearching: false) == .appendToQuery("请"))
    }

    // MARK: - Keys that must be left alone

    @Test("control and option combinations are passed through untouched")
    func modifierCombinationsAreIgnored() {
        // Swallowing these makes the panel feel like it eats input.
        #expect(map(1, characters: "s", modifiers: .control) == nil)
        #expect(map(1, characters: "s", modifiers: .option) == nil)
        #expect(map(KeyCode.upArrow, modifiers: [.control, .shift]) == nil)
    }

    @Test("⌘-anything the panel does not own goes to the system")
    func commandKeysGoToTheSystem() {
        // ⌘Q must quit and ⌘, must open settings, both handled by AppKit.
        #expect(map(12, characters: "q", modifiers: .command) == nil)
        #expect(map(43, characters: ",", modifiers: .command) == nil)
    }

    @Test("function keys never leak into the query")
    func functionKeysAreNotText() {
        // AppKit reports these as private-use scalars; letting them through
        // would fill the query with invisible characters that match nothing.
        #expect(map(122, characters: "\u{F704}", isSearching: true) == nil)
        #expect(map(96, characters: "\u{F708}", isSearching: false) == nil)
        #expect(KeyMapping.isTypable("\u{F704}") == false)
        #expect(KeyMapping.isTypable("") == false)
        #expect(KeyMapping.isTypable("a") == true)
        #expect(KeyMapping.isTypable("请") == true)
    }
}
