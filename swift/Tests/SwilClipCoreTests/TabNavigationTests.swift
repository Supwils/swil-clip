import Testing

@testable import SwilClipCore

@Suite("PanelTab")
struct PanelTabTests {
    /// The `＋` used to exist because the tab was *the* prompts tab. Now it
    /// exists because the tab is a collection — one rule instead of one name.
    @Test("every collection tab carries the add button; clipboard never does")
    func topBarStopsDeriveFromTheCase() {
        #expect(PanelTab.clipboard.topBarItems == [.tabs, .settings])
        #expect(PanelTab.collection("prompts").topBarItems == [.tabs, .newItem, .settings])
        #expect(PanelTab.collection("anything").topBarItems == [.tabs, .newItem, .settings])
    }

    @Test("tabs carry a stable string form and expose their collection")
    func storageKeyAndCollectionID() {
        #expect(PanelTab.clipboard.storageKey == "clipboard")
        #expect(PanelTab.collection("personal").storageKey == "collection:personal")
        #expect(PanelTab.clipboard.collectionID == nil)
        #expect(PanelTab.collection("personal").collectionID == "personal")
    }
}

@Suite("Tab cycling")
struct TabCyclingTests {
    private let tabs: [PanelTab] = [
        .clipboard, .collection("prompts"), .collection("personal"), .collection("work"),
    ]

    private func state(tab: PanelTab, focus: PanelFocus = .list) -> SelectionReducer.State {
        .init(selectedID: "a", tab: tab, focus: focus)
    }

    @Test("⇥ steps forward and wraps at the end")
    func forwardWraps() {
        var s = state(tab: .clipboard)
        for expected in tabs.dropFirst() + [.clipboard] {
            s = SelectionReducer.reduce(s, .switchTab, visibleIDs: ["a"], tabs: tabs).state
            #expect(s.tab == expected)
        }
    }

    @Test("⇧⇥ steps backward and wraps at the start")
    func backwardWraps() {
        let s = SelectionReducer.reduce(
            state(tab: .clipboard), .switchTabBackward, visibleIDs: ["a"], tabs: tabs
        )
        #expect(s.state.tab == .collection("work"))
        #expect(s.effect == .switchTab)
    }

    /// Wrapping is right here and wrong in the list, and the difference is not
    /// taste: a list is unbounded with both ends off-screen, a tab bar is four
    /// stops and all of them are drawn. Wrapping is safe exactly when the
    /// boundary is visible.
    @Test("a single tab has nowhere to go and emits no effect")
    func singleTabIsANoOp() {
        let outcome = SelectionReducer.reduce(
            state(tab: .clipboard), .switchTab, visibleIDs: ["a"], tabs: [.clipboard]
        )
        #expect(outcome.state.tab == .clipboard)
        #expect(outcome.effect == nil, "a no-op switch must not trigger a state handover")
    }

    @Test("switching tabs drops row focus but keeps the band")
    func focusRulesSurvive() {
        let fromRow = SelectionReducer.reduce(
            state(tab: .clipboard, focus: .row(action: .delete)),
            .switchTab, visibleIDs: ["a"], actions: [.pin, .delete], tabs: tabs
        )
        #expect(fromRow.state.focus == .list, "the next tab's rows carry different buttons")

        let fromBand = SelectionReducer.reduce(
            state(tab: .clipboard, focus: .tabs), .switchTab, visibleIDs: ["a"], tabs: tabs
        )
        #expect(fromBand.state.focus == .tabs, "the band is panel-wide, not per tab")
    }

    @Test("a stop the incoming tab lacks falls back to the tabs")
    func newItemStopIsDropped() {
        let betweenCollections = SelectionReducer.reduce(
            .init(tab: .collection("work"), focus: .topBar(.newItem)),
            .switchTabBackward, visibleIDs: [], tabs: tabs
        )
        #expect(betweenCollections.state.tab == .collection("personal"))
        #expect(betweenCollections.state.focus == .topBar(.newItem), "personal is a collection too")

        let ontoClipboard = SelectionReducer.reduce(
            .init(tab: .collection("prompts"), focus: .topBar(.newItem)),
            .switchTabBackward, visibleIDs: [], tabs: tabs
        )
        #expect(ontoClipboard.state.tab == .clipboard)
        #expect(ontoClipboard.state.focus == .tabs, "clipboard has no ＋ to stand on")
    }
}

@Suite("Tab band arrows")
struct TabBandTests {
    private let tabs: [PanelTab] = [.clipboard, .collection("prompts"), .collection("personal")]

    @Test("→ walks the tabs first, and only then reaches ＋ and ⚙")
    func arrowsSpendThemselvesOnTabs() {
        var s = SelectionReducer.State(tab: .clipboard, focus: .tabs)

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.tab == .collection("prompts"))
        #expect(s.focus == .tabs)

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.tab == .collection("personal"))

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.tab == .collection("personal"), "the last tab does not wrap")
        #expect(s.focus == .topBar(.newItem), "it steps on to the buttons instead")

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.focus == .topBar(.settings))
    }

    @Test("← from the first tab does nothing rather than wrapping onto the gear")
    func leftEdgeStops() {
        let s = SelectionReducer.reduce(
            .init(tab: .clipboard, focus: .tabs), .moveLeft, visibleIDs: [], tabs: tabs
        )
        #expect(s.state.tab == .clipboard)
        #expect(s.state.focus == .tabs)
    }
}

@Suite("reconcileTab")
struct ReconcileTabTests {
    /// The tab-level twin of `reconcile`. A selection pointing at a row that is
    /// gone is one keystroke from acting on the wrong thing; a `tab` pointing at
    /// a collection that is gone is that same sentence one dimension up.
    @Test("a deleted collection drops the panel back to clipboard")
    func deadTabFallsBack() {
        let s = SelectionReducer.reconcileTab(
            .init(
                selectedID: "x", query: "git", isSearching: true,
                tab: .collection("gone"), expandedID: "x", focus: .row(action: .delete)
            ),
            with: [.clipboard, .collection("prompts")]
        )
        #expect(s.tab == .clipboard)
        #expect(s.focus == .list)
        #expect(s.selectedID == nil)
        #expect(s.expandedID == nil)
        #expect(s.query.isEmpty)
        #expect(!s.isSearching, "the dead tab's search must not follow you")
    }

    @Test("someone standing in the band stays in the band")
    func bandSurvives() {
        let s = SelectionReducer.reconcileTab(
            .init(tab: .collection("gone"), focus: .topBar(.newItem)), with: [.clipboard]
        )
        #expect(s.tab == .clipboard)
        #expect(s.focus == .tabs, "ejecting someone out of the top bar is the SW-06 shape")
    }

    @Test("a live tab is left completely alone")
    func liveTabUntouched() {
        let original = SelectionReducer.State(
            selectedID: "x", query: "g", isSearching: true,
            tab: .collection("prompts"), focus: .list
        )
        #expect(
            SelectionReducer.reconcileTab(original, with: [.clipboard, .collection("prompts")])
                == original
        )
    }
}
