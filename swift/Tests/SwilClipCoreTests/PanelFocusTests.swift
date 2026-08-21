import Testing

@testable import SwilClipCore

/// Arrow-key navigation across the panel's two bands.
///
/// `SelectionReducerTests` covers the vertical axis and exists because of a
/// shipped bug. This suite covers the axis added on top of it, and it exists
/// for the same reason: a second way to reach "delete" is a second way to
/// delete the wrong thing, unless the two ways are provably one.
@Suite("PanelFocus")
struct PanelFocusTests {
    private let ids = ["a", "b", "c", "d"]
    /// A text clip's buttons.
    private let text: [RowAction] = [.pin, .promote, .expand, .delete]
    /// An image clip's — no text to promote, so one fewer.
    private let image: [RowAction] = [.pin, .expand, .delete]

    private func state(
        selected: String?,
        focus: PanelFocus = .list,
        tab: PanelTab = .clipboard,
        expanded: String? = nil,
        searching: Bool = false
    ) -> SelectionReducer.State {
        .init(
            selectedID: selected,
            isSearching: searching,
            tab: tab,
            expandedID: expanded,
            focus: focus
        )
    }

    private func reduce(
        _ state: SelectionReducer.State,
        _ command: KeyCommand,
        actions: [RowAction]? = nil
    ) -> SelectionReducer.Outcome {
        SelectionReducer.reduce(
            state, command, visibleIDs: ids, actions: actions ?? text
        )
    }

    // MARK: - The invariant this whole feature rests on

    /// Reaching an action by arrowing onto its button and pressing `⏎` must be
    /// *the same transition* as pressing its letter — same next state, same
    /// effect. If these ever diverge, the panel has grown a second, less-tested
    /// implementation of delete.
    @Test("⏎ on a focused button is identical to that button's shortcut")
    func returnMatchesTheShortcut() {
        for action in text {
            let armed = state(selected: "b", focus: .row(action: action))
            let viaReturn = reduce(armed, .confirm)
            // The letter path starts from the same state minus the focus, since
            // pressing `d` does not require having arrowed anywhere.
            let viaKey = reduce(armed, action.command)
            #expect(viaReturn.effect == viaKey.effect, "\(action) effect")
            #expect(viaReturn.state == viaKey.state, "\(action) state")
        }
    }

    /// The delete-wrong-row property, re-checked on the new path: the successor
    /// is chosen from the list as it stands *before* the row goes away.
    @Test("⏎ on the trash picks the successor before the removal")
    func deleteViaReturnResolvesSuccessorFirst() {
        let armed = state(selected: "b", focus: .row(action: .delete))
        let outcome = reduce(armed, .confirm)

        #expect(outcome.effect == .delete(id: "b"))
        #expect(outcome.state.selectedID == "c")
        // And it disarms, so a second `⏎` copies rather than deleting again.
        #expect(outcome.state.focus == .list)
    }

    @Test("deleting the last row falls back to its predecessor")
    func deleteViaReturnAtTheEnd() {
        let outcome = reduce(state(selected: "d", focus: .row(action: .delete)), .confirm)
        #expect(outcome.effect == .delete(id: "d"))
        #expect(outcome.state.selectedID == "c")
    }

    // MARK: - Focus travels by identity, never by position

    /// The reason ``PanelFocus`` stores a ``RowAction`` and not an index.
    ///
    /// "Save as prompt" is the second button on a text clip; the second button
    /// on an image clip is "expand". An index would slide focus silently from
    /// one to the other, and the next `⏎` would run something nobody aimed at.
    @Test("a button the new row does not carry drops focus back to the row")
    func focusDoesNotSlideOntoANeighbour() {
        let onPromote = state(selected: "b", focus: .row(action: .promote))
        let reconciled = SelectionReducer.reconcile(onPromote, with: ids, actions: image)
        #expect(reconciled.focus == .list)
        #expect(reconciled.selectedID == "b")
    }

    @Test("a button the row still carries survives reconciliation")
    func focusSurvivesWhenStillValid() {
        let onDelete = state(selected: "b", focus: .row(action: .delete))
        let reconciled = SelectionReducer.reconcile(onDelete, with: ids, actions: image)
        #expect(reconciled.focus == .row(action: .delete))
    }

