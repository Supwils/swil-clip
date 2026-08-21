import SwiftUI
import SwilClipCore

/// One prompt row.
///
/// Two lines rather than the clipboard tab's one: a prompt is a *name plus its
/// content*, and the whole reason titles exist here is that four entries all
/// starting "请…" are indistinguishable on a single truncated line. The second
/// line costs vertical space and earns it back in scannability.
struct PromptRowView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    let prompt: PromptItem
    let isSelected: Bool
    let query: String
    let isExpanded: Bool
    /// See ``ClipRowView/focusedAction``.
    let focusedAction: RowAction?

    let onSelect: () -> Void
    let onConfirm: () -> Void
    let onAction: (RowAction) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded { expansion }
        }
        .padding(.vertical, metrics.rowVertical + metrics.scale)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 8 * metrics.scale) {
            RoundedRectangle(cornerRadius: metrics.radiusXS + 1, style: .continuous)
                .fill(isSelected ? theme.accentSoft : Token.Surface.soft)
                .frame(width: metrics.chip, height: metrics.chip)
                .overlay {
                    Image(systemName: "text.quote")
                        .font(.system(size: metrics.actionGlyph, weight: .medium))
                        .foregroundStyle(
                            isSelected ? theme.accent : Token.Foreground.muted
                        )
                }

            VStack(alignment: .leading, spacing: 1) {
                HighlightedText(
                    text: prompt.title, query: query, font: metrics.rowTitleFont
                )
                .lineLimit(1)
                Text(prompt.preview)
                    .font(metrics.metaFont)
                    .foregroundStyle(Token.Foreground.subtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingCluster
        }
    }

    private func symbol(for action: RowAction) -> String {
        switch action {
        case .pin: prompt.isPinned ? "pin.fill" : "pin"
        case .promote: "text.badge.star"
        case .edit: "pencil"
        case .expand: isExpanded ? "chevron.up" : "chevron.down"
        case .delete: "trash"
        }
    }

    private func help(for action: RowAction) -> String {
        switch action {
        case .pin: prompt.isPinned ? strings.unpin : strings.pin
        case .promote: strings.saveAsPromptTooltip
        case .edit: strings.edit
        case .expand: isExpanded ? strings.collapse : strings.preview
        case .delete: strings.delete
        }
    }

    private var trailingCluster: some View {
        ZStack(alignment: .trailing) {
            if isHovering || isSelected {
                // Generated from `prompt.rowActions`; see ``ClipRowView``.
                HStack(spacing: 2 * metrics.scale) {
                    ForEach(prompt.rowActions) { action in
                        RowActionButton(
                            symbol: symbol(for: action),
                            help: help(for: action),
                            isDestructive: action == .delete,
                            isActive: action == .pin && prompt.isPinned,
                            isFocused: focusedAction == action,
                            action: { onAction(action) }
                        )
                    }
                }
            } else if prompt.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: metrics.pinGlyph))
                    .foregroundStyle(theme.accent.opacity(0.8))
            }
        }
        .frame(width: metrics.actionCluster, alignment: .trailing)
        .padding(.top, 1)
    }

    private var expansion: some View {
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            Hairline().padding(.vertical, 6 * metrics.scale)
            ScrollView {
                Text(prompt.body)
                    .font(metrics.expandedFont)
                    .foregroundStyle(Token.Foreground.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: metrics.expansionMaxHeight)

            HStack {
                Text(strings.characterCount(prompt.body.count))
                Spacer(minLength: 0)
                Text(strings.editedLabel(for: prompt.updatedAt))
            }
            .font(metrics.microFont)
            .foregroundStyle(Token.Foreground.faint)
        }
        .padding(.bottom, 2)
    }
}
