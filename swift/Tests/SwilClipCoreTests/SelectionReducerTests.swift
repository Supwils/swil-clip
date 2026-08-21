import Testing

@testable import SwilClipCore

/// The suite that exists because of a shipped bug.
///
/// v1 0.1.2 deleted the wrong row: `cmdk` kept a second, invisible copy of the
/// selection and rewrote it when the selected element unmounted. Every case
/// below is a state that bug passed through. They are cheap to keep and they
/// turn "acted on the wrong row" from a runtime race into a test failure.
@Suite("SelectionReducer")
struct SelectionReducerTests {
    private let ids = ["a", "b", "c", "d"]

    private func state(
        selected: String?,
        searching: Bool = false,
        query: String = "",
        expanded: String? = nil,
        tab: PanelTab = .clipboard
    ) -> SelectionReducer.State {
        .init(
            selectedID: selected,
            query: query,
            isSearching: searching,
            tab: tab,
            expandedID: expanded
        )
    }

    // MARK: - Navigation

    @Test("moves down and up one row at a time")
    func movesByOne() {
        var s = state(selected: "a")
        s = SelectionReducer.reduce(s, .moveDown, visibleIDs: ids).state
        #expect(s.selectedID == "b")
        s = SelectionReducer.reduce(s, .moveDown, visibleIDs: ids).state
        #expect(s.selectedID == "c")
        s = SelectionReducer.reduce(s, .moveUp, visibleIDs: ids).state
        #expect(s.selectedID == "b")
    }

    @Test("stops at the ends instead of wrapping")
    func doesNotWrap() {
        // The list is ordered by recency. Jumping from newest to oldest on one
        // press is never the intent.
        let atTop = SelectionReducer.reduce(state(selected: "a"), .moveUp, visibleIDs: ids)
        #expect(atTop.state.selectedID == "a")

        let atBottom = SelectionReducer.reduce(state(selected: "d"), .moveDown, visibleIDs: ids)
        #expect(atBottom.state.selectedID == "d")
    }

