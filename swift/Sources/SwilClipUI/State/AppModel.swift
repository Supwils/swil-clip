import Foundation
import Observation
import SwilClipCore

/// The panel's state, and the only place effects are carried out.
///
/// Views read this and emit ``KeyCommand``s. They never mutate selection — that
/// belongs to ``SelectionReducer``, and keeping the rule absolute is what makes
/// the v1 delete-wrong-row bug structurally impossible rather than merely fixed.
///
/// ## Responsiveness
///
/// Everything the panel draws is already in memory. Opening it, moving the
/// cursor and typing a query never touch SQLite, so none of them can be slower
/// than a frame. Writes go to the store actor and the UI updates optimistically;
/// a failed write refreshes from disk rather than leaving a lie on screen.
@MainActor
@Observable
final class AppModel {
    // MARK: - Data

    private(set) var clips: [ClipItem] = []
    private(set) var collections: [LibraryCollection] = []
    /// Every library entry across every collection.
    ///
    /// Tens of entries of a few hundred characters, so one array filtered per
    /// render beats a dictionary that has to be kept in step with
    /// ``collections``.
    private(set) var entries: [LibraryEntry] = []
    /// Set when something the user should know about went wrong. Surfaced in the
    /// footer rather than a modal — a clipboard manager must never block.
    private(set) var statusMessage: String?
    /// Clears ``statusMessage`` on its own. Held so a new message cancels the
    /// previous countdown instead of inheriting its remaining time.
    private var statusDismissTask: Task<Void, Never>?

    /// How long a status line stays up.
    ///
    /// Long enough to read a short sentence, short enough that it is gone before
    /// you next need the row it covers. The footer is a shared surface: the
    /// keyboard hints live there too, and they are what the panel is for.
    private static let statusLifetime = Duration.seconds(3)

    var selection = SelectionReducer.State()

    /// Bumped whenever the list re-sorts under a selection that did not change.
    ///
    /// Pin and unpin move a row without changing its id, so the view's
    /// `onChange(of: selectedID)` never fires — and the selected row can end up
    /// far outside the viewport with nothing to bring it back. This token is the
    /// missing signal: the list watches it and re-anchors the scroll.
    private(set) var reorderToken = 0

    /// Per-tab cursor, query and expansion, so returning to a tab does not
    /// silently reset what you were doing there.
    ///
    /// Keyed by tab and **pruned whenever the tab list changes**: an entry left
    /// behind for a deleted collection would hand a recreated id someone else's
    /// cursor, which is the delete-wrong-row failure one dimension up.
    private var parked: [PanelTab: SelectionReducer.State] = [:]

    /// Test-only view of the parking lot, so "no orphan entries" is an
    /// assertion rather than a hope.
    var parkedTabsForTesting: [PanelTab] {
        parked.keys.sorted { $0.storageKey < $1.storageKey }
    }

    // MARK: - Undo

    /// One reversible action.
    ///
    /// `u` means "undo the last thing I did", so pin changes share the stack
    /// with deletions rather than living in a parallel one — a user pressing it
    /// is not thinking in categories.
    private enum UndoableOperation {
        case deletedClips(items: [ClipItem], contents: [String: Data])
        case deletedEntries(entries: [LibraryEntry])
        /// A collection and the membership of its entries *as it was before* the
        /// deletion. One case covers both buttons in the confirmation: rows that
        /// were deleted are re-inserted from this snapshot, rows that were moved
        /// have their `collectionID` rewritten back to it.
        case deletedCollection(collection: LibraryCollection, entries: [LibraryEntry])
        /// `orderDate` is the row's sort key *before* the change: `created_at`
        /// for a clip, `updated_at` for a prompt. Unpinning rewrites it, so the
        /// undo has to put it back — see `LocalStore.restorePinState`.
        case pinChanged(id: String, tab: PanelTab, wasPinned: Bool, orderDate: Date)
    }

    private var undoStack: [UndoableOperation] = []
    /// Undo is a safety net for the last few actions, not a journal — an
    /// unbounded stack would hold deleted payloads in memory forever.
    private static let undoDepth = 50

    var canUndo: Bool { !undoStack.isEmpty }

    // MARK: - Collaborators

    let settings: Settings
    private let store: LocalStore
    private var monitor: PasteboardMonitor?
    let focusTarget = FocusTarget()

