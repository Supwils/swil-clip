import SwiftUI
import SwilClipCore

/// The panel's whole surface: drag strip, tab bar, list, footer.
struct PanelRootView: View {
    @Bindable var model: AppModel

    private var metrics: Metrics { Metrics(size: model.settings.panelSize) }
    /// Read from `settings` here and pushed into the environment once, so a
    /// language switch invalidates exactly one body and every row below follows.
    private var strings: Strings { model.settings.strings }
    private var theme: Theme { model.settings.theme }

    /// Full text / image bytes for the one expanded row, fetched lazily so the
    /// list never carries payloads it is not showing.
    @State private var expandedText: String?
    @State private var expandedImage: Data?

    var body: some View {
        AppShell {
            VStack(spacing: 0) {
                DragStrip()
                TabBar(
                    tabs: model.tabs,
                    current: model.selection.tab,
                    focusedItem: model.selection.focus.topBarItem,
                    strings: strings,
                    clipCount: model.clips.count,
                    collections: model.collections,
                    entryCount: { model.entryCount(in: $0) },
                    switchKeyLabel: model.settings.tabSwitchKey.displayString,
                    onSelect: { tab in select(tab) },
                    onNewItem: { model.handle(.newItem) },
                    onOpenSettings: { model.onOpenSettings?() }
                )
                Hairline()

                if model.selection.isSearching {
                    SearchField(
                        query: model.selection.query,
                        placeholder: model.currentCollectionID == nil
                            ? strings.searchHistoryPlaceholder
                            : strings.searchCollectionPlaceholder(currentCollectionName)
                    )
                    .padding(.top, 6 * metrics.scale)
                }

                list
                Hairline()
                FooterBar(model: model)
            }
        }
        .frame(width: metrics.panelWidth, height: metrics.panelHeight)
        .environment(\.metrics, metrics)
        .environment(\.strings, strings)
        .environment(\.theme, theme)
        // The panel owns its keyboard entirely — there is no focus ring to move
        // between, so AppKit's ring is noise. It appears when a control is
        // clicked and then stays, drawing a blue box around whatever was touched
        // last, which competes with the accent that means "this row is selected".
        .focusEffectDisabled()
        // Keyed on the revision too: an inline save changes the text without
        // changing the id, and the old text would otherwise stay on screen.
        .task(id: ExpansionKey(id: model.selection.expandedID, revision: model.contentRevision)) {
            await loadExpansion()
        }
    }

    /// Clicking a tab is the same command the keyboard emits, repeated — so the
    /// click cannot take a second path with its own idea of what a handover is.
    private func select(_ tab: PanelTab) {
        guard tab != model.selection.tab,
              let target = model.tabs.firstIndex(of: tab),
              let current = model.tabs.firstIndex(of: model.selection.tab)
        else { return }
        let command: KeyCommand = target > current ? .switchTab : .switchTabBackward
        for _ in 0..<abs(target - current) { model.handle(command) }
    }

    private var currentCollectionSymbol: CollectionSymbol {
        guard let id = model.currentCollectionID else { return .textQuote }
        return model.collections.first { $0.id == id }?.symbol ?? .textQuote
    }

