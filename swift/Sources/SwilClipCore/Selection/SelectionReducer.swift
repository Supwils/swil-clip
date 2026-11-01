import Foundation

/// Everything the panel's keyboard layer can be asked to do, as data.
///
/// Producing these is the AppKit adapter's only job; deciding what they mean is
/// this file's only job. That split is what lets the entire keyboard model be
/// tested without a window server.
public enum KeyCommand: Equatable, Sendable {
    case moveUp
    case moveDown
    case moveToFirst
    case moveToLast
    /// `←` / `→`. In the tab bar they change tab; on a row they step through
    /// its buttons.
    case moveLeft
    case moveRight
    case beginSearch
    case appendToQuery(String)
    case deleteQueryCharacter
    case switchTab
    /// `⇧` plus the switch binding. A separate case rather than a payload on
    /// ``switchTab``, so the existing `.switchTab` literals in the regression
    /// suite keep compiling and ``documentedAction`` stays flat.
    case switchTabBackward
    case confirm
    case deleteItem
    case togglePin
    case toggleExpand
    case undo
    case newItem
    case promoteToPrompt
    /// Open the editor for the selected prompt. Reachable only through a
    /// focused pencil button — there is no letter for it, because `e` was
    /// already expand and rebinding a shipped key is worse than one more arrow.
    case editPrompt
    /// `⇧E`: edit the selected row's text right inside its expansion. The
    /// shifted twin of `e`, the way `⇧S` is the shifted twin of `s` — so it
    /// costs no letter from type-to-find.
    case editInline
    /// `⇧↑` / `⇧↓`: scroll the expanded row's contents, in lines. A long prompt
    /// used to expand past the panel and then be readable only in the editor.
    case scrollExpansion(lines: Int)
    case dismiss
    /// Mouse click. Assistive only — never emitted by hover.
    case selectID(String)
}

/// A side effect the host must carry out. The reducer never performs one; it
/// only says which is due, so "what happens when you press `d` on the last row
/// while filtered" is an assertion rather than a race.
public enum SelectionEffect: Equatable, Sendable {
    case confirm(id: String)
    case delete(id: String)
    case togglePin(id: String)
    case toggleExpand(id: String)
    case undo
    case newItem
    case promote(id: String)
    case edit(id: String)
    /// Hand the expanded row to the inline editor. The host decides whether the
    /// row has text to edit; the reducer only knows ids.
    case editInline(id: String)
    /// Scroll the expanded row by this many lines. Purely visual: the view owns
    /// the scroll offset, because it is the only one that knows the layout.
    case scrollExpansion(id: String, lines: Int)
    /// Open the preferences sheet. Reachable from the gear in the top bar,
    /// by mouse or by arrowing onto it.
    case openSettings
    case switchTab
    case dismiss
}

/// Which list the panel is showing.
///
/// ## Why this stays an enum
///
/// Flattening it to a bare id would make Clipboard just another string, and
/// Clipboard genuinely is not: it lives in another table, the pasteboard poller
/// writes it, it evicts, and it is read-only. That is the one special case worth
/// having in the type system — and putting it there is what lets
/// ``topBarItems`` stop asking *which tab is this* and start asking *what kind
/// of tab is this*.
///
/// The consequence is that this is no longer `CaseIterable`: the set of tabs is
/// runtime data. So ``SelectionReducer`` is *told* it, exactly as it is already
/// told `visibleIDs` and `actions`.
public enum PanelTab: Hashable, Sendable {
    case clipboard
    case collection(String)

    /// Stable string form, for `UserDefaults` keys and undo entries.
    public var storageKey: String {
        switch self {
        case .clipboard: "clipboard"
        case .collection(let id): "collection:\(id)"
        }
    }

    public var collectionID: String? {
        if case .collection(let id) = self { return id }
        return nil
    }
}

