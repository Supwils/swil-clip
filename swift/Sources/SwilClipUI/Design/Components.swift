import SwiftUI
import SwilClipCore

// MARK: - Hairline

/// A 0.5 pt rule. §6: "try a hairline first" — a full-weight divider reads as a
/// frame and chops a 340 pt panel into boxes.
///
/// Deliberately *not* scaled with the panel: a hairline scaled to 0.75 pt stops
/// landing on a pixel boundary and renders as a fuzzy grey band.
struct Hairline: View {
    var color: Color = Token.Border.subtle

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 0.5)
    }
}

// MARK: - Keycap

/// The convex pill used in the keyboard hint reel (§4.7).
///
/// The illusion is two inset strokes — a light top edge and a dark bottom one.
/// A drop shadow would make it float; a keycap should look pressed *into* the
/// surface, not laid on top of it.
struct Keycap: View {
    @Environment(\.metrics) private var metrics
    let label: String

    var body: some View {
        Text(label)
            .font(metrics.keycapFont)
            .foregroundStyle(Token.Foreground.muted)
            .frame(minWidth: metrics.keycapMinSize, minHeight: metrics.keycapMinSize)
            .padding(.horizontal, 3 * metrics.scale)
            .background(
                Token.Surface.soft,
                in: RoundedRectangle(cornerRadius: metrics.radiusXS - 1, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radiusXS - 1, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Token.Bevel.keycapTop, Token.Bevel.keycapBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
    }
}

/// One `key → meaning` pair in the footer reel.
struct KeyHint: View {
    @Environment(\.metrics) private var metrics
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 2 * metrics.scale) {
            ForEach(keys, id: \.self) { Keycap(label: $0) }
            Text(label)
                .font(metrics.metaFont)
                .foregroundStyle(Token.Foreground.faint)
        }
    }
}

// MARK: - Type chip

/// The square that carries a content-kind glyph (§4.4).
///
/// 20 pt at Small — ratified over 24 and 28. At 340 pt wide, four points of chip
/// is four points of preview text.
struct TypeChip: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    let kind: ContentKind
    let isSelected: Bool

    private var symbol: String {
        switch kind {
        case .url: "link"
        case .email: "envelope"
        case .color: "paintpalette"
        case .json: "curlybraces"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .multiline: "text.alignleft"
        case .text: "textformat.abc"
        case .image: "photo"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.radiusSM - 1, style: .continuous)
            .fill(isSelected ? theme.accentSoft : Token.Surface.soft)
            .frame(width: metrics.chip, height: metrics.chip)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: metrics.chipGlyph, weight: .medium))
                    .foregroundStyle(isSelected ? theme.accent : Token.Foreground.muted)
            }
    }
}

// MARK: - Row action button

/// A row action, shown only when its row is hovered or selected (§4.5).
///
/// Always-visible actions would turn a dense list into a wall of icons; the
/// reserved cluster width (§5.2) keeps text from ever sliding underneath.
struct RowActionButton: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    let symbol: String
    let help: String
    var isDestructive = false
    var isActive = false
    /// The keyboard is on this button: `⏎` will run it.
    ///
    /// Drawn as a filled ring rather than a hover wash, because hover and focus
    /// can be on two different buttons at once and the user needs to know which
    /// one Return is aimed at.
    var isFocused = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.actionGlyph, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: metrics.actionButton, height: metrics.actionButton)
                .background(
                    wash,
                    in: RoundedRectangle(cornerRadius: metrics.radiusXS, style: .continuous)
                )
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: metrics.radiusXS, style: .continuous)
                            .strokeBorder(ring, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }

    /// Focus on the trash reads red, not accent. "Return will delete this" is
    /// the one thing in the panel worth spending a colour on.
    private var ring: Color { isDestructive ? Token.Status.destructive : theme.accent }

    private var wash: Color {
        if isFocused { return isDestructive ? Token.Status.destructiveSoft : theme.accentSoft }
        return isHovering ? Token.Surface.hover : .clear
    }

    private var tint: Color {
        if isDestructive {
            return isFocused || isHovering ? Token.Status.destructive : Token.Foreground.subtle
        }
        if isFocused || isActive { return theme.accent }
        return isHovering ? Token.Foreground.primary : Token.Foreground.subtle
    }
}