    private var currentCollectionName: String {
        guard let id = model.currentCollectionID,
              let collection = model.collections.first(where: { $0.id == id })
        else { return "" }
        return collection.isUnreadable ? strings.collectionUnreadable : collection.name
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.rowGap) {
                    if model.currentCollectionID == nil {
                        clipRows
                    } else {
                        entryRows
                    }
                }
                .padding(.horizontal, metrics.edge - metrics.row)
                .padding(.vertical, 4 * metrics.scale)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .onChange(of: model.selection.selectedID) { previousID, currentID in
                keepSelectionVisible(from: previousID, to: currentID, proxy: proxy)
            }
            // Pin and unpin move a row without changing its id, so the change
            // above never fires and the selection can be left off-screen.
            //
            // `anchor: nil`, like every other scroll here. This used to centre
            // the row with an animation — the one thing `docs/ui-design.md` and
            // CLAUDE.md both say not to do, because centring moves the whole
            // list under a cursor that did not move. A re-order is a big jump,
            // so it animates; it still scrolls the minimum.
            .onChange(of: model.reorderToken) { _, _ in
                guard let id = model.selection.selectedID else { return }
                withAnimation(Token.Motion.gated(Token.Motion.quick)) {
                    proxy.scrollTo(id, anchor: nil)
                }
            }
        }
    }

    /// Scroll only when the cursor is about to run out of runway.
    ///
    /// The naive version — `scrollTo(selected, anchor: .center)` on every change —
    /// re-centres the list on *every* arrow key, so the whole list slides under a
    /// cursor that never moves, and holding `↓` smears. See ``ScrollAnchoring``
    /// for the rule; the reveal target it returns is a row *past* the selection,
    /// and asking for a minimal scroll to that row is what preserves the margin
    /// without measuring the viewport.
    private func keepSelectionVisible(
        from previousID: String?,
        to currentID: String?,
        proxy: ScrollViewProxy
    ) {
        guard let currentID else { return }
        let ids = model.visibleIDs
        guard let newIndex = ids.firstIndex(of: currentID) else { return }
        let oldIndex = previousID.flatMap { ids.firstIndex(of: $0) }

        guard let revealIndex = ScrollAnchoring.revealIndex(
            movingFrom: oldIndex, to: newIndex, count: ids.count
        ) else { return }

        // `anchor: nil` is the load-bearing part: it scrolls the *minimum*
        // needed to bring the row on screen, and does nothing at all when it is
        // already visible. Any explicit anchor forces a scroll every time.
        if oldIndex == nil {
            // A re-anchor — a filter narrowed, a tab switched, a clip arrived.
            // The jump is large and unexpected, so it is worth explaining.
            withAnimation(Token.Motion.gated(Token.Motion.quick)) {
                proxy.scrollTo(ids[revealIndex], anchor: nil)
            }
        } else {
            // Keyboard navigation: instant. Interpolating between two adjacent
            // rows only adds latency and lets repeats stack into a smear.
            proxy.scrollTo(ids[revealIndex], anchor: nil)
        }
    }

    @ViewBuilder
    private var clipRows: some View {
        let clips = model.visibleClips
        if clips.isEmpty {
            EmptyState(
                symbol: model.selection.isSearching ? "magnifyingglass" : "doc.on.clipboard",
                title: model.selection.isSearching
                    ? strings.emptyNoMatchesTitle
                    : strings.emptyClipsTitle,
                hint: model.selection.isSearching
                    ? strings.emptyNoMatchesHint
                    : strings.emptyClipsHint
            )
            .frame(height: metrics.panelHeight / 2)
        } else {
            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                if isFirstUnpinned(at: index, in: clips) {
                    SectionDivider(label: strings.dividerRecent)
                }
                ClipRowView(
                    clip: clip,
                    isSelected: model.selection.selectedID == clip.id,
                    query: model.selection.isSearching ? model.selection.query : "",
                    isExpanded: model.selection.expandedID == clip.id,
                    expandedText: expandedText,
                    expandedImage: expandedImage,
                    focusedAction: focusedAction(for: clip.id),
                    edit: editHooks(for: clip.id),
                    onSelect: { model.handle(.selectID(clip.id)) },
                    onConfirm: {
                        model.handle(.selectID(clip.id))
                        model.handle(.confirm)
                    },
                    onAction: { action in
                        model.handle(.selectID(clip.id))
                        model.handle(action.command)
                    }
                )
                .id(clip.id)
            }
        }
    }

    @ViewBuilder
    private var entryRows: some View {
        let prompts = model.visibleEntries
        if prompts.isEmpty {
            EmptyState(
                symbol: model.selection.isSearching
                    ? "magnifyingglass" : currentCollectionSymbol.rawValue,
                title: model.selection.isSearching
                    ? strings.emptyNoMatchesTitle
                    : strings.emptyCollectionTitle,
                hint: model.selection.isSearching
                    ? strings.emptyNoMatchesHint
                    : strings.emptyCollectionHint
            )
            .frame(height: metrics.panelHeight / 2)
        } else {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                if isFirstUnpinned(at: index, in: prompts) {
                    SectionDivider(label: strings.dividerSaved)
                }
                LibraryRowView(
                    entry: prompt,
                    symbol: currentCollectionSymbol,
                    isSelected: model.selection.selectedID == prompt.id,
                    query: model.selection.isSearching ? model.selection.query : "",
                    isExpanded: model.selection.expandedID == prompt.id,
                    focusedAction: focusedAction(for: prompt.id),
                    edit: editHooks(for: prompt.id),
                    onSelect: { model.handle(.selectID(prompt.id)) },
                    onConfirm: {
                        model.handle(.selectID(prompt.id))
                        model.handle(.confirm)
                    },
                    onAction: { action in
                        model.handle(.selectID(prompt.id))
                        model.handle(action.command)
                    }
                )
                .id(prompt.id)
            }
        }
    }

    /// A button ring belongs to the selected row and no other. Passing the
    /// focus down unconditionally would light up the same button on every row.
    private func focusedAction(for id: String) -> RowAction? {
        guard model.selection.selectedID == id else { return nil }
        return model.selection.focus.focusedAction
    }

    /// The pencil goes through ``AppModel/handle(_:)`` like every other button,
    /// so clicking it and pressing `⇧E` are one path. Save and cancel are not
    /// commands — while a draft is open ``AppModel/handle(_:)`` refuses them all.
    private func editHooks(for id: String) -> InlineEditHooks {
        InlineEditHooks(
            draft: model.inlineEdit?.id == id
                ? Binding(
                    get: { model.inlineEdit?.draft ?? "" },
                    set: { model.inlineEdit?.draft = $0 }
                )
                : nil,
            begin: {
                model.handle(.selectID(id))
                model.handle(.editInline)
            },
            save: { Task { await model.commitInlineEdit() } },
            cancel: { model.cancelInlineEdit() }
        )
    }

    /// Whether `index` is the first unpinned row after at least one pinned one.
    ///
    /// Both groups have to be non-empty for a divider to mean anything: a line
    /// above the first row, or below the last, is just a stray rule.
    private func isFirstUnpinned<T>(at index: Int, in items: [T]) -> Bool
    where T: PinnableRow {
        guard index > 0, !items[index].isPinned, items[index - 1].isPinned else { return false }
        return true
    }

    private func loadExpansion() async {
        expandedText = nil
        expandedImage = nil
        guard let id = model.selection.expandedID else { return }
        if model.currentCollectionID == nil,
           let clip = model.clips.first(where: { $0.id == id }),
           clip.kind == .image {
            expandedImage = await model.imageData(for: id)
        } else {
            expandedText = await model.expandedText(for: id)
        }
    }
}