    @Test("jumps to the first and last rows")
    func jumpsToEnds() {
        #expect(
            SelectionReducer.reduce(state(selected: "c"), .moveToFirst, visibleIDs: ids)
                .state.selectedID == "a"
        )
        #expect(
            SelectionReducer.reduce(state(selected: "b"), .moveToLast, visibleIDs: ids)
                .state.selectedID == "d"
        )
    }

    @Test("adopts an end row when nothing is selected yet")
    func adoptsEndWhenUnselected() {
        #expect(
            SelectionReducer.reduce(state(selected: nil), .moveDown, visibleIDs: ids)
                .state.selectedID == "a"
        )
        #expect(
            SelectionReducer.reduce(state(selected: nil), .moveUp, visibleIDs: ids)
                .state.selectedID == "d"
        )
    }

    @Test("navigating an empty list selects nothing and does not crash")
    func handlesEmptyList() {
        let outcome = SelectionReducer.reduce(state(selected: "gone"), .moveDown, visibleIDs: [])
        #expect(outcome.state.selectedID == nil)
        #expect(outcome.effect == nil)
    }

    // MARK: - Deletion (the regression this suite is named for)

    @Test("deletes the selected row, not a neighbour")
    func deletesTheSelectedRow() {
        let outcome = SelectionReducer.reduce(state(selected: "b"), .deleteItem, visibleIDs: ids)
        #expect(outcome.effect == .delete(id: "b"))
    }

    @Test("selection slides to the row that took the vacated position")
    func selectionSlidesDown() {
        // This is what lets `d` be held down to clear a run of entries.
        let outcome = SelectionReducer.reduce(state(selected: "b"), .deleteItem, visibleIDs: ids)
        #expect(outcome.state.selectedID == "c")
    }

    @Test("deleting the last row selects the new last row")
    func deletingLastSelectsNewLast() {
        let outcome = SelectionReducer.reduce(state(selected: "d"), .deleteItem, visibleIDs: ids)
        #expect(outcome.effect == .delete(id: "d"))
        #expect(outcome.state.selectedID == "c")
    }

    @Test("deleting the only row clears the selection")
    func deletingOnlyRowClearsSelection() {
        let outcome = SelectionReducer.reduce(
            state(selected: "solo"), .deleteItem, visibleIDs: ["solo"]
        )
        #expect(outcome.effect == .delete(id: "solo"))
        #expect(outcome.state.selectedID == nil)
    }

    @Test("a stale selection cannot delete anything")
    func staleSelectionIsInert() {
        // The exact v1 failure: a selection pointing at a row that is no longer
        // rendered. It must be a no-op — never an action on a different row.
        let outcome = SelectionReducer.reduce(
            state(selected: "vanished"), .deleteItem, visibleIDs: ids
        )
        #expect(outcome.effect == nil)
    }

    @Test("a stale selection cannot confirm, pin, expand or promote either")
    func staleSelectionBlocksEveryAction() {
        for command in [KeyCommand.confirm, .togglePin, .toggleExpand, .promoteToPrompt] {
            let outcome = SelectionReducer.reduce(
                state(selected: "vanished"), command, visibleIDs: ids
            )
            #expect(outcome.effect == nil, "\(command) acted on a row that is not visible")
        }
    }

    @Test("deletion within a filtered list stays inside the filtered list")
    func deletionRespectsFiltering() {
        // The reducer only ever sees what is rendered. Handing it the unfiltered
        // list is the mistake that would reintroduce the original bug.
        let visible = ["b", "d"]
        let outcome = SelectionReducer.reduce(
            state(selected: "b", searching: true, query: "x"), .deleteItem, visibleIDs: visible
        )
        #expect(outcome.effect == .delete(id: "b"))
        #expect(outcome.state.selectedID == "d")
    }

    @Test("collapses an expanded row when that row is deleted")
    func deletingCollapsesExpansion() {
        let outcome = SelectionReducer.reduce(
            state(selected: "b", expanded: "b"), .deleteItem, visibleIDs: ids
        )
        #expect(outcome.state.expandedID == nil)
    }

    // MARK: - selectionAfterRemoval

    @Test("resolves the successor from the pre-removal list")
    func successorResolution() {
        #expect(SelectionReducer.selectionAfterRemoval(of: "a", from: ids) == "b")
        #expect(SelectionReducer.selectionAfterRemoval(of: "c", from: ids) == "d")
        #expect(SelectionReducer.selectionAfterRemoval(of: "d", from: ids) == "c")
        #expect(SelectionReducer.selectionAfterRemoval(of: "a", from: ["a"]) == nil)
        // An id that was never present falls back to the head, so the panel
        // always has something selected while anything is showing.
        #expect(SelectionReducer.selectionAfterRemoval(of: "zz", from: ids) == "a")
    }

    // MARK: - Reconciliation

    @Test("keeps a still-valid selection when the list changes")
    func reconcileKeepsValidSelection() {
        #expect(SelectionReducer.reconcile(state(selected: "c"), with: ids).selectedID == "c")
    }

    @Test("re-anchors a selection whose row disappeared")
    func reconcileRepairsStaleSelection() {
        // A new clip arriving, or a filter narrowing, must never leave the
        // selection pointing at nothing.
        #expect(SelectionReducer.reconcile(state(selected: "gone"), with: ids).selectedID == "a")
    }

    @Test("adopts the first row when nothing was selected")
    func reconcileAdoptsFirst() {
        #expect(SelectionReducer.reconcile(state(selected: nil), with: ids).selectedID == "a")
    }

    @Test("clears the selection when the list empties")
    func reconcileClearsOnEmpty() {
        #expect(SelectionReducer.reconcile(state(selected: "a"), with: []).selectedID == nil)
    }

    @Test("drops an expansion whose row is gone")
    func reconcileDropsStaleExpansion() {
        let s = SelectionReducer.reconcile(state(selected: "a", expanded: "gone"), with: ids)
        #expect(s.expandedID == nil)
    }

    // MARK: - Search

    @Test("typing enters search and accumulates the query")
    func typingBuildsQuery() {
        var s = state(selected: "a")
        for fragment in ["g", "i", "t"] {
            s = SelectionReducer.reduce(s, .appendToQuery(fragment), visibleIDs: ids).state
        }
        #expect(s.isSearching)
        #expect(s.query == "git")
    }

    @Test("backspace on an empty query leaves search rather than doing nothing")
    func backspaceExitsSearch() {
        let s = SelectionReducer.reduce(
            state(selected: "a", searching: true, query: ""),
            .deleteQueryCharacter,
            visibleIDs: ids
        ).state
        #expect(s.isSearching == false)
    }

    @Test("escape peels one layer at a time")
    func escapePeelsLayers() {
        // Expanded + searching: first Esc collapses, second leaves search, third
        // dismisses. Closing outright on the first press throws away the context
        // the user just asked to see.
        var s = state(selected: "a", searching: true, query: "git", expanded: "a")

        var outcome = SelectionReducer.reduce(s, .dismiss, visibleIDs: ids)
        #expect(outcome.effect == nil)
        #expect(outcome.state.expandedID == nil)
        s = outcome.state

        outcome = SelectionReducer.reduce(s, .dismiss, visibleIDs: ids)
        #expect(outcome.effect == nil)
        #expect(outcome.state.isSearching == false)
        #expect(outcome.state.query.isEmpty)
        s = outcome.state

        outcome = SelectionReducer.reduce(s, .dismiss, visibleIDs: ids)
        #expect(outcome.effect == .dismiss)
    }

    // MARK: - Tabs and mouse

    @Test("tab switching toggles and reports an effect")
    func tabSwitching() {
        let outcome = SelectionReducer.reduce(state(selected: "a"), .switchTab, visibleIDs: ids)
        #expect(outcome.state.tab == .prompts)
        #expect(outcome.effect == .switchTab)
        #expect(
            SelectionReducer.reduce(outcome.state, .switchTab, visibleIDs: ids)
                .state.tab == .clipboard
        )
    }

    @Test("a click selects a visible row and ignores an invisible one")
    func clickSelection() {
        #expect(
            SelectionReducer.reduce(state(selected: "a"), .selectID("c"), visibleIDs: ids)
                .state.selectedID == "c"
        )
        #expect(
            SelectionReducer.reduce(state(selected: "a"), .selectID("zz"), visibleIDs: ids)
                .state.selectedID == "a"
        )
    }

    @Test("expand toggles off when pressed twice")
    func expandToggles() {
        let opened = SelectionReducer.reduce(state(selected: "b"), .toggleExpand, visibleIDs: ids)
        #expect(opened.state.expandedID == "b")
        let closed = SelectionReducer.reduce(opened.state, .toggleExpand, visibleIDs: ids)
        #expect(closed.state.expandedID == nil)
    }
}