    /// Called when the panel should close.
    var onDismiss: (() -> Void)?
    /// Called when an entry should be opened in the editor.
    ///
    /// The `String` is the collection the picker should start on — for a new
    /// entry that is the current tab's collection, or the first collection when
    /// the cursor is on the clipboard.
    var onEditItem: ((LibraryEntry?, String) -> Void)?
    /// The gear, reached by mouse or by arrowing along the top bar.
    var onOpenSettings: (() -> Void)?

    /// Name of the app that was frontmost when a clip is captured.
    ///
    /// Injected rather than read inline. It was the only reason this file
    /// reached for the window server, and with it behind a closure the model is
    /// constructible in a test with a temp store — which is what the undo stack
    /// and the per-tab state machine needed in order to be asserted rather than
    /// hand-walked. See `docs/roadmap.md` 2.1.1.
    private let sourceApp: @MainActor () -> String?

    init(
        store: LocalStore,
        settings: Settings,
        sourceApp: @escaping @MainActor () -> String? = { nil }
    ) {
        self.store = store
        self.settings = settings
        self.sourceApp = sourceApp
    }

    // MARK: - Derived views of the data

    /// The rows currently rendered, after filtering.
    ///
    /// This — not the full list — is what the reducer is handed. Passing the
    /// unfiltered list is the single mistake that would reintroduce v1's bug.
    var visibleClips: [ClipItem] {
        selection.isSearching ? Matcher.filter(clips, query: selection.query) : clips
    }

    /// The collection the panel is currently showing, or `nil` on Clipboard.
    ///
    /// Replaces every `tab == .prompts` test in this file. The question is no
    /// longer *which* tab this is but *what kind* it is, which is the whole
    /// point of the tab model change.
    var currentCollectionID: String? { selection.tab.collectionID }

    private var collectionEntries: [LibraryEntry] {
        guard let id = currentCollectionID else { return [] }
        return entries.filter { $0.collectionID == id }
    }

    var visibleEntries: [LibraryEntry] {
        selection.isSearching
            ? Matcher.filter(collectionEntries, query: selection.query)
            : collectionEntries
    }

    var visibleIDs: [String] {
        currentCollectionID == nil ? visibleClips.map(\.id) : visibleEntries.map(\.id)
    }

    /// The tabs the bar draws, left to right.
    ///
    /// Clipboard is pinned first and is not reorderable. Not a convention — it
    /// is the one real special case: another table, written by the poller,
    /// evicting, read-only.
    var tabs: [PanelTab] { [.clipboard] + collections.map { .collection($0.id) } }

    /// Where `⇧S` and `n`-on-the-clipboard land.
    ///
    /// The first collection in tab order, with no preference key behind it. A
    /// stored destination could be deleted and would need a dangling-reference
    /// fallback; this cannot dangle, and the rule is *visible* — the order is
    /// drawn across the top bar, which makes it the least hidden state in the
    /// app. To change where clips land, move that collection to the front.
    var firstCollectionID: String? { collections.first?.id }

    /// Count for a tab's badge.
    func entryCount(in collectionID: String) -> Int {
        entries.lazy.filter { $0.collectionID == collectionID }.count
    }

    /// The buttons the *currently selected row is drawing*, in render order.
    ///
    /// The horizontal counterpart of ``visibleIDs``: the reducer is told what is
    /// actually on screen rather than being left to assume. Derived from the
    /// item itself, which is the same array the row renders from — see
    /// ``ClipItem/rowActions``.
    var selectedRowActions: [RowAction] {
        guard let id = selection.selectedID else { return [] }
        if currentCollectionID == nil {
            return visibleClips.first { $0.id == id }?.rowActions ?? []
        }
        return visibleEntries.first { $0.id == id }?.rowActions ?? []
    }

    var selectedClip: ClipItem? {
        guard let id = selection.selectedID else { return nil }
        return clips.first { $0.id == id }
    }

    var selectedEntry: LibraryEntry? {
        guard let id = selection.selectedID else { return nil }
        return entries.first { $0.id == id }
    }

    // MARK: - Lifecycle

    /// Load persisted data and start watching the pasteboard.
    func start() async {
        await refresh()
        await backfillThumbnails()
        let monitor = PasteboardMonitor { [weak self] capture in
            guard let self else { return }
            Task { await self.record(capture) }
        }
        monitor.start()
        self.monitor = monitor
    }

    func refresh() async {
        do {
            let loadedClips = try await store.allClips()
            let loadedCollections = try await store.allCollections()
            let loadedEntries = try await store.allEntries()
            clips = loadedClips
            collections = loadedCollections
            entries = loadedEntries
            // Order matters: the tab decides which list `visibleIDs` returns, so
            // it has to be valid before the selection is anchored against it.
            reconcileTabs()
            reconcileSelection()
        } catch {
            setStatus(strings.errorReadHistory("\(error)"))
        }
    }