private struct ExpansionKey: Hashable {
    let id: String?
    let revision: Int
}

// MARK: - Drag strip

/// An invisible grab area. §4.2 is explicit: no permanent handle — three dots
/// fade in on hover and that is enough of an affordance.
private struct DragStrip: View {
    @Environment(\.metrics) private var metrics
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3 * metrics.scale) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Token.Foreground.faint)
                    .frame(width: 2.5 * metrics.scale, height: 2.5 * metrics.scale)
            }
        }
        .opacity(isHovering ? 1 : 0)
        .animation(Token.Motion.gated(Token.Motion.quick), value: isHovering)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.dragRegionHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Tab bar

private struct TabBar: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    let tabs: [PanelTab]
    let current: PanelTab
    /// Which stop the keyboard is on, if it has arrowed up out of the list.
    let focusedItem: TopBarItem?
    let strings: Strings
    let clipCount: Int
    let collections: [LibraryCollection]
    let entryCount: (String) -> Int
    /// Rendered on the keycap so the reminder always matches the real binding.
    let switchKeyLabel: String
    let onSelect: (PanelTab) -> Void
    let onNewItem: () -> Void
    let onOpenSettings: () -> Void

    /// What the bar gives up, in order, when it will not fit.
    ///
    /// The same device `FooterBar.hints` uses, and the order is as deliberate
    /// here as there: inactive counts go first because they are the least
    /// load-bearing thing on the bar, inactive names go second because an icon
    /// you chose yourself is a usable identifier. The active tab never
    /// degrades — losing the label for *where you are* is the one thing the bar
    /// exists to say.
    private enum Density { case full, noInactiveCounts, iconsOnly }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(.full)
            bar(.noInactiveCounts)
            bar(.iconsOnly)
        }
        .padding(.horizontal, metrics.edge)
        .padding(.bottom, 6 * metrics.scale)
    }

    private func bar(_ density: Density) -> some View {
        HStack(spacing: 2 * metrics.scale) {
            ForEach(tabs, id: \.storageKey) { tab in
                tabButton(tab, density: density)
            }
            Spacer(minLength: 0)
            Keycap(label: switchKeyLabel)
                .opacity(0.55)
            // Rendered from `current.topBarItems` — the same array the reducer
            // steps along — so a stop cannot exist in one and not the other.
            ForEach(current.topBarItems.filter { $0 != .tabs }) { item in
                RowActionButton(
                    symbol: item == .newItem ? "plus" : "gearshape",
                    help: item == .newItem ? strings.newItemTooltip : strings.settingsTooltip,
                    isFocused: focusedItem == item,
                    action: item == .newItem ? onNewItem : onOpenSettings
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func collection(for tab: PanelTab) -> LibraryCollection? {
        guard let id = tab.collectionID else { return nil }
        return collections.first { $0.id == id }
    }

    private func label(for tab: PanelTab) -> String {
        guard let collection = collection(for: tab) else { return strings.clipboardTab }
        // Never blank: a nameless tab reads as "the app lost something".
        return collection.isUnreadable ? strings.collectionUnreadable : collection.name
    }

    private func symbol(for tab: PanelTab) -> String {
        collection(for: tab)?.symbol.rawValue ?? "doc.on.clipboard"
    }

    private func count(for tab: PanelTab) -> Int {
        guard let id = tab.collectionID else { return clipCount }
        return entryCount(id)
    }

    private func tabButton(_ target: PanelTab, density: Density) -> some View {
        let isActive = target == current
        let showsName = isActive || density != .iconsOnly
        let showsCount = count(for: target) > 0 && (isActive || density == .full)

        return Button { onSelect(target) } label: {
            HStack(spacing: 4 * metrics.scale) {
                Image(systemName: symbol(for: target))
                    .font(.system(size: metrics.actionGlyph, weight: .medium))
                    .foregroundStyle(
                        isActive ? Token.Foreground.strong : Token.Foreground.subtle
                    )
                if showsName {
                    Text(label(for: target))
                        .font(metrics.brandFont)
                        .lineLimit(1)
                        .foregroundStyle(
                            isActive ? Token.Foreground.strong : Token.Foreground.subtle
                        )
                }
                if showsCount {
                    Text("\(count(for: target))")
                        .font(metrics.badgeFont)
                        .foregroundStyle(isActive ? theme.accent : Token.Foreground.faint)
                }
            }
            .padding(.horizontal, 7 * metrics.scale)
            .padding(.vertical, 3 * metrics.scale)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                        .fill(focusedItem == .tabs ? theme.accentSoft : Token.Surface.soft)
                }
            }
            .overlay {
                if isActive && focusedItem == .tabs {
                    RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                        .strokeBorder(theme.accent, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Footer

private struct FooterBar: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.strings) private var strings
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6 * metrics.scale) {
            if let status = model.statusMessage {
                Image(systemName: "info.circle")
                    .font(.system(size: 9 * metrics.scale))
                    .foregroundStyle(theme.accent)
                Text(status)
                    .font(metrics.metaFont)
                    .foregroundStyle(Token.Foreground.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // The message clears itself after a few seconds; this is for
                // when it is covering something you want to read *now*.
                Button(strings.dismiss) { model.clearStatus() }
                    .buttonStyle(.plain)
                    .font(metrics.metaFont)
                    .foregroundStyle(Token.Foreground.subtle)
            } else {
                bandHints
            }
        }
        .padding(.horizontal, metrics.edge)
        .padding(.vertical, 6 * metrics.scale)
        .frame(height: metrics.footerHeight)
        .animation(Token.Motion.gated(Token.Motion.quick), value: model.statusMessage)
    }

    /// The footer says different things in different bands.
    ///
    /// While a button is armed, the reel is replaced by what `⏎` is *currently*
    /// aimed at. That is the whole affordance: arrow keys are only safe to use
    /// on a destructive button if the panel tells you, before you press Return,
    /// which one you are on.
    @ViewBuilder
    private var bandHints: some View {
        if model.inlineEdit != nil {
            // Every other key is typing now, so the reel would be describing a
            // keyboard that is not there. Only the two ways out are true.
            HStack(spacing: 8 * metrics.scale) {
                KeyHint(keys: ["⌘", "⏎"], label: strings.hintSave)
                Spacer(minLength: 0)
                KeyHint(keys: ["⎋"], label: strings.hintCancel)
            }
        } else if let action = model.selection.focus.focusedAction {
            HStack(spacing: 8 * metrics.scale) {
                KeyHint(keys: ["←", "→"], label: strings.hintMove)
                KeyHint(keys: ["⏎"], label: strings.rowActionLabel(action))
                Spacer(minLength: 0)
                KeyHint(keys: ["⎋"], label: strings.hintBack)
            }
        } else if let item = model.selection.focus.topBarItem {
            HStack(spacing: 8 * metrics.scale) {
                KeyHint(
                    keys: ["←", "→"],
                    // With more than two tabs there is no single "other" one
                    // to name, so the arrows explain themselves.
                    label: strings.hintMove
                )
                KeyHint(keys: ["⏎"], label: strings.topBarLabel(item))
                Spacer(minLength: 0)
                KeyHint(keys: ["↓"], label: strings.hintBack)
            }
        } else {
            hints
        }
    }

    /// The hint reel.
    ///
    /// Six hints do not fit a 316 pt strip, and a reel that clips is worse than
    /// one that says less. `ViewThatFits` picks the widest version that fits, so
    /// Large shows everything and Small degrades in a chosen order rather than
    /// truncating at whatever character the layout happens to reach.
    ///
    /// What survives the squeeze is deliberate: `⏎` and the tab key stay, because
    /// they are the two things you cannot guess. `move` and `find` lose their
    /// labels first — an arrow keycap explains itself.
    private var hints: some View {
        ViewThatFits(in: .horizontal) {
            reel(labels: .full)
            reel(labels: .short)
            reel(labels: .minimal)
        }
    }

    private enum LabelDensity { case full, short, minimal }

    @ViewBuilder
    private func reel(labels: LabelDensity) -> some View {
        let tabKey = model.settings.tabSwitchKey.displayString
        let isClipboard = model.currentCollectionID == nil

        HStack(spacing: (labels == .full ? 8 : 6) * metrics.scale) {
            KeyHint(keys: ["↑", "↓"], label: labels == .full ? strings.hintMove : "")
            KeyHint(
                keys: ["⏎"],
                label: model.settings.autoPaste ? strings.hintPaste : strings.hintCopy
            )

            if labels != .minimal {
                if isClipboard {
                    KeyHint(keys: ["⇧S"], label: labels == .full ? strings.hintSaveAsPrompt : "")
                } else {
                    KeyHint(keys: ["n"], label: labels == .full ? strings.hintNew : "")
                }
            }

            // Always present: the tab key is rebindable, so it is the one hint a
            // user cannot fall back on convention for.
            // Always present: the switch key is rebindable, so it is the one
            // hint a user cannot fall back on convention for. The label is gone
            // because with N tabs there is no single "other tab" to name.
            KeyHint(keys: [tabKey], label: "")

            Spacer(minLength: 0)

            if model.canUndo && labels == .full {
                KeyHint(keys: ["u"], label: strings.hintUndo)
            }
            KeyHint(keys: ["s"], label: labels == .full ? strings.hintFind : "")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