/// The one and only place a selection lives.
///
/// ## Why this type exists
///
/// v1's worst shipped bug deleted the wrong row. The cause was structural:
/// `cmdk` kept a private copy of the selection and rewrote it when the selected
/// element unmounted, outside React's knowledge. Two sources of truth, one of
/// them invisible.
///
/// v2 has no `cmdk`, so that particular mechanism is gone — but "the framework
/// can't do it to us any more" is luck, not design. Selection is therefore a
/// value, transitions are a pure function over it, and views may read it but
/// never write it.
public enum SelectionReducer {
    public struct State: Equatable, Sendable {
        public var selectedID: String?
        public var query: String
        public var isSearching: Bool
        public var tab: PanelTab
        public var expandedID: String?
        /// Which band of the panel the keyboard is in, and which button inside
        /// a row. Lives here rather than in a view for the same reason
        /// `selectedID` does: it decides what `⏎` does, so a second copy of it
        /// is a second chance to act on the wrong thing.
        public var focus: PanelFocus

        public init(
            selectedID: String? = nil,
            query: String = "",
            isSearching: Bool = false,
            tab: PanelTab = .clipboard,
            expandedID: String? = nil,
            focus: PanelFocus = .list
        ) {
            self.selectedID = selectedID
            self.query = query
            self.isSearching = isSearching
            self.tab = tab
            self.expandedID = expandedID
            self.focus = focus
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var state: State
        public var effect: SelectionEffect?

        public init(state: State, effect: SelectionEffect? = nil) {
            self.state = state
            self.effect = effect
        }
    }

    // MARK: - Transition