// MARK: - Selection background

/// Selected-row treatment: tinted fill, a hairline accent ring, and a 2 pt rail
/// on the leading edge.
///
/// The rail is what makes the selection findable at a glance in a dense list —
/// a fill alone is too subtle at 16 % opacity, and raising the opacity would
/// fight the glass.
struct SelectionBackground: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: metrics.radiusMD, style: .continuous)
                .fill(theme.selectionFill)
            RoundedRectangle(cornerRadius: metrics.radiusMD, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.35), lineWidth: 0.5)
            UnevenRoundedRectangle(
                topLeadingRadius: 1, bottomLeadingRadius: 1,
                bottomTrailingRadius: 0, topTrailingRadius: 0,
                style: .continuous
            )
            .fill(theme.accent)
            .frame(width: max(2, round(2 * metrics.scale)))
            .padding(.vertical, metrics.rowVertical)
        }
    }
}

// MARK: - Search field

/// The panel's search input.
///
/// §5.4 in the design system says this must exist only while searching. That
/// rule was written for a cmdk quirk that does not exist here, but the behaviour
/// it produced is right on its own terms: the panel opens showing history, not
/// an empty text field.
struct SearchField: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    let query: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6 * metrics.scale) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10 * metrics.scale, weight: .medium))
                .foregroundStyle(Token.Foreground.subtle)
            Text(query.isEmpty ? placeholder : query)
                .font(metrics.rowFont)
                .foregroundStyle(query.isEmpty ? Token.Foreground.faint : Token.Foreground.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            // A caret rather than a real NSTextField: the panel already owns the
            // keyboard, and giving a control first-responder status would mean
            // two things competing for every keystroke — the shape of the v1 bug.
            Caret()
        }
        .padding(.horizontal, 8 * metrics.scale)
        .padding(.vertical, 5 * metrics.scale)
        .background(
            Token.Surface.sunk,
            in: RoundedRectangle(cornerRadius: metrics.radiusMD, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radiusMD, style: .continuous)
                .strokeBorder(theme.accentRing, lineWidth: 0.5)
        }
        .padding(.horizontal, metrics.edge)
        .padding(.bottom, 4 * metrics.scale)
    }
}

/// A blinking insertion point.
private struct Caret: View {
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(theme.accent)
            .frame(width: max(1.5, 1.5 * metrics.scale), height: 12 * metrics.scale)
            .opacity(isVisible ? 1 : 0)
            .task {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    isVisible.toggle()
                }
            }
    }
}

// MARK: - Section divider

/// The line between the pinned group and everything below it.
///
/// A bare rule would be ambiguous — "why does the list break here?" — so it
/// carries a label. That costs one row's height *once*, and only when both
/// groups exist, which is cheaper than the same question every time the panel
/// opens. The label sits on the rule rather than above it, so the divider stays
/// one line tall in a 340 pt panel where vertical space is the scarce resource.
struct SectionDivider: View {
    @Environment(\.metrics) private var metrics
    let label: String

    var body: some View {
        HStack(spacing: 6 * metrics.scale) {
            Text(label.uppercased())
                .font(metrics.groupHeadingFont)
                .tracking(0.9)
                .foregroundStyle(Token.Foreground.faint)
            Hairline()
        }
        .padding(.horizontal, metrics.row)
        .padding(.top, 6 * metrics.scale)
        .padding(.bottom, 3 * metrics.scale)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    @Environment(\.metrics) private var metrics
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 6 * metrics.scale) {
            Image(systemName: symbol)
                .font(.system(size: 20 * metrics.scale, weight: .light))
                .foregroundStyle(Token.Foreground.faint)
            Text(title)
                .font(metrics.bodyFont)
                .foregroundStyle(Token.Foreground.muted)
            Text(hint)
                .font(metrics.metaFont)
                .foregroundStyle(Token.Foreground.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24 * metrics.scale)
    }
}