    /// Belt to the braces above: even if a stale focus somehow reached the
    /// reducer, `⏎` refuses to run a button the row does not have.
    @Test("⏎ ignores a focused button the row does not carry")
    func returnIgnoresAnUnavailableButton() {
        let stale = state(selected: "b", focus: .row(action: .promote))
        let outcome = SelectionReducer.reduce(
            stale, .confirm, visibleIDs: ids, actions: image
        )
        // Falls through to the row's own meaning rather than promoting.
        #expect(outcome.effect == .confirm(id: "b"))
    }

    // MARK: - Horizontal movement inside a row

    @Test("→ enters the buttons, ← walks back out to the row")
    func steppingInAndOut() {
        var s = state(selected: "b")
        s = reduce(s, .moveRight).state
        #expect(s.focus == .row(action: .pin))
        s = reduce(s, .moveRight).state
        #expect(s.focus == .row(action: .promote))
        s = reduce(s, .moveLeft).state
        #expect(s.focus == .row(action: .pin))
        s = reduce(s, .moveLeft).state
        // Back on the row itself — `⏎` means copy again.
        #expect(s.focus == .list)
    }

    @Test("← on the row itself does nothing; there is nothing to its left")
    func leftFromTheRowIsInert() {
        let outcome = reduce(state(selected: "b"), .moveLeft)
        #expect(outcome.state.focus == .list)
        #expect(outcome.effect == nil)
    }

    @Test("→ stops at the last button rather than wrapping to the first")
    func doesNotWrapAroundTheCluster() {
        var s = state(selected: "b", focus: .row(action: .delete))
        s = reduce(s, .moveRight).state
        // Wrapping from delete back to pin is one stray keypress from a
        // deletion the user was trying to move away from.
        #expect(s.focus == .row(action: .delete))
    }

    @Test("arrows do nothing on a row with no buttons")
    func degradesOffWithoutActions() {
        let outcome = reduce(state(selected: "b"), .moveRight, actions: [])
        #expect(outcome.state.focus == .list)
    }

    @Test("arrows do nothing when the selection is stale")
    func inertWithoutAValidSelection() {
        #expect(reduce(state(selected: "gone"), .moveRight).state.focus == .list)
        #expect(reduce(state(selected: nil), .moveRight).state.focus == .list)
    }

    // MARK: - Vertical movement disarms

    /// Carrying a focused button down the list would leave `⏎` meaning "delete"
    /// several rows after the user last thought about deleting anything.
    @Test("↑ and ↓ always return to the row itself")
    func verticalMovementDisarms() {
        for command in [KeyCommand.moveDown, .moveUp, .moveToFirst, .moveToLast] {
            let armed = state(selected: "b", focus: .row(action: .delete))
            #expect(reduce(armed, command).state.focus == .list, "\(command)")
        }
    }

    @Test("pin and expand keep their focus — they are idempotent and stay put")
    func nonDestructiveActionsStayArmed() {
        let onPin = state(selected: "b", focus: .row(action: .pin))
        #expect(reduce(onPin, .confirm).state.focus == .row(action: .pin))

        let onExpand = state(selected: "b", focus: .row(action: .expand))
        #expect(reduce(onExpand, .confirm).state.focus == .row(action: .expand))
    }

    // MARK: - The tab band

    @Test("↑ from the first row reaches the tabs, and stops there")
    func reachesTheTabs() {
        var s = state(selected: "a")
        s = reduce(s, .moveUp).state
        #expect(s.focus == .tabs)
        #expect(s.selectedID == "a", "arriving at the tabs must not disturb the selection")

        // Nothing above the tab bar.
        s = reduce(s, .moveUp).state
        #expect(s.focus == .tabs)
    }

    @Test("↑ from a middle row moves up a row, not to the tabs")
    func onlyTheFirstRowLeaves() {
        let outcome = reduce(state(selected: "c"), .moveUp)
        #expect(outcome.state.focus == .list)
        #expect(outcome.state.selectedID == "b")
    }

