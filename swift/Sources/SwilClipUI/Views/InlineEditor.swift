import SwiftUI
import SwilClipCore

/// The text editor that replaces an expanded row's contents while it is being
/// edited.
///
/// Shared by both row kinds, so a clip and a library entry edit the same way.
/// It owns no keys of its own: `⌘⏎` and `⎋` are caught by the panel's key
/// monitor (see ``KeyMapping/inlineEditCommand(keyCode:modifiers:)``), and the
/// buttons here call the same two closures.
struct InlineEditor: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * metrics.scale) {
            TextEditor(text: $text)
                .font(metrics.expandedFont)
                .foregroundStyle(Token.Foreground.primary)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(4 * metrics.scale)
                .frame(minHeight: 72 * metrics.scale, maxHeight: metrics.expansionMaxHeight)
                .background(
                    Token.Surface.sunk,
                    in: RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                )
                .overlay {
                    // Accent rather than the subtle border: this is the one place
                    // in the panel where typing goes into a row instead of into
                    // the search query, and it should look like it.
                    RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.6), lineWidth: 0.5)
                }

            HStack(spacing: 8 * metrics.scale) {
                Text(strings.characterCount(text.count))
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    HStack(spacing: 3 * metrics.scale) {
                        Text(strings.cancel)
                        Text("⎋").foregroundStyle(Token.Foreground.faint)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Token.Foreground.muted)

                Button(action: onSave) {
                    HStack(spacing: 3 * metrics.scale) {
                        Text(strings.save)
                        Text("⌘⏎").opacity(0.7)
                    }
                    .foregroundStyle(isValid ? theme.onAccent : Token.Foreground.faint)
                    .padding(.horizontal, 8 * metrics.scale)
                    .padding(.vertical, 2 * metrics.scale)
                    .background(
                        isValid ? theme.accent : Token.Surface.soft,
                        in: RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
            .font(metrics.microFont)
            .foregroundStyle(Token.Foreground.faint)
        }
        .onAppear { isFocused = true }
    }
}

/// The small "edit" affordance in an expanded row's meta line — the mouse
/// route to the same command as `⇧E`.
struct InlineEditButton: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3 * metrics.scale) {
                Image(systemName: "pencil")
                Text(strings.edit)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accent)
        .help(strings.editInlineTooltip)
    }
}

/// Everything a row needs to host the inline editor, in one value so the two
/// row views take one parameter instead of four.
struct InlineEditHooks {
    /// The draft, when *this* row is the one being edited.
    let draft: Binding<String>?
    let begin: () -> Void
    let save: () -> Void
    let cancel: () -> Void
}
