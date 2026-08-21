import SwiftUI
import SwilClipCore

/// One clipboard row.
///
/// Ratified geometry from `docs/ui-design.md` §7 — 11.5 pt text, 4 pt vertical
/// padding, a 20 pt chip and a 66 pt reserved action cluster. None of those are
/// round numbers by accident; each was chosen against its neighbours in the
/// running app.
struct ClipRowView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    let clip: ClipItem
    let isSelected: Bool
    let query: String
    let isExpanded: Bool
    let expandedText: String?
    let expandedImage: Data?
    /// Which of this row's buttons the keyboard is on, if any. Only ever
    /// non-nil for the selected row.
    let focusedAction: RowAction?

    let onSelect: () -> Void
    let onConfirm: () -> Void
    /// One entry point for every button, mouse or keyboard. Clicking the trash
    /// and arrowing onto it both end up in ``RowAction/command``, so the two
    /// routes cannot acquire different behaviour.
    let onAction: (RowAction) -> Void

    @State private var isHovering = false

    private var kind: ContentKind {
        clip.kind == .image ? .image : ContentKind.detect(clip.text ?? clip.preview)
    }

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
        // Hover paints, but never moves the keyboard cursor (§5.3). "Selection
        // follows mouse" fights a keyboard-first flow and causes drift during
        // async mutations.
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onConfirm)
        .onTapGesture(perform: onSelect)
    }

    private var header: some View {
        HStack(spacing: 8 * metrics.scale) {
            leadingChip

            if clip.isUnreadable {
                // A blank line where text should be looks like the app lost the
                // content. Saying so costs one row and is the difference between
                // a bug report and a shrug.
                Text(strings.unreadableRow)
                    .font(metrics.rowFont)
                    .foregroundStyle(Token.Status.destructive)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HighlightedText(
                    text: clip.preview,
                    query: query,
                    font: kind == .code || kind == .json
                        ? metrics.rowMonoFont
                        : metrics.rowFont
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            trailingCluster
        }
        .frame(minHeight: metrics.chip + 4 * metrics.scale)
    }

    private func symbol(for action: RowAction) -> String {
        switch action {
        case .pin: clip.isPinned ? "pin.fill" : "pin"
        case .promote: "text.badge.star"
        case .edit: "pencil"
        case .expand: isExpanded ? "chevron.up" : "chevron.down"
        case .delete: "trash"
        }
    }

    private func help(for action: RowAction) -> String {
        switch action {
        case .pin: clip.isPinned ? strings.unpin : strings.pin
        case .promote: strings.saveAsPromptTooltip
        case .edit: strings.edit
        case .expand: isExpanded ? strings.collapse : strings.expand
        case .delete: strings.delete
        }
    }

    /// An image row shows the picture in the chip slot; everything else shows a
    /// type glyph.
    ///
    /// When you can see the image, an icon saying "this is an image" is spent
    /// space — and the slot is exactly the size a thumbnail wants, so the row
    /// gains a real preview at zero cost to the preview text beside it.
    @ViewBuilder
    private var leadingChip: some View {
        if let image = ThumbnailCache.image(for: clip) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: metrics.chip, height: metrics.chip)
                .clipShape(
                    RoundedRectangle(cornerRadius: metrics.radiusSM - 1, style: .continuous)
                )
                .overlay {
                    // A hairline keeps a light-coloured screenshot from bleeding
                    // into the panel behind it.
                    RoundedRectangle(cornerRadius: metrics.radiusSM - 1, style: .continuous)
                        .strokeBorder(
                            isSelected ? theme.accent.opacity(0.5) : Token.Border.subtle,
                            lineWidth: 0.5
                        )
                }
        } else {
            TypeChip(kind: kind, isSelected: isSelected)
        }
    }

    /// The right-hand cluster. Meta and actions occupy the *same* 66 pt so the
    /// preview's truncation point never moves when a row is hovered (§5.2).
    private var trailingCluster: some View {
        ZStack(alignment: .trailing) {
            if isHovering || isSelected {
                // Generated from `clip.rowActions` — the same array the reducer
                // is handed — so the button the ring is on and the button `⏎`
                // runs are the same button by construction, not by agreement.
                HStack(spacing: 2 * metrics.scale) {
                    ForEach(clip.rowActions) { action in
                        RowActionButton(
                            symbol: symbol(for: action),
                            help: help(for: action),
                            isDestructive: action == .delete,
                            isActive: action == .pin && clip.isPinned,
                            isFocused: focusedAction == action,
                            action: { onAction(action) }
                        )
                    }
                }
            } else {
                HStack(spacing: 4 * metrics.scale) {
                    // Pinned state stays visible when not hovered (§7) — it is
                    // a property of the row, not an action on it.
                    if clip.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: metrics.pinGlyph))
                            .foregroundStyle(theme.accent.opacity(0.8))
                    }
                    Text(strings.ageLabel(for: clip.createdAt))
                        .font(metrics.metaFont)
                        .foregroundStyle(Token.Foreground.faint)
                }
            }
        }
        .frame(width: metrics.actionCluster, alignment: .trailing)
    }

    @ViewBuilder
    private var expansion: some View {
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            Hairline()
                .padding(.vertical, 6 * metrics.scale)

            if let expandedImage, let image = NSImage(data: expandedImage) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: metrics.expansionMaxHeight)
                    .clipShape(
                        RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                    )
            } else if let expandedText {
                ScrollView {
                    Text(expandedText)
                        .font(metrics.expandedFont)
                        .foregroundStyle(Token.Foreground.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: metrics.expansionMaxHeight)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8 * metrics.scale) {
                if let size = clip.pixelSizeLabel {
                    Text(size)
                }
                if let source = clip.sourceApp {
                    Text(source)
                }
                Spacer(minLength: 0)
                Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(metrics.microFont)
            .foregroundStyle(Token.Foreground.faint)
        }
        .padding(.bottom, 2)
    }
}

/// Preview text with matched runs tinted.
///
/// Highlighting matters more than it looks: in a filtered list of near-identical
/// entries, the tinted run is often the only thing distinguishing two rows.
struct HighlightedText: View {
    @Environment(\.theme) private var theme

    let text: String
    let query: String
    let font: Font

    var body: some View {
        Text(attributed)
            .font(font)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = Token.Foreground.primary

        let ranges = Matcher.highlightRanges(of: query, in: text)
        for range in ranges {
            guard let bounds = Range(range, in: result) else { continue }
            result[bounds].foregroundColor = theme.accent
            result[bounds].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }
}