    @Test("↓ and ⏎ both come back down, keeping the row that was selected")
    func returnsFromTheTabs() {
        for command in [KeyCommand.moveDown, .confirm] {
            let onTabs = state(selected: "c", focus: .tabs)
            let outcome = reduce(onTabs, command)
            #expect(outcome.state.focus == .list, "\(command)")
            #expect(outcome.state.selectedID == "c", "\(command) — the tabs are a detour, not a reset")
            #expect(outcome.effect == nil, "\(command) — coming back is navigation, not an action")
        }
    }

    @Test("↓ from the tabs adopts a row when there was no selection")
    func adoptsARowOnTheWayBack() {
        let outcome = reduce(state(selected: nil, focus: .tabs), .moveDown)
        #expect(outcome.state.selectedID == "a")
    }

    @Test("← and → switch tabs, and are inert at either end")
    func arrowsSwitchTabs() {
        let onClipboard = state(selected: "a", focus: .tabs, tab: .clipboard)

        let right = reduce(onClipboard, .moveRight)
        #expect(right.state.tab == .prompts)
        #expect(right.effect == .switchTab)
        #expect(right.state.focus == .tabs, "switching tabs must not drop out of the band")

        // Already as far left as it goes.
        let left = reduce(onClipboard, .moveLeft)
        #expect(left.state.tab == .clipboard)
        #expect(left.effect == nil)
    }

    @Test("⇥ still switches tabs, and drops any armed button")
    func tabKeyStillWorks() {
        let armed = state(selected: "b", focus: .row(action: .delete))
        let outcome = reduce(armed, .switchTab)
        #expect(outcome.state.tab == .prompts)
        #expect(outcome.effect == .switchTab)
        // The other tab's rows carry a pencil where these carry "save as prompt".
        #expect(outcome.state.focus == .list)
    }

    // MARK: - Escape, and clicks

    @Test("esc disarms a button before it touches anything else")
    func escapePeelsTheButtonFirst() {
        let armed = state(selected: "b", focus: .row(action: .delete), expanded: "b", searching: true)
        let outcome = reduce(armed, .dismiss)
        #expect(outcome.state.focus == .list)
        // Everything else is still standing — one layer per press.
        #expect(outcome.state.expandedID == "b")
        #expect(outcome.state.isSearching)
        #expect(outcome.effect == nil)
    }

    /// The tab bar is a place, not a mode. Someone who has arrowed up there
    /// still expects esc to close the panel rather than walk them back a step.
    @Test("esc on the tabs closes the panel")
    func escapeOnTheTabsClosesTheWindow() {
        let outcome = reduce(state(selected: "b", focus: .tabs), .dismiss)
        #expect(outcome.effect == .dismiss)
    }

    @Test("clicking a row disarms whatever the keyboard was on")
    func clickingResetsTheBand() {
        let armed = state(selected: "b", focus: .row(action: .delete))
        let outcome = reduce(armed, .selectID("d"))
        #expect(outcome.state.selectedID == "d")
        #expect(outcome.state.focus == .list)
    }

    // MARK: - Rows and the reducer agree by construction

    /// Both the row view and the reducer read `rowActions`. This checks the
    /// shape of what they share: a text clip promotes, an image does not, and a
    /// prompt edits.
    @Test("each row kind declares the buttons it actually draws")
    func rowActionsMatchTheRowKinds() {
        let textClip = ClipItem(kind: .text, preview: "hi", text: "hi")
        let imageClip = ClipItem(kind: .image, preview: "png", blobPath: "x")
        let prompt = PromptItem(title: "t", body: "b")

        #expect(textClip.rowActions == [.pin, .promote, .expand, .delete])
        #expect(imageClip.rowActions == [.pin, .expand, .delete])
        #expect(prompt.rowActions == [.pin, .edit, .expand, .delete])

        // Delete is last everywhere: the most destructive button should never
        // be one the user arrives at on the way to something else.
        for actions in [textClip.rowActions, imageClip.rowActions, prompt.rowActions] {
            #expect(actions.last == .delete)
            #expect(Set(actions).count == actions.count)
        }
    }

    @Test("every row action maps to a command the reducer understands")
    func everyActionIsRoutable() {
        for action in RowAction.allCases {
            let outcome = SelectionReducer.reduce(
                state(selected: "b"), action.command, visibleIDs: ids, actions: RowAction.allCases
            )
            #expect(outcome.effect != nil, "\(action) produced no effect")
        }
    }
}