    /// `visibleIDs` is the list *as currently rendered* — already filtered by the
    /// query. Passing the unfiltered list is the mistake that reintroduces the
    /// v1 bug, so the reducer never filters: it only ever moves within what the
    /// user can actually see.
    ///
    /// `actions` is the same promise one axis over: the buttons the *selected
    /// row is currently drawing*, in render order. The rows are generated from
    /// this list too (see ``RowAction``), so neither side has to count. Left
    /// empty, `←`/`→` simply do nothing on a row — the feature degrades off
    /// rather than pointing somewhere wrong.
    /// - Parameter tabs: the tabs the bar is *currently drawing*, in order.
    ///   The third member of the promise `visibleIDs` and `actions` already
    ///   make: this function never assumes what is on screen, it is told. The
    ///   default of a lone clipboard is what keeps every pre-existing call site
    ///   compiling, and it degrades the feature *off* rather than pointing it
    ///   somewhere wrong.
    public static func reduce(
        _ state: State,
        _ command: KeyCommand,
        visibleIDs: [String],
        actions: [RowAction] = [],
        tabs: [PanelTab] = [.clipboard]
    ) -> Outcome {
        var next = state

        switch command {
        case .moveUp:
            // Nothing sits above the top bar.
            guard !state.focus.isOnTopBar else { return Outcome(state: next) }
            // Vertical movement always returns to the row itself. Carrying a
            // focused button down the list would leave `⏎` meaning "delete"
            // several rows after the user last thought about deleting.
            next.focus = .list
            guard let selected = state.selectedID else {
                // Nothing selected yet: `↑` still adopts the last row, which it
                // has always done. Only a cursor that is *already* on the first
                // row has run out of list and should leave it.
                next.selectedID = neighbour(of: nil, in: visibleIDs, offset: -1)
                if next.selectedID == nil { next.focus = .tabs }
                return Outcome(state: next)
            }
            guard selected != visibleIDs.first else {
                // From the first row — or an empty list — `↑` reaches the tabs.
                // That is the point of the band model: every part of the panel
                // is arrow-reachable, with no chord to remember.
                next.focus = .tabs
                return Outcome(state: next)
            }
            next.selectedID = neighbour(of: selected, in: visibleIDs, offset: -1)
            return Outcome(state: next)

        case .moveDown:
            next.focus = .list
            guard !state.focus.isOnTopBar else {
                // Coming back down keeps whatever row was selected rather than
                // snapping to the top: the tab bar is a detour, not a reset.
                if next.selectedID == nil { next.selectedID = visibleIDs.first }
                return Outcome(state: next)
            }
            next.selectedID = neighbour(of: state.selectedID, in: visibleIDs, offset: +1)
            return Outcome(state: next)

        case .moveToFirst:
            next.focus = .list
            next.selectedID = visibleIDs.first
            return Outcome(state: next)

        case .moveToLast:
            next.focus = .list
            next.selectedID = visibleIDs.last
            return Outcome(state: next)

        case .moveLeft:
            return step(next, -1, visibleIDs: visibleIDs, actions: actions, tabs: tabs)

        case .moveRight:
            return step(next, +1, visibleIDs: visibleIDs, actions: actions, tabs: tabs)

        case .beginSearch:
            next.isSearching = true
            return Outcome(state: next)

        case .appendToQuery(let fragment):
            next.isSearching = true
            next.query += fragment
            return Outcome(state: next)

        case .deleteQueryCharacter:
            guard !next.query.isEmpty else {
                // Backspace on an empty query leaves search rather than doing
                // nothing — the only way out that does not need the mouse.
                next.isSearching = false
                return Outcome(state: next)
            }
            next.query.removeLast()
            return Outcome(state: next)

        case .switchTab:
            return cycleTab(next, offset: +1, tabs: tabs)

        case .switchTabBackward:
            return cycleTab(next, offset: -1, tabs: tabs)

        case .confirm:
            if let item = state.focus.topBarItem {
                switch item {
                case .tabs:
                    // On the tabs, `⏎` means "go into this list" — the tab has
                    // already changed, live, under the arrow keys.
                    next.focus = .list
                    if next.selectedID == nil { next.selectedID = visibleIDs.first }
                    return Outcome(state: next)
                case .newItem:
                    return Outcome(state: next, effect: .newItem)
                case .settings:
                    return Outcome(state: next, effect: .openSettings)
                }
            }
            if let action = state.focus.focusedAction, actions.contains(action) {
                // Not a second implementation of delete — the same one, reached
                // a second way. Recursing is what guarantees `⏎` on the trash
                // icon and `d` cannot drift apart, including the part where the
                // successor is chosen before the row goes away.
                return reduce(
                    state, action.command,
                    visibleIDs: visibleIDs, actions: actions, tabs: tabs
                )
            }
            guard let id = state.selectedID, visibleIDs.contains(id) else {
                return Outcome(state: next)
            }
            return Outcome(state: next, effect: .confirm(id: id))

        case .deleteItem:
            guard let id = state.selectedID, visibleIDs.contains(id) else {
                return Outcome(state: next)
            }
            // Resolve the successor here, while the pre-removal list is still in
            // hand. Deciding afterwards is precisely what went wrong in v1.
            next.selectedID = selectionAfterRemoval(of: id, from: visibleIDs)
            if next.expandedID == id { next.expandedID = nil }
            // The only action that changes *which* row is selected, so the only
            // one that must drop the button focus: the row underneath may not
            // carry the same buttons, and leaving `⏎` armed as "delete" over a
            // row the user has not looked at yet is how runs of data disappear.
            // Pin and expand keep their focus — they are idempotent and stay put.
            next.focus = .list
            return Outcome(state: next, effect: .delete(id: id))

        case .togglePin:
            guard let id = state.selectedID, visibleIDs.contains(id) else {
                return Outcome(state: next)
            }
            return Outcome(state: next, effect: .togglePin(id: id))

        case .toggleExpand:
            guard let id = state.selectedID, visibleIDs.contains(id) else {
                return Outcome(state: next)
            }
            next.expandedID = state.expandedID == id ? nil : id
            return Outcome(state: next, effect: .toggleExpand(id: id))

        case .undo:
            return Outcome(state: next, effect: .undo)

        case .newItem:
            return Outcome(state: next, effect: .newItem)

        case .promoteToPrompt:
            guard let id = state.selectedID, visibleIDs.contains(id) else {
                return Outcome(state: next)
            }
            return Outcome(state: next, effect: .promote(id: id))

        case .editPrompt:
            guard let id = state.selectedID, visibleIDs.contains(id) else {
                return Outcome(state: next)
            }
            return Outcome(state: next, effect: .edit(id: id))

        case .editInline:
            guard let id = state.selectedID, visibleIDs.contains(id) else {
                return Outcome(state: next)
            }
            // The editor lives inside the expansion, so asking to edit a
            // collapsed row opens it. And it is never a toggle: `⇧E` on an
            // expanded row must not be the key that hides it.
            next.expandedID = id
            next.focus = .list
            return Outcome(state: next, effect: .editInline(id: id))

        case .scrollExpansion(let lines):
            guard let id = state.selectedID, id == state.expandedID, visibleIDs.contains(id),
                  !state.focus.isOnTopBar
            else {
                // Nothing open to scroll, so the shifted arrow is just an arrow.
                // Holding ⇧ out of habit must not freeze the list.
                return reduce(
                    state, lines < 0 ? .moveUp : .moveDown,
                    visibleIDs: visibleIDs, actions: actions, tabs: tabs
                )
            }
            return Outcome(state: next, effect: .scrollExpansion(id: id, lines: lines))

        case .dismiss:
            if state.focus.focusedAction != nil {
                // A focused button is a mode, and Esc leaves modes. The tab bar
                // is deliberately *not* one: it is a place, and someone who has
                // arrowed up there still expects Esc to close the panel rather
                // than to walk them back a step.
                next.focus = .list
                return Outcome(state: next)
            }
            if state.expandedID != nil {
                // Esc peels one layer at a time: collapse, then leave search,
                // then close. Closing the panel on the first Esc while a row is
                // expanded loses context the user just asked for.
                next.expandedID = nil
                return Outcome(state: next)
            }
            if state.isSearching {
                next.isSearching = false
                next.query = ""
                return Outcome(state: next)
            }
            return Outcome(state: next, effect: .dismiss)

        case .selectID(let id):
            guard visibleIDs.contains(id) else { return Outcome(state: next) }
            next.selectedID = id
            next.focus = .list
            return Outcome(state: next)
        }
    }

