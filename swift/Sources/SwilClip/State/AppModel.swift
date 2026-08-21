import AppKit
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
    private(set) var prompts: [PromptItem] = []
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

    /// Per-tab selection, so switching back returns you where you were.
    private var clipboardSelection = SelectionReducer.State(tab: .clipboard)
    private var promptSelection = SelectionReducer.State(tab: .prompts)

    // MARK: - Undo

    /// One reversible action.
    ///
    /// `u` means "undo the last thing I did", so pin changes share the stack
    /// with deletions rather than living in a parallel one — a user pressing it
    /// is not thinking in categories.
    private enum UndoableOperation {
        case deletedClips(items: [ClipItem], contents: [String: Data])
        case deletedPrompts(items: [PromptItem])
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
    /// Called when a prompt should be opened in the editor.
    var onEditPrompt: ((PromptItem?) -> Void)?
    /// The gear, reached by mouse or by arrowing along the top bar.
    var onOpenSettings: (() -> Void)?

    init(store: LocalStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    // MARK: - Derived views of the data

    /// The rows currently rendered, after filtering.
    ///
    /// This — not the full list — is what the reducer is handed. Passing the
    /// unfiltered list is the single mistake that would reintroduce v1's bug.
    var visibleClips: [ClipItem] {
        selection.isSearching ? Matcher.filter(clips, query: selection.query) : clips
    }

    var visiblePrompts: [PromptItem] {
        selection.isSearching ? Matcher.filter(prompts, query: selection.query) : prompts
    }

    var visibleIDs: [String] {
        selection.tab == .clipboard ? visibleClips.map(\.id) : visiblePrompts.map(\.id)
    }

    /// The buttons the *currently selected row is drawing*, in render order.
    ///
    /// The horizontal counterpart of ``visibleIDs``: the reducer is told what is
    /// actually on screen rather than being left to assume. Derived from the
    /// item itself, which is the same array the row renders from — see
    /// ``ClipItem/rowActions``.
    var selectedRowActions: [RowAction] {
        guard let id = selection.selectedID else { return [] }
        if selection.tab == .clipboard {
            return visibleClips.first { $0.id == id }?.rowActions ?? []
        }
        return visiblePrompts.first { $0.id == id }?.rowActions ?? []
    }

    var selectedClip: ClipItem? {
        guard let id = selection.selectedID else { return nil }
        return clips.first { $0.id == id }
    }

    var selectedPrompt: PromptItem? {
        guard let id = selection.selectedID else { return nil }
        return prompts.first { $0.id == id }
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
            let loadedPrompts = try await store.allPrompts()
            clips = loadedClips
            prompts = loadedPrompts
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

    private func record(_ capture: PasteboardMonitor.Capture) async {
        do {
            switch capture {
            case .text(let string):
                try await store.recordText(
                    string,
                    sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                    limit: settings.historyLimit
                )
            case .image(let data, let width, let height, let format, let thumbnail):
                try await store.recordImage(
                    data, width: width, height: height, format: format,
                    thumbnail: thumbnail,
                    sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName,
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
            selection, command, visibleIDs: visibleIDs, actions: selectedRowActions
        )
        let previousTab = selection.tab
        let previousQuery = selection.query
        let previousSearching = selection.isSearching
        selection = outcome.state

        if previousTab != selection.tab { swapTabState(from: previousTab) }

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
    /// Which parts survive the handover is ``SelectionReducer/swapTab(current:incoming:from:)``
    /// — a rule with a regression test, not one written twice in a view model.
    private func swapTabState(from previousTab: PanelTab) {
        let stored = previousTab == .clipboard ? promptSelection : clipboardSelection
        let (outgoing, adopted) = SelectionReducer.swapTab(
            current: selection, incoming: stored, from: previousTab
        )
        if previousTab == .clipboard {
            clipboardSelection = outgoing
        } else {
            promptSelection = outgoing
        }
        selection = adopted
        reconcileSelection()
    }

    private func perform(_ effect: SelectionEffect) {
        switch effect {
        case .confirm(let id): confirm(id: id)
        case .delete(let id): Task { await delete(id: id) }
        case .togglePin(let id): Task { await togglePin(id: id) }
        case .toggleExpand: break // purely visual; the reducer already applied it
        case .undo: Task { await undo() }
        case .newPrompt: onEditPrompt?(nil)
        case .promote(let id): Task { await promote(clipID: id) }
        case .edit(let id): onEditPrompt?(prompts.first { $0.id == id })
        case .openSettings: onOpenSettings?()
        case .switchTab: break // handled above, where both tabs' state is in hand
        case .dismiss: onDismiss?()
        }
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
            if selection.tab == .prompts {
                text = prompts.first { $0.id == id }?.body
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
            if selection.tab == .prompts {
                guard let prompt = prompts.first(where: { $0.id == id }) else { return }
                pushUndo(.deletedPrompts(items: [prompt]))
                try await store.deletePrompt(id: id)
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
                pushUndo(.deletedClips(items: [clip], contents: contents))
                try await store.delete(id: id)
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
            if selection.tab == .prompts {
                guard let prompt = prompts.first(where: { $0.id == id }) else { return }
                pushUndo(.pinChanged(
                    id: id, tab: .prompts,
                    wasPinned: prompt.isPinned, orderDate: prompt.updatedAt
                ))
                try await store.setPromptPinned(!prompt.isPinned, id: id)
            } else {
                guard let clip = clips.first(where: { $0.id == id }) else { return }
                pushUndo(.pinChanged(
                    id: id, tab: .clipboard,
                    wasPinned: clip.isPinned, orderDate: clip.createdAt
                ))
                try await store.setPinned(!clip.isPinned, id: id)
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
        do {
            guard let prompt = try await store.promoteToPrompt(clipID: clipID) else {
                setStatus(strings.statusOnlyTextPromotes)
                return
            }
            await refresh()
            setStatus(strings.statusSavedAsPrompt(prompt.title))
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

            case .deletedPrompts(let items):
                try await store.restorePrompts(items)
                selection.selectedID = items.first?.id ?? selection.selectedID

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
                    swapTabState(from: previous)
                }
                if tab == .prompts {
                    try await store.restorePromptPinState(
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

    func savePrompt(id: String?, title: String, body: String) async {
        do {
            if let id, var existing = prompts.first(where: { $0.id == id }) {
                existing.title = title
                existing.body = body
                try await store.updatePrompt(existing)
            } else {
                try await store.createPrompt(title: title, body: body)
            }
            await refresh()
        } catch {
            setStatus(strings.errorSavePrompt("\(error)"))
        }
    }

    /// Full text of a clip, for the expanded row.
    func expandedText(for id: String) async -> String? {
        if selection.tab == .prompts { return prompts.first { $0.id == id }?.body }
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
