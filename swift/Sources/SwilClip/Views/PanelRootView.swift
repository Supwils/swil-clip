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
                    tab: model.selection.tab,
                    focusedItem: model.selection.focus.topBarItem,
                    strings: strings,
                    clipCount: model.clips.count,
                    promptCount: model.prompts.count,
                    switchKeyLabel: model.settings.tabSwitchKey.displayString,
                    onSelect: { tab in
                        guard tab != model.selection.tab else { return }
                        model.handle(.switchTab)
                    },
                    onNewPrompt: { model.handle(.newPrompt) },
                    onOpenSettings: { model.onOpenSettings?() }
                )
                Hairline()

                if model.selection.isSearching {
                    SearchField(
                        query: model.selection.query,
                        placeholder: model.selection.tab == .clipboard
                            ? strings.searchHistoryPlaceholder
                            : strings.searchPromptsPlaceholder
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
        .task(id: model.selection.expandedID) { await loadExpansion() }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.rowGap) {
                    if model.selection.tab == .clipboard {
                        clipRows
                    } else {
                        promptRows
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
    private var promptRows: some View {
        let prompts = model.visiblePrompts
        if prompts.isEmpty {
            EmptyState(
                symbol: model.selection.isSearching ? "magnifyingglass" : "text.quote",
                title: model.selection.isSearching
                    ? strings.emptyNoMatchesTitle
                    : strings.emptyPromptsTitle,
                hint: model.selection.isSearching
                    ? strings.emptyNoMatchesHint
                    : strings.emptyPromptsHint
            )
            .frame(height: metrics.panelHeight / 2)
        } else {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                if isFirstUnpinned(at: index, in: prompts) {
                    SectionDivider(label: strings.dividerLibrary)
                }
                PromptRowView(
                    prompt: prompt,
                    isSelected: model.selection.selectedID == prompt.id,
                    query: model.selection.isSearching ? model.selection.query : "",
                    isExpanded: model.selection.expandedID == prompt.id,
                    focusedAction: focusedAction(for: prompt.id),
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
        if model.selection.tab == .clipboard,
           let clip = model.clips.first(where: { $0.id == id }),
           clip.kind == .image {
            expandedImage = await model.imageData(for: id)
        } else {
            expandedText = await model.expandedText(for: id)
        }
    }
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
    let tab: PanelTab
    /// Which stop the keyboard is on, if it has arrowed up out of the list.
    let focusedItem: TopBarItem?
    let strings: Strings
    let clipCount: Int
    let promptCount: Int
    /// Rendered on the keycap so the reminder always matches the real binding.
    let switchKeyLabel: String
    let onSelect: (PanelTab) -> Void
    let onNewPrompt: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 2 * metrics.scale) {
            tabButton(.clipboard, label: strings.clipboardTab, count: clipCount)
            tabButton(.prompts, label: strings.promptsTab, count: promptCount)
            Spacer(minLength: 0)
            Keycap(label: switchKeyLabel)
                .opacity(0.55)
            // Rendered from `tab.topBarItems` — the same array the reducer
            // steps along — so a stop cannot exist in one and not the other.
            ForEach(tab.topBarItems.filter { $0 != .tabs }) { item in
                RowActionButton(
                    symbol: item == .newPrompt ? "plus" : "gearshape",
                    help: item == .newPrompt ? strings.newPromptTooltip : strings.settingsTooltip,
                    isFocused: focusedItem == item,
                    action: item == .newPrompt ? onNewPrompt : onOpenSettings
                )
            }
        }
        .padding(.horizontal, metrics.edge)
        .padding(.bottom, 6 * metrics.scale)
    }

    private func tabButton(_ target: PanelTab, label: String, count: Int) -> some View {
        let isActive = tab == target
        return Button { onSelect(target) } label: {
            HStack(spacing: 4 * metrics.scale) {
                Text(label)
                    .font(metrics.brandFont)
                    .foregroundStyle(
                        isActive ? Token.Foreground.strong : Token.Foreground.subtle
                    )
                if count > 0 {
                    Text("\(count)")
                        .font(metrics.badgeFont)
                        .foregroundStyle(
                            isActive ? theme.accent : Token.Foreground.faint
                        )
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
        if let action = model.selection.focus.focusedAction {
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
                    label: item == .tabs
                        ? (model.selection.tab == .clipboard
                            ? strings.promptsTab : strings.clipboardTab)
                        : strings.hintMove
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
        let isClipboard = model.selection.tab == .clipboard

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
            KeyHint(keys: [tabKey], label: isClipboard ? strings.promptsTab : strings.clipboardTab)

            Spacer(minLength: 0)

            if model.canUndo && labels == .full {
                KeyHint(keys: ["u"], label: strings.hintUndo)
            }
            KeyHint(keys: ["s"], label: labels == .full ? strings.hintFind : "")
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