    /// `←` / `→` along the top bar.
    ///
    /// The tabs are one stop with two states, so the arrows spend themselves on
    /// switching tabs before they carry you out of them: from Clipboard, `→`
    /// lights Prompts; only a second `→` steps on to `+`. That keeps the
    /// commonest gesture — flipping between the two lists — a single key, and
    /// it means you cannot land on `+` while looking at the clipboard.
    private static func stepTopBar(
        _ state: State, _ offset: Int, from item: TopBarItem, tabs: [PanelTab]
    ) -> Outcome {
        var next = state
        let stops = state.tab.topBarItems

        if item == .tabs, let index = tabs.firstIndex(of: state.tab) {
            let target = index + offset
            if tabs.indices.contains(target) {
                next.tab = tabs[target]
                return Outcome(state: next, effect: .switchTab)
            }
            // Ran off the end of the tab group; fall through to the bar's other
            // stops. Deliberately *not* wrapping even though `⇥` does: these
            // arrows have somewhere else to go, and wrapping from the last tab
            // back to the first would make `＋` and `⚙` unreachable by arrow.
        }

        guard let index = stops.firstIndex(of: item) else {
            // A stop this tab does not have; the tabs are always present.
            next.focus = .tabs
            return Outcome(state: next)
        }
        let target = index + offset
        guard stops.indices.contains(target) else { return Outcome(state: next) }
        next.focus = .topBar(stops[target])
        return Outcome(state: next)
    }

    // MARK: - Tab handover