    /// Re-anchor the selection against the list that is actually rendered.
    ///
    /// Called after every mutation and every background refresh, because a
    /// selection pointing at a row that no longer exists is one keystroke away
    /// from acting on the wrong thing.
    private func reconcileSelection() {
        selection = SelectionReducer.reconcile(
            selection, with: visibleIDs, actions: selectedRowActions
        )
    }

    /// Give thumbnails to image rows captured before they existed.
    ///
    /// Runs once per launch, after the first load so it never delays the panel.
    /// Bounded by the store's own query limit, so a large history is spread over
    /// several launches rather than stalling one.
    ///
    /// Failures are ignored on purpose: a missing thumbnail costs a plain icon,
    /// and a sidecar that will not decode is not worth a visible error.
    private func backfillThumbnails() async {
        guard let pending = try? await store.imageRowsMissingThumbnail(), !pending.isEmpty
        else { return }

        var repaired = 0
        for row in pending {
            guard let data = try? await store.imageData(atBlobPath: row.blobPath),
                  let thumbnail = Thumbnail.make(from: data)
            else { continue }
            try? await store.setThumbnail(thumbnail, id: row.id)
            repaired += 1
        }
        guard repaired > 0 else { return }
        await refresh()
    }

    // MARK: - Collections

    /// Delete a collection, moving or removing its entries. No undo capture —
    /// used by tests and by paths that do their own bookkeeping.
    func deleteCollection(id: String, movingEntriesTo destination: String?) async throws {
        try await store.deleteCollection(id: id, movingEntriesTo: destination)
        await refresh()
        // The tab list changed, so the selected row may be somewhere else
        // entirely — or on another tab.
        reorderToken &+= 1
    }

    /// Delete a collection, capturing enough to undo it.
    ///
    /// The snapshot is taken *before* the store is touched, and the undo entry
    /// is pushed *after* the delete succeeds — a failed delete must not spend
    /// the user's `u` on a no-op. That is CLAUDE.md §5.1, and the shape of
    /// SW-14.
    ///
    /// Reachable only from Settings, which is a separate `NSHostingView` and so
    /// cannot see `u` itself. That is exactly why the confirmation offers a
    /// non-destructive default rather than leaning on this.
    func deleteCollectionWithUndo(
        _ collection: LibraryCollection,
        movingEntriesTo destination: String?
    ) async {
        let members = entries.filter { $0.collectionID == collection.id }
        do {
            try await store.deleteCollection(id: collection.id, movingEntriesTo: destination)
            pushUndo(.deletedCollection(collection: collection, entries: members))
            await refresh()
            reorderToken &+= 1
        } catch {
            setStatus(strings.errorDeleteCollection("\(error)"))
            await refresh()
        }
    }

    /// - Returns: `false` at the cap. Not an error: "you already have five
    ///   tabs" is a state the `＋` greys out for, not something to interrupt
    ///   anyone about.
    @discardableResult
    func createCollection(name: String, symbol: CollectionSymbol) async -> Bool {
        do {
            let made = try await store.createCollection(name: name, symbol: symbol)
            await refresh()
            return made != nil
        } catch {
            setStatus(strings.errorSavePrompt("\(error)"))
            return false
        }
    }

    func updateCollection(_ collection: LibraryCollection) async {
        do {
            try await store.updateCollection(collection)
            await refresh()
        } catch {
            setStatus(strings.errorSavePrompt("\(error)"))
        }
    }

    func reorderCollections(_ orderedIDs: [String]) async throws {
        try await store.reorderCollections(orderedIDs)
        await refresh()
        reorderToken &+= 1
    }

    /// Test-only wrapper over the store, so the shell tests drive the same path
    /// the UI does rather than reaching around the model.
    func createEntryForTesting(collectionID: String, title: String, body: String) async throws {
        try await store.createEntry(collectionID: collectionID, title: title, body: body)
    }

    /// Record a clip without a pasteboard. Test-only entry to the same path
    /// `PasteboardMonitor` drives, so the tests exercise production code rather
    /// than a parallel one written to be convenient.
    func recordForTesting(text: String) async {
        await record(.text(text))
    }

