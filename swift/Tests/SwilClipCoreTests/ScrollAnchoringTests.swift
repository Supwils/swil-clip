import Foundation
import Testing

@testable import SwilClipCore

/// The suite behind "the list jitters when the cursor passes the middle".
///
/// The old behaviour re-centred on every selection change, so the list moved on
/// every keypress whether or not it needed to. These cases pin down the rule
/// that replaced it: scroll only when the cursor is running out of runway, and
/// then by the minimum that restores the margin.
@Suite("ScrollAnchoring")
struct ScrollAnchoringTests {
    private let lead = ScrollAnchoring.defaultLead // 2

    @Test("moving down reveals rows ahead of the cursor, not the cursor itself")
    func revealsAheadWhenMovingDown() {
        // Asking for row 7 while the cursor sits on 5 is what leaves two rows of
        // runway below it. Asking for row 5 would pin the cursor to the edge.
        #expect(
            ScrollAnchoring.revealIndex(movingFrom: 4, to: 5, count: 20) == 5 + lead
        )
    }

    @Test("moving up reveals rows behind the cursor")
    func revealsBehindWhenMovingUp() {
        #expect(
            ScrollAnchoring.revealIndex(movingFrom: 10, to: 9, count: 20) == 9 - lead
        )
    }

    @Test("the reveal target is clamped at both ends")
    func clampsAtEnds() {
        // Near the top there is nothing behind to reveal, and near the bottom
        // nothing ahead. Clamping is what stops an out-of-range scroll request.
        #expect(ScrollAnchoring.revealIndex(movingFrom: 1, to: 0, count: 20) == 0)
        #expect(ScrollAnchoring.revealIndex(movingFrom: 18, to: 19, count: 20) == 19)
    }

    @Test("a fresh selection with no previous position reveals itself")
    func noPreviousPositionRevealsSelf() {
        // Opening the panel, switching tabs, clicking a row: there is no
        // direction to project, and guessing one would scroll for no reason.
        #expect(ScrollAnchoring.revealIndex(movingFrom: nil, to: 7, count: 20) == 7)
    }

    @Test("re-selecting the same row asks for no movement past itself")
    func sameRowIsInert() {
        #expect(ScrollAnchoring.revealIndex(movingFrom: 5, to: 5, count: 20) == 5)
    }

    @Test("an empty or out-of-range list yields nothing to scroll to")
    func handlesDegenerateInput() {
        #expect(ScrollAnchoring.revealIndex(movingFrom: nil, to: 0, count: 0) == nil)
        #expect(ScrollAnchoring.revealIndex(movingFrom: 0, to: 5, count: 3) == nil)
        #expect(ScrollAnchoring.revealIndex(movingFrom: 0, to: -1, count: 3) == nil)
    }

    @Test("a single-row list never asks to scroll past itself")
    func singleRow() {
        #expect(ScrollAnchoring.revealIndex(movingFrom: nil, to: 0, count: 1) == 0)
    }

    @Test("the reveal target is always in range, for every move in a list")
    func targetIsAlwaysInRange() {
        // The property that matters: a scroll request for a row that does not
        // exist is either ignored or throws, and either way the cursor is lost.
        let count = 30
        for old in 0..<count {
            for new in 0..<count {
                guard let target = ScrollAnchoring.revealIndex(
                    movingFrom: old, to: new, count: count
                ) else {
                    Issue.record("no target for \(old) → \(new)")
                    continue
                }
                #expect((0..<count).contains(target), "out of range for \(old) → \(new)")
            }
        }
    }

    @Test("keyboard movement is never animated; a re-anchor is")
    func animationPolicy() {
        // Interpolating between two adjacent rows adds latency to every keypress
        // and lets held keys stack into a smear. A re-anchor is a large,
        // unexpected jump and is worth explaining.
        #expect(ScrollAnchoring.shouldAnimate(.keyboard) == false)
        #expect(ScrollAnchoring.shouldAnimate(.reanchor) == true)
    }
}

// MARK: - KeyBinding

@Suite("KeyBinding")
struct KeyBindingTests {
    @Test("matches only its exact key and modifier set")
    func matchesExactly() {
        let binding = KeyBinding(keyCode: KeyCode.tab, modifiers: [.command])
        #expect(binding.matches(keyCode: KeyCode.tab, modifiers: [.command]))
        #expect(!binding.matches(keyCode: KeyCode.tab, modifiers: []))
        #expect(!binding.matches(keyCode: KeyCode.tab, modifiers: [.command, .shift]))
        #expect(!binding.matches(keyCode: KeyCode.escape, modifiers: [.command]))
    }

    @Test("a rebound tab key wins over the command it would otherwise be")
    func rebindingBeatsBuiltInMeaning() {
        // Bound to `d`, which is normally delete. The binding is checked first,
        // so the user gets what they asked for instead of a deleted row.
        let binding = KeyBinding(keyCode: 2, modifiers: [])
        let command = KeyMapping.command(
            keyCode: 2, characters: "d", charactersIgnoringModifiers: "d",
            modifiers: [], isSearching: false, tabSwitch: binding
        )
        #expect(command == .switchTab)
    }

    @Test("a modifier chord binding works, and does not fire without the chord")
    func chordBinding() {
        let binding = KeyBinding(keyCode: KeyCode.tab, modifiers: [.command])
        #expect(
            KeyMapping.command(
                keyCode: KeyCode.tab, characters: "\t", charactersIgnoringModifiers: "\t",
                modifiers: [.command], isSearching: false, tabSwitch: binding
            ) == .switchTab
        )
        // Bare Tab now means nothing, because the user moved the binding.
        #expect(
            KeyMapping.command(
                keyCode: KeyCode.tab, characters: "\t", charactersIgnoringModifiers: "\t",
                modifiers: [], isSearching: false, tabSwitch: binding
            ) == nil
        )
    }

    @Test("the default binding is plain Tab, in both modes")
    func defaultIsTab() {
        for searching in [false, true] {
            #expect(
                KeyMapping.command(
                    keyCode: KeyCode.tab, characters: "\t", charactersIgnoringModifiers: "\t",
                    modifiers: [], isSearching: searching
                ) == .switchTab
            )
        }
    }

    @Test("renders a readable label for the settings field")
    func displayString() {
        #expect(KeyBinding.tab.displayString == "⇥")
        #expect(
            KeyBinding(keyCode: KeyCode.tab, modifiers: [.command, .shift]).displayString == "⇧⌘⇥"
        )
        #expect(KeyBinding(keyCode: 1, modifiers: [.control]).displayString == "⌃S")
    }

    @Test("survives a round trip through Codable")
    func codableRoundTrip() throws {
        // The binding is persisted; a lossy encoding would silently reset the
        // user's choice on the next launch.
        let original = KeyBinding(keyCode: 48, modifiers: [.command, .option])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(KeyBinding.self, from: data) == original)
    }
}