    /// Hand the panel over to the other tab.
    ///
    /// Each tab remembers its own cursor and query, so returning to one does
    /// not silently reset what you were doing there. The focus *band* is the
    /// exception, and the distinction is worth stating because getting it wrong
    /// is invisible until it bites:
    ///
    /// - **Per tab** — `selectedID`, `query`, `isSearching`, `expandedID`. They
    ///   describe a place in a list, and the other tab has a different list.
    /// - **Panel-wide** — ``PanelFocus``. It describes where the *keyboard* is.
    ///   Someone arrowing across the tab bar is still on the tab bar afterwards;
    ///   restoring the incoming tab's stored band drops them into the list
    ///   mid-gesture, and the next `⏎` copies a row and closes the panel instead
    ///   of entering the tab. That shipped for exactly one build.
    ///
    /// The row-level half of the band is still dropped by ``reduce`` on a tab
    /// switch, because the other tab's rows carry different buttons.
    ///
    /// - Returns: the state to file under `previousTab`, and the state to adopt.
    /// - Parameter targetTab: where the panel is going. This used to be derived
    ///   by negating a two-case enum; with an open list it has to be said.
    public static func swapTab(
        current: State,
        incoming: State,
        from previousTab: PanelTab,
        to targetTab: PanelTab
    ) -> (outgoing: State, adopted: State) {
        var outgoing = current
        outgoing.tab = previousTab

        var adopted = incoming
        adopted.tab = targetTab
        adopted.focus = current.focus
        return (outgoing, adopted)
    }

    /// Re-anchor the *tab* against the tabs that actually exist.
    ///
    /// Deleting a collection deletes a tab, so this is ``reconcile(_:with:actions:)``
    /// one dimension up: a `tab` pointing at a collection that is gone is the
    /// state from which "acted on the wrong list" is one keystroke away.
    ///
    /// List-scoped fields are cleared because they described the dead tab. The
    /// host may overlay the destination tab's parked state afterwards; this
    /// function has no parking of its own, so it leaves a clean slate rather
    /// than a stale one.
    public static func reconcileTab(_ state: State, with tabs: [PanelTab]) -> State {
        var next = state
        guard !tabs.contains(state.tab) else {
            if let item = next.focus.topBarItem, !next.tab.topBarItems.contains(item) {
                next.focus = .tabs
            }
            return next
        }
        next.tab = tabs.first ?? .clipboard
        // Only the band survives, and only as the band. Ejecting someone out of
        // the top bar because a background change removed a tab is the SW-06
        // failure wearing a different hat.
        next.focus = next.focus.isOnTopBar ? .tabs : .list
        next.selectedID = nil
        next.expandedID = nil
        next.query = ""
        next.isSearching = false
        return next
    }

    /// `⇥` / `⇧⇥`: step through the tab ring.
    ///
    /// **Wrapping, unlike the list.** ``neighbour(of:in:offset:)`` refuses to
    /// wrap because a history list is unbounded and both of its ends are
    /// off-screen. A tab bar is at most six stops and every one of them is
    /// drawn. Wrapping is safe exactly when the boundary is visible.
    ///
    /// A one-tab panel emits **no effect**: the host treats `.switchTab` as a
    /// state handover, and handing a tab's state over to itself would park and
    /// re-adopt the same value for nothing.
    private static func cycleTab(_ state: State, offset: Int, tabs: [PanelTab]) -> Outcome {
        var next = state
        guard tabs.count > 1, let index = tabs.firstIndex(of: state.tab) else {
            return Outcome(state: next)
        }
        next.tab = tabs[(index + offset + tabs.count) % tabs.count]
        // The other tab's rows carry different buttons — a library entry has a
        // pencil where a clip has "save as prompt".
        if case .row = state.focus { next.focus = .list }
        // And its bar may have different stops: `＋` exists only on collections.
        if let item = state.focus.topBarItem, !next.tab.topBarItems.contains(item) {
            next.focus = .tabs
        }
        // Each tab owns its own selection and query; the host restores them.
        return Outcome(state: next, effect: .switchTab)
    }

    // MARK: - Reconciliation