    private func record(_ capture: PasteboardMonitor.Capture) async {
        do {
            switch capture {
            case .text(let string):
                try await store.recordText(
                    string,
                    sourceApp: sourceApp(),
                    limit: settings.historyLimit
                )
            case .image(let data, let width, let height, let format, let thumbnail):
                try await store.recordImage(
                    data, width: width, height: height, format: format,
                    thumbnail: thumbnail,
                    sourceApp: sourceApp(),
                    limit: settings.historyLimit
                )
            }
            await refresh()
        } catch {
            setStatus(strings.errorRecordClip("\(error)"))
        }
    }

    // MARK: - Command entry point

    /// The single door every keystroke comes through.
    func handle(_ command: KeyCommand) {
        let outcome = SelectionReducer.reduce(
            selection, command,
            visibleIDs: visibleIDs, actions: selectedRowActions, tabs: tabs
        )
        let previousTab = selection.tab
        let previousQuery = selection.query
        let previousSearching = selection.isSearching
        selection = outcome.state

        if previousTab != selection.tab {
            swapTabState(from: previousTab, to: selection.tab)
        }

        // A query change re-filters the list underneath the cursor. The reducer
        // cannot re-anchor it — it was handed the *old* `visibleIDs` — so the
        // selection can end up pointing at a row the filter just hid. Nothing
        // acts on it (every effect re-checks membership), but the panel shows
        // no selection at all until the next arrow key, and `⏎` does nothing.
        if selection.query != previousQuery || selection.isSearching != previousSearching {
            reconcileSelection()
        }

        guard let effect = outcome.effect else { return }
        perform(effect)
    }

    /// Preserve each tab's selection and query across a switch, so returning to
    /// a tab does not silently reset what you were doing there.
    ///
    /// Which parts survive the handover is
    /// ``SelectionReducer/swapTab(current:incoming:from:to:)`` — a rule with a
    /// regression test, not one written twice in a view model.
    private func swapTabState(from previousTab: PanelTab, to targetTab: PanelTab) {
        let stored = parked[targetTab] ?? SelectionReducer.State(tab: targetTab)
        let (outgoing, adopted) = SelectionReducer.swapTab(
            current: selection, incoming: stored, from: previousTab, to: targetTab
        )
        parked[previousTab] = outgoing
        selection = adopted
        reconcileSelection()
    }

    /// Re-anchor the *tab* after the collection list changed underneath it.
    ///
    /// Two things, and both matter. The panel cannot be left sitting on a tab
    /// that no longer exists — that is ``SelectionReducer/reconcileTab(_:with:)``.
    /// And the parking lot cannot keep entries for tabs that are gone: a
    /// recreated collection reusing an id would inherit a stranger's cursor.
    private func reconcileTabs() {
        let live = tabs
        parked = parked.filter { live.contains($0.key) }

        let before = selection.tab
        selection = SelectionReducer.reconcileTab(selection, with: live)
        guard selection.tab != before else { return }
        parked.removeValue(forKey: before)
        // `reconcileTab` leaves a clean slate because Core has no parking of its
        // own; overlay the destination's stored state if we kept any.
        if let stored = parked[selection.tab] {
            selection.selectedID = stored.selectedID
            selection.query = stored.query
            selection.isSearching = stored.isSearching
            selection.expandedID = stored.expandedID
        }
    }

    private func perform(_ effect: SelectionEffect) {
        switch effect {
        case .confirm(let id): confirm(id: id)
        case .delete(let id): Task { await delete(id: id) }
        case .togglePin(let id): Task { await togglePin(id: id) }
        case .toggleExpand: break // purely visual; the reducer already applied it
        case .undo: Task { await undo() }
        case .newItem: beginNewItem()
        case .promote(let id): Task { await promote(clipID: id) }
        case .edit(let id): beginEdit(id: id)
        case .openSettings: onOpenSettings?()
        case .switchTab: break // handled above, where both tabs' state is in hand
        case .dismiss: onDismiss?()
        }
    }

    /// `n` and `＋`.
    ///
    /// On a collection tab the new entry goes there; on the clipboard it goes to
    /// the first collection — the same rule `⇧S` follows. The `＋` glyph is
    /// still absent from the clipboard's bar, which is a judgement about what a
    /// plus *reads* as next to the word "Clipboard", not a statement that the
    /// action is unavailable. That asymmetry is deliberate.
    private func beginNewItem() {
        guard let target = currentCollectionID ?? firstCollectionID else {
            setStatus(strings.statusNoCollections)
            return
        }
        onEditItem?(nil, target)
    }

    private func beginEdit(id: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        onEditItem?(entry, entry.collectionID)
    }