@Suite("KeyMapping — arrows")
struct ArrowKeyMappingTests {
    private func map(_ keyCode: UInt16, modifiers: KeyModifiers = [], searching: Bool = false)
        -> KeyCommand?
    {
        KeyMapping.command(
            keyCode: keyCode,
            characters: nil,
            charactersIgnoringModifiers: nil,
            modifiers: modifiers,
            isSearching: searching
        )
    }

    @Test("left and right map to horizontal movement")
    func mapsBareArrows() {
        #expect(map(KeyCode.leftArrow) == .moveLeft)
        #expect(map(KeyCode.rightArrow) == .moveRight)
    }

    /// The query field has no editable caret — it is a `Text` and a blinking
    /// rectangle — so the arrows keep their meaning while searching rather than
    /// pretending to move a cursor that does not exist.
    @Test("they keep working while searching")
    func worksWhileSearching() {
        #expect(map(KeyCode.leftArrow, searching: true) == .moveLeft)
        #expect(map(KeyCode.rightArrow, searching: true) == .moveRight)
    }

    @Test("⌘← is left alone rather than aliased onto a step")
    func commandArrowsAreNotClaimed() {
        #expect(map(KeyCode.leftArrow, modifiers: .command) == nil)
        #expect(map(KeyCode.rightArrow, modifiers: .command) == nil)
    }

    @Test("the settings UI can print them on a keycap")
    func hasPrintableSymbols() {
        #expect(KeyCode.symbol(for: KeyCode.leftArrow) == "←")
        #expect(KeyCode.symbol(for: KeyCode.rightArrow) == "→")
    }
}

/// The tab handover, which is where the arrow-key feature first broke in a way
/// no reducer test could see: the app layer restored the incoming tab's stored
/// focus band and dropped the user out of the tab bar mid-gesture.
@Suite("SelectionReducer — tab handover")
struct TabHandoverTests {
    @Test("the focus band is panel-wide and rides across the switch")
    func bandSurvivesTheSwap() {
        let onTabs = SelectionReducer.State(selectedID: "a", tab: .clipboard, focus: .tabs)
        let stored = SelectionReducer.State(selectedID: "p1", tab: .prompts, focus: .list)

        let (_, adopted) = SelectionReducer.swapTab(
            current: onTabs, incoming: stored, from: .clipboard
        )
        // Still on the tab bar — otherwise the very next ⏎ copies a row and
        // closes the panel instead of entering the tab you just arrowed to.
        #expect(adopted.focus == .tabs)
        #expect(adopted.tab == .prompts)
        #expect(adopted.selectedID == "p1", "the cursor is still per tab")
    }

    @Test("selection, query and expansion stay with the tab they belong to")
    func cursorStaysPerTab() {
        let clipboard = SelectionReducer.State(
            selectedID: "a", query: "abc", isSearching: true, tab: .clipboard, expandedID: "a"
        )
        let prompts = SelectionReducer.State(selectedID: "p2", tab: .prompts)

        let (outgoing, adopted) = SelectionReducer.swapTab(
            current: clipboard, incoming: prompts, from: .clipboard
        )
        // Filed away intact, so coming back resumes the search.
        #expect(outgoing.tab == .clipboard)
        #expect(outgoing.query == "abc")
        #expect(outgoing.isSearching)
        #expect(outgoing.expandedID == "a")
        // And the incoming tab is not wearing the outgoing one's search.
        #expect(adopted.query.isEmpty)
        #expect(!adopted.isSearching)
        #expect(adopted.expandedID == nil)
    }

    @Test("switching back and forth is a round trip")
    func roundTrips() {
        var clipboard = SelectionReducer.State(selectedID: "a", query: "x", isSearching: true, tab: .clipboard)
        var prompts = SelectionReducer.State(selectedID: "p1", tab: .prompts)

        let out = SelectionReducer.swapTab(current: clipboard, incoming: prompts, from: .clipboard)
        clipboard = out.outgoing
        let back = SelectionReducer.swapTab(current: out.adopted, incoming: clipboard, from: .prompts)
        prompts = back.outgoing

        #expect(back.adopted.selectedID == "a")
        #expect(back.adopted.query == "x")
        #expect(back.adopted.isSearching)
        #expect(back.adopted.tab == .clipboard)
        #expect(prompts.selectedID == "p1")
    }
}

