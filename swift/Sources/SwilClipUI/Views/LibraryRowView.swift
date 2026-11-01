import SwiftUI
import SwilClipCore

/// One library row — a saved entry in whichever collection is showing.
///
/// ## One line, like the clipboard tab
///
/// This drew two lines — title, then a truncated body — on the theory that four
/// entries all starting "请…" are indistinguishable on a single line. In
/// practice the second line disambiguated nothing, because ``PromptTitle``
/// derives the title *from the body's first line*: both lines were truncations
/// of the same string, so entries that shared an opening shared both. The real
/// answer to that problem is a better title, which the editor exists for.
///
/// So the body is not drawn here. It belongs to the expansion, which is what
/// `e` is for.
///
/// ## Except while searching
///
/// With a live query the second line comes back, highlighted. Its job then is
/// not "preview" but **"why is this row in my results"** — `Matcher` matches on
/// title *and* body, so a hit that lives only in the body would otherwise show
/// up as a title with no visible reason for being there. That question only
/// exists during a search, which is exactly when the line is drawn.
struct LibraryRowView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    let entry: LibraryEntry
    /// The glyph of the collection this row lives in.
    ///
    /// Passed in rather than looked up: the row does not get to know about the
    /// collection list, and the tab bar and the row must not each derive the
    /// symbol from their own copy of it.
    let symbol: CollectionSymbol
    let isSelected: Bool
    let query: String
    let isExpanded: Bool
    /// See ``ClipRowView/focusedAction``.
    let focusedAction: RowAction?
    let edit: InlineEditHooks
    /// The latest scroll request aimed at this row, if any.
    let scroll: ExpansionScroll?

    let onSelect: () -> Void
    let onConfirm: () -> Void
    let onAction: (RowAction) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded { expansion }
        }
        .padding(.vertical, metrics.rowVertical)
        .padding(.horizontal, metrics.row)
        .background {
            if isSelected {
                SelectionBackground()
            } else if isHovering {
                RoundedRectangle(cornerRadius: metrics.radiusMD, style: .continuous)
                    .fill(Token.Surface.hover)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onConfirm)
        .onTapGesture(perform: onSelect)
    }

    /// Whether the "why did this match" line is drawn.
    ///
    /// `query` is already empty whenever search is closed — the panel passes it
    /// that way — so this is exactly "there is a live query".
    private var showsMatchLine: Bool { !query.isEmpty }

    private var header: some View {
        // Centre-aligned and `minHeight`-floored, the same shape `ClipRowView`
        // uses. The old `.top` alignment existed to hang two lines off the chip.
        HStack(alignment: showsMatchLine ? .top : .center, spacing: 8 * metrics.scale) {
            RoundedRectangle(cornerRadius: metrics.radiusXS + 1, style: .continuous)
                .fill(isSelected ? theme.accentSoft : Token.Surface.soft)
                .frame(width: metrics.chip, height: metrics.chip)
                .overlay {
                    Image(systemName: symbol.rawValue)
                        .font(.system(size: metrics.actionGlyph, weight: .medium))
                        .foregroundStyle(
                            isSelected ? theme.accent : Token.Foreground.muted
                        )
                }

            VStack(alignment: .leading, spacing: 1) {
                HighlightedText(
                    text: entry.title, query: query, font: metrics.rowTitleFont
                )
                .lineLimit(1)
                .truncationMode(.tail)

                if showsMatchLine {
                    HighlightedText(
                        text: entry.preview,
                        query: query,
                        font: metrics.metaFont,
                        base: Token.Foreground.subtle
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingCluster
        }
        .frame(minHeight: metrics.chip + 4 * metrics.scale)
    }

    private func symbol(for action: RowAction) -> String {
        switch action {
        case .pin: entry.isPinned ? "pin.fill" : "pin"
        case .promote: "text.badge.star"
        case .edit: "pencil"
        case .expand: isExpanded ? "chevron.up" : "chevron.down"
        case .delete: "trash"
        }
    }

    private func help(for action: RowAction) -> String {
        switch action {
        case .pin: entry.isPinned ? strings.unpin : strings.pin
        case .promote: strings.saveAsPromptTooltip
        case .edit: strings.edit
        case .expand: isExpanded ? strings.collapse : strings.preview
        case .delete: strings.delete
        }
    }

    private var trailingCluster: some View {
        ZStack(alignment: .trailing) {
            if isHovering || isSelected {
                // Generated from `entry.rowActions`; see ``ClipRowView``.
                HStack(spacing: 2 * metrics.scale) {
                    ForEach(entry.rowActions) { action in
                        RowActionButton(
                            symbol: symbol(for: action),
                            help: help(for: action),
                            isDestructive: action == .delete,
                            isActive: action == .pin && entry.isPinned,
                            isFocused: focusedAction == action,
                            action: { onAction(action) }
                        )
                    }
                }
            } else if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: metrics.pinGlyph))
                    .foregroundStyle(theme.accent.opacity(0.8))
            }
        }
        .frame(width: metrics.actionCluster, alignment: .trailing)
    }

    private var expansion: some View {
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            Hairline().padding(.vertical, 6 * metrics.scale)
            if let draft = edit.draft {
                // Body only. The title has its own field in the sheet editor
                // (the pencil), and a second text box here would turn a quick
                // fix into a form.
                InlineEditor(text: draft, onSave: edit.save, onCancel: edit.cancel)
            } else {
                ExpandedText(
                    text: entry.body,
                    font: metrics.expandedNSFont,
                    color: NSColor(Token.Foreground.primary),
                    maxHeight: metrics.expansionMaxHeight,
                    scroll: scroll
                )

                HStack(spacing: 8 * metrics.scale) {
                    Text(strings.characterCount(entry.body.count))
                    Spacer(minLength: 0)
                    Text(strings.editedLabel(for: entry.updatedAt))
                    InlineEditButton(action: edit.begin)
                }
                .font(metrics.microFont)
                .foregroundStyle(Token.Foreground.faint)
            }
        }
        .padding(.bottom, 2)
    }
}