    // MARK: - Effects

    /// Put the row on the pasteboard, restore focus, and optionally paste.
    ///
    /// The default stops after restoring focus. That needs no Accessibility
    /// permission and can never paste into the wrong field — the user presses
    /// `⌘V` where they actually mean it.
    func confirm(id: String) {
        Task { await deliver(id: id) }
    }

    private func deliver(id: String) async {
        var text: String?
        var imageData: Data?

        do {
            if currentCollectionID != nil {
                text = entries.first { $0.id == id }?.body
            } else if let clip = clips.first(where: { $0.id == id }) {
                if clip.kind == .text {
                    text = try await store.text(for: id)
                } else {
                    imageData = try await store.imageData(for: id)
                }
            } else {
                return
            }
        } catch {
            setStatus(strings.errorReadEntry("\(error)"))
            return
        }

        // Mark before writing: the write bumps `changeCount` synchronously, so
        // the poller would otherwise read our own paste back as a new clip.
        monitor?.markNextWriteAsOurs()
        if let text {
            PasteSimulator.write(text: text)
        } else if let imageData {
            PasteSimulator.write(imageData: imageData)
        } else {
            return
        }

        onDismiss?()

        // Auto Paste only fires when it can actually work. Posting the event
        // without Accessibility fails silently, which is v1's SC-06 exactly.
        if settings.autoPaste && AccessibilityPermission.isTrusted {
            focusTarget.restore { PasteSimulator.sendCommandV() }
        } else {
            focusTarget.restore()
        }
    }

    private func delete(id: String) async {
        do {
            if currentCollectionID != nil {
                guard let entry = entries.first(where: { $0.id == id }) else { return }
                try await store.deleteEntry(id: id)
                // Pushed *after* the write succeeds. A failed delete that still
                // consumed a stack slot would spend the user's `u` on a silent
                // no-op — CLAUDE.md §5.1, and the shape of SW-14.
                pushUndo(.deletedEntries(entries: [entry]))
            } else {
                guard let clip = clips.first(where: { $0.id == id }) else { return }
                // Capture the payload *before* deleting, so undo restores the
                // whole entry. v1 dropped images from the undo batch and still
                // reported success (SC-05).
                var contents: [String: Data] = [:]
                if clip.kind == .text, let text = try await store.text(for: id) {
                    contents[id] = Data(text.utf8)
                } else if let image = try await store.imageData(for: id) {
                    contents[id] = image
                }
                try await store.delete(id: id)
                pushUndo(.deletedClips(items: [clip], contents: contents))
                // The encoded thumbnail is a column and goes with the row; this
                // drops the *decoded* copy so the cache cannot outlive it.
                ThumbnailCache.forget(id: id)
            }
            await refresh()
        } catch {
            setStatus(strings.errorDelete("\(error)"))
            await refresh()
        }
    }

    /// Pin or unpin the selected row.
    ///
    /// Both directions keep the row under the user's eye. Pinning lifts it into
    /// the pinned group at the top; unpinning drops it to the *top* of the
    /// unpinned group rather than back to its chronological place, which would
    /// otherwise send it — and the selection with it — hundreds of rows down.
    /// See ``LocalStore/setPinned(_:id:now:)``.
    private func togglePin(id: String) async {
        do {
            // Both arms push *after* the write. A pin that failed but still
            // consumed a stack slot turns the next `u` into a no-op the user
            // spent their one undo on.
            if currentCollectionID != nil {
                guard let entry = entries.first(where: { $0.id == id }) else { return }
                try await store.setEntryPinned(!entry.isPinned, id: id)
                pushUndo(.pinChanged(
                    id: id, tab: selection.tab,
                    wasPinned: entry.isPinned, orderDate: entry.updatedAt
                ))
            } else {
                guard let clip = clips.first(where: { $0.id == id }) else { return }
                try await store.setPinned(!clip.isPinned, id: id)
                pushUndo(.pinChanged(
                    id: id, tab: .clipboard,
                    wasPinned: clip.isPinned, orderDate: clip.createdAt
                ))
            }
            await refresh()
            // The row moved but kept its id, so nothing else would tell the list
            // to scroll it back into view.
            reorderToken &+= 1
        } catch {
            setStatus(strings.errorPin("\(error)"))
        }
    }