/// The prompts tab's own cluster. `.edit` is the one action with no letter
/// shortcut, so the arrow route is its *only* keyboard route — which makes it
/// the one most worth pinning.
@Suite("PanelFocus — prompt rows")
struct PromptRowFocusTests {
    private let ids = ["p1", "p2"]
    private let actions: [RowAction] = [.pin, .edit, .expand, .delete]

    @Test("⏎ on the pencil opens the editor instead of copying")
    func returnOnThePencilEdits() {
        let armed = SelectionReducer.State(
            selectedID: "p1", tab: .prompts, focus: .row(action: .edit)
        )
        let outcome = SelectionReducer.reduce(
            armed, .confirm, visibleIDs: ids, actions: actions
        )
        #expect(outcome.effect == .edit(id: "p1"))
        #expect(outcome.state.focus == .row(action: .edit), "the editor closing returns you here")
    }

    @Test("two rights from a prompt row land on the pencil")
    func twoRightsReachThePencil() {
        var s = SelectionReducer.State(selectedID: "p1", tab: .prompts)
        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: ids, actions: actions).state
        #expect(s.focus == .row(action: .pin))
        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: ids, actions: actions).state
        #expect(s.focus == .row(action: .edit))
    }
}

/// Reconciliation runs after every refresh, and it is handed the buttons of the
/// row the cursor was on *before* it ran. When it moves the cursor, that array
/// is describing the wrong row — so the focus cannot be trusted against it.
@Suite("PanelFocus — reconciliation order")
struct FocusReconciliationTests {
    private let actions: [RowAction] = [.pin, .promote, .expand, .delete]

    @Test("a cursor that gets moved takes any focused button with it")
    func movingTheCursorDropsTheButton() {
        // "b" is gone; the cursor lands on "a". `actions` still describes "b",
        // so agreeing with it would leave the ring on a row nobody chose.
        let armed = SelectionReducer.State(selectedID: "b", focus: .row(action: .delete))
        let next = SelectionReducer.reconcile(armed, with: ["a", "c"], actions: actions)
        #expect(next.selectedID == "a")
        #expect(next.focus == .list)
    }

    @Test("a cursor that stays put keeps a button the row still carries")
    func stayingPutKeepsTheButton() {
        let armed = SelectionReducer.State(selectedID: "b", focus: .row(action: .delete))
        let next = SelectionReducer.reconcile(armed, with: ["a", "b"], actions: actions)
        #expect(next.selectedID == "b")
        #expect(next.focus == .row(action: .delete))
    }

    @Test("adopting a first row from nothing does not inherit a stale button")
    func adoptingARowDropsTheButton() {
        let armed = SelectionReducer.State(selectedID: nil, focus: .row(action: .delete))
        let next = SelectionReducer.reconcile(armed, with: ["a"], actions: actions)
        #expect(next.selectedID == "a")
        #expect(next.focus == .list)
    }

    @Test("the tab band is not a row focus and survives reconciliation")
    func theTabBandIsUntouched() {
        let onTabs = SelectionReducer.State(selectedID: "b", focus: .tabs)
        let next = SelectionReducer.reconcile(onTabs, with: ["a", "c"], actions: actions)
        #expect(next.focus == .tabs, "moving the cursor underneath must not eject you from the tabs")
    }
}

/// The top bar is a band with stops, not just two tabs. `+` and the gear were
/// previously reachable only by `n` and by mouse respectively.
@Suite("PanelFocus — top bar")
struct TopBarFocusTests {
    private let ids = ["a", "b"]

    private func reduce(
        _ state: SelectionReducer.State, _ command: KeyCommand
    ) -> SelectionReducer.Outcome {
        SelectionReducer.reduce(state, command, visibleIDs: ids, actions: [.pin, .expand, .delete])
    }

    private func onBar(_ item: TopBarItem, tab: PanelTab) -> SelectionReducer.State {
        .init(selectedID: "a", tab: tab, focus: .topBar(item))
    }