    /// Where the selection lands after `id` disappears.
    ///
    /// The row that slid up into the vacated position, or the new last row if
    /// the deleted one was at the end. This is what makes holding `d` delete a
    /// run of entries instead of one entry and then nothing.
    public static func selectionAfterRemoval(of id: String, from ids: [String]) -> String? {
        guard let index = ids.firstIndex(of: id) else { return ids.first }
        var remaining = ids
        remaining.remove(at: index)
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }

    /// Re-anchor a selection against a list that changed underneath it —
    /// a new clip arriving, a filter narrowing, a background refresh.
    ///
    /// A selection pointing at a row that no longer exists is the state from
    /// which every "acted on the wrong row" bug is one keystroke away, so it is
    /// never allowed to persist.
    public static func reconcile(
        _ state: State,
        with visibleIDs: [String],
        actions: [RowAction] = []
    ) -> State {
        var next = state
        if next.expandedID.map({ !visibleIDs.contains($0) }) ?? false {
            next.expandedID = nil
        }

        let before = next.selectedID
        if let selected = next.selectedID, !visibleIDs.contains(selected) {
            next.selectedID = visibleIDs.first
        } else if next.selectedID == nil {
            next.selectedID = visibleIDs.first
        }

        // The horizontal twin of the rule above: a focused button that is not
        // on the row under the cursor is one `⏎` away from acting on something
        // that is not there.
        //
        // The order matters. `actions` describes the row as it was *before* this
        // call — the caller could not have known where the selection was about
        // to land. So if the cursor moved, the focus belonged to the old row and
        // goes regardless of what `actions` says; only when the cursor held
        // still is `actions` a statement about the right row.
        // Only ever a *row* focus: the tab band is not attached to a row, and a
        // background refresh moving the cursor underneath must not eject
        // someone out of the tab bar mid-gesture.
        if let action = next.focus.focusedAction,
           next.selectedID != before || !actions.contains(action) {
            next.focus = .list
        }
        // The bar's own version of the same rule: `+` exists only on Prompts,
        // so a focus left on it after a tab change points at nothing.
        if let item = next.focus.topBarItem, !next.tab.topBarItems.contains(item) {
            next.focus = .tabs
        }
        return next
    }

    // MARK: - Horizontal movement

    /// `←` / `→`, which mean different things in the two bands.
    private static func step(
        _ state: State,
        _ offset: Int,
        visibleIDs: [String],
        actions: [RowAction],
        tabs: [PanelTab]
    ) -> Outcome {
        var next = state

        if let item = state.focus.topBarItem {
            return stepTopBar(next, offset, from: item, tabs: tabs)
        }

        guard let selected = state.selectedID, visibleIDs.contains(selected), !actions.isEmpty
        else { return Outcome(state: next) }

        guard let current = state.focus.focusedAction.flatMap(actions.firstIndex(of:)) else {
            // From the row itself: `→` lands on the first button, `←` does
            // nothing — there is nothing to the left of the preview text.
            if offset > 0 { next.focus = .row(action: actions.first) }
            return Outcome(state: next)
        }

        let target = current + offset
        if target < 0 {
            // Walking off the left end returns to the row. That is the way back
            // out, and it means `⏎` is never more than a few `←` from meaning
            // "copy" again.
            next.focus = .list
        } else if actions.indices.contains(target) {
            next.focus = .row(action: actions[target])
        }
        // Walking off the right end stops: a button row is not a carousel, and
        // wrapping from "delete" back to "pin" invites exactly one bad press.
        return Outcome(state: next)
    }

    // MARK: - Helpers

    /// Step through the list without wrapping.
    ///
    /// Wrapping is wrong here: the list is ordered by recency, and jumping from
    /// the newest entry to the oldest on one `↑` is never what was meant.
    private static func neighbour(of id: String?, in ids: [String], offset: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let id, let index = ids.firstIndex(of: id) else {
            return offset > 0 ? ids.first : ids.last
        }
        let target = index + offset
        guard ids.indices.contains(target) else { return id }
        return ids[target]
    }
}