    private func promote(clipID: String) async {
        guard let target = firstCollectionID,
              let destination = collections.first(where: { $0.id == target })
        else {
            setStatus(strings.statusNoCollections)
            return
        }
        do {
            guard try await store.promote(clipID: clipID, into: target) != nil else {
                setStatus(strings.statusOnlyTextPromotes)
                return
            }
            await refresh()
            setStatus(strings.statusSavedTo(destination.name))
        } catch {
            setStatus(strings.errorPromote("\(error)"))
        }
    }


    private func pushUndo(_ operation: UndoableOperation) {
        undoStack.insert(operation, at: 0)
        if undoStack.count > Self.undoDepth { undoStack.removeLast() }
    }

    private func undo() async {
        guard !undoStack.isEmpty else { return }
        let operation = undoStack.removeFirst()
        do {
            // Note: on any failure below the entry goes back on the stack. It
            // used to be consumed regardless, so a restore that could not
            // complete — an image whose bytes are gone, a locked database —
            // cost the user both the row and their only way back to it.
            switch operation {
            case .deletedClips(let items, let contents):
                try await store.restore(items, contents: contents)
                selection.selectedID = items.first?.id ?? selection.selectedID

            case .deletedCollection(let collection, let members):
                // The collection first, then its members — no entry is ever
                // momentarily homeless.
                try await store.restoreCollection(collection, entries: members)

            case .deletedEntries(let restored):
                try await store.restoreEntries(restored)
                selection.selectedID = restored.first?.id ?? selection.selectedID

            case .pinChanged(let id, let tab, let wasPinned, let orderDate):
                // Switch back to the tab the change happened on, so the row the
                // user is about to see restored is actually on screen.
                //
                // Through the handover, not by assigning `selection.tab`: that
                // shortcut skipped filing the outgoing tab's query and search
                // mode away, so undoing a pin from the other tab dragged the
                // current tab's search across with it and lost the target tab's.
                if selection.tab != tab {
                    let previous = selection.tab
                    selection.tab = tab
                    swapTabState(from: previous, to: tab)
                }
                if tab.collectionID != nil {
                    try await store.restoreEntryPinState(
                        id: id, isPinned: wasPinned, orderDate: orderDate
                    )
                } else {
                    try await store.restorePinState(
                        id: id, isPinned: wasPinned, orderDate: orderDate
                    )
                }
                selection.selectedID = id
                setStatus(wasPinned ? strings.statusPinRestored : strings.statusUnpinnedAgain)
            }
            await refresh()
            // Restored rows reappear wherever their age puts them, which may be
            // nowhere near what is currently on screen.
            reorderToken &+= 1
        } catch {
            undoStack.insert(operation, at: 0)
            setStatus(strings.errorUndo("\(error)"))
        }
    }

    // MARK: - Prompt editing

    func saveItem(id: String?, title: String, body: String, collectionID: String) async {
        do {
            if let id, var existing = entries.first(where: { $0.id == id }) {
                existing.title = title
                existing.body = body
                // Changing this in the editor *is* the move. Membership is
                // written like any other field, so there is no second code path
                // that could disagree about where the entry lives.
                existing.collectionID = collectionID
                try await store.updateEntry(existing)
            } else {
                try await store.createEntry(
                    collectionID: collectionID, title: title, body: body
                )
            }
            await refresh()
        } catch {
            setStatus(strings.errorSavePrompt("\(error)"))
        }
    }

    /// Full text of a clip, for the expanded row.
    func expandedText(for id: String) async -> String? {
        if currentCollectionID != nil { return entries.first { $0.id == id }?.body }
        return try? await store.text(for: id)
    }

    func imageData(for id: String) async -> Data? {
        try? await store.imageData(for: id)
    }

    func clearStatus() {
        statusDismissTask?.cancel()
        statusDismissTask = nil
        statusMessage = nil
    }

    /// The catalog the status line is written in. Resolved at the moment a
    /// message is made rather than held, so a message composed after a language
    /// switch is in the new language.
    private var strings: Strings { settings.strings }

    /// Show a transient message in the footer, replacing any current one.
    private func setStatus(_ message: String) {
        statusDismissTask?.cancel()
        statusMessage = message
        statusDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.statusLifetime)
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
            self?.statusDismissTask = nil
        }
    }

    /// Called when the panel is about to open, so each summon starts clean
    /// rather than resuming a search the user has forgotten they left running.
    func prepareForPresentation() {
        selection.isSearching = false
        selection.query = ""
        selection.expandedID = nil
        // A summon starts on a row, never on a button left armed from last time.
        selection.focus = .list
        statusMessage = nil
        reconcileSelection()
        Task { await refresh() }
    }
}