    @Test("+ exists on Prompts and nowhere else")
    func plusIsPromptsOnly() {
        #expect(PanelTab.prompts.topBarItems == [.tabs, .newPrompt, .settings])
        // A plus next to "Clipboard" would read as "add a clip".
        #expect(PanelTab.clipboard.topBarItems == [.tabs, .settings])
        // The tabs are the one stop that is always present, so arriving in the
        // bar always has somewhere to land.
        for tab in PanelTab.allCases { #expect(tab.topBarItems.first == .tabs) }
    }

    /// The arrows spend themselves on switching tabs first, so flipping between
    /// the two lists stays a single key — and you cannot land on `+` while
    /// looking at the clipboard.
    @Test("→ switches tabs before it steps off them")
    func tabsAbsorbTheFirstStep() {
        let first = reduce(onBar(.tabs, tab: .clipboard), .moveRight)
        #expect(first.state.tab == .prompts)
        #expect(first.effect == .switchTab)
        #expect(first.state.focus == .tabs, "still on the tabs, just the other one")

        let second = reduce(onBar(.tabs, tab: .prompts), .moveRight)
        #expect(second.state.tab == .prompts, "no tab left to switch to")
        #expect(second.state.focus == .topBar(.newPrompt))
        #expect(second.effect == nil)
    }

    @Test("the bar walks to the gear and stops at the end")
    func walksToTheGearAndStops() {
        var s = onBar(.newPrompt, tab: .prompts)
        s = reduce(s, .moveRight).state
        #expect(s.focus == .topBar(.settings))
        s = reduce(s, .moveRight).state
        #expect(s.focus == .topBar(.settings), "nothing past the gear")
        s = reduce(s, .moveLeft).state
        #expect(s.focus == .topBar(.newPrompt))
    }

    @Test("on Clipboard the gear is one step past the tabs")
    func clipboardSkipsThePlus() {
        var s = onBar(.tabs, tab: .prompts)
        // ← switches back to Clipboard...
        s = reduce(s, .moveLeft).state
        #expect(s.tab == .clipboard)
        // ...and from there → returns to Prompts rather than reaching the gear,
        // because the tabs always absorb the first step.
        #expect(reduce(s, .moveRight).state.tab == .prompts)
    }

    @Test("⏎ activates whichever stop it is on")
    func enterActivatesTheStop() {
        #expect(reduce(onBar(.newPrompt, tab: .prompts), .confirm).effect == .newPrompt)
        #expect(reduce(onBar(.settings, tab: .prompts), .confirm).effect == .openSettings)
        // The tabs are the exception: `⏎` there means "go into this list".
        let tabs = reduce(onBar(.tabs, tab: .prompts), .confirm)
        #expect(tabs.effect == nil)
        #expect(tabs.state.focus == .list)
    }

    @Test("↓ leaves the bar from any stop")
    func downLeavesFromAnywhere() {
        for item in TopBarItem.allCases {
            let outcome = reduce(onBar(item, tab: .prompts), .moveDown)
            #expect(outcome.state.focus == .list, "\(item)")
            #expect(outcome.state.selectedID == "a", "\(item) — leaving the bar is not a reset")
        }
    }

    @Test("↑ from the bar has nowhere to go")
    func nothingAboveTheBar() {
        for item in TopBarItem.allCases {
            #expect(reduce(onBar(item, tab: .prompts), .moveUp).state.focus == .topBar(item))
        }
    }

    /// `+` vanishes when the tab changes under a focus that was sitting on it —
    /// the bar's version of "a button the row does not carry".
    @Test("a stop the new tab lacks falls back to the tabs")
    func stopsClampOnTabChange() {
        let onPlus = onBar(.newPrompt, tab: .prompts)
        #expect(reduce(onPlus, .switchTab).state.focus == .tabs)

        var stale = onPlus
        stale.tab = .clipboard
        #expect(SelectionReducer.reconcile(stale, with: ids).focus == .tabs)
    }

    @Test("the gear survives a tab change; it exists on both")
    func theGearIsAlwaysThere() {
        #expect(reduce(onBar(.settings, tab: .prompts), .switchTab).state.focus == .topBar(.settings))
    }
}
