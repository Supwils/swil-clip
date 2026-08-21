import SwiftUI
import SwilClipCore

/// Write or edit a prompt.
///
/// Two fields, and the title is pre-filled from the body's first line with the
/// cursor already on it — `⏎` accepts, typing overrides. Recording friction is
/// what decides whether a personal tool gets used, and "think of a name" is the
/// step that stops people saving things.
struct PromptEditorView: View {
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    let prompt: PromptItem?
    let onCancel: () -> Void
    let onSave: (String, String) -> Void

    @State private var title: String
    @State private var body_: String
    /// Whether the user has taken control of the title. Until they do, it keeps
    /// tracking the body so pasting a new body does not leave a stale name.
    @State private var titleIsManual: Bool
    @FocusState private var focus: Field?

    private enum Field { case title, body }

    /// The window is built by ``PanelController`` and the frame by this view.
    /// One constant so they cannot drift into a sheet with a scroll bar or a
    /// margin of dead space.
    static let preferredSize = CGSize(width: 460, height: 420)

    init(prompt: PromptItem?, onCancel: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        self.prompt = prompt
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: prompt?.title ?? "")
        _body_ = State(initialValue: prompt?.body ?? "")
        _titleIsManual = State(initialValue: prompt != nil)
    }

    private var isValid: Bool {
        !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            VStack(alignment: .leading, spacing: 12) {
                field(label: strings.fieldTitle) {
                    TextField(strings.titlePlaceholder, text: $title)
                        .textFieldStyle(.plain)
                        .font(Token.Typography.body)
                        .focused($focus, equals: .title)
                        .onChange(of: title) { _, _ in
                            if focus == .title { titleIsManual = true }
                        }
                }

                field(label: strings.fieldBody) {
                    TextEditor(text: $body_)
                        .font(Token.Typography.body)
                        .scrollContentBackground(.hidden)
                        .focused($focus, equals: .body)
                        .frame(minHeight: 180)
                        .onChange(of: body_) { _, newValue in
                            guard !titleIsManual else { return }
                            title = PromptTitle.propose(from: newValue)
                        }
                }
            }
            .padding(Token.Space.edge + 4)

            Spacer(minLength: 0)
            Hairline()
            footer
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        // Same stacking rule as AppShell: the tint has to be *over* the
        // vibrancy view, or a bright window behind the sheet shows through it.
        .background {
            ZStack {
                VisualEffectBackground(material: .sheet, cornerRadius: 0)
                Token.Surface.popover
            }
        }
        .onAppear { focus = prompt == nil ? .body : .title }
    }

    private var header: some View {
        HStack {
            Text(prompt == nil ? strings.newPromptTitle : strings.editPromptTitle)
                .font(Token.Typography.sectionLabel)
                .foregroundStyle(Token.Foreground.primary)
            Spacer()
            Text(strings.characterCount(body_.count))
                .font(Token.Typography.meta)
                .foregroundStyle(Token.Foreground.faint)
        }
        .padding(.horizontal, Token.Space.edge + 4)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            KeyHint(keys: ["⎋"], label: strings.hintCancel)
            KeyHint(keys: ["⌘", "⏎"], label: strings.hintSave)
            Spacer()
            Button(strings.cancel, action: onCancel)
                .buttonStyle(.plain)
                .font(Token.Typography.body)
                .foregroundStyle(Token.Foreground.muted)
                .keyboardShortcut(.cancelAction)

            Button(strings.save) { onSave(title, body_) }
                .buttonStyle(.plain)
                .font(Token.Typography.body)
                .foregroundStyle(isValid ? theme.onAccent : Token.Foreground.faint)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    isValid ? theme.accent : Token.Surface.soft,
                    in: RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
                )
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, Token.Space.edge + 4)
        .padding(.vertical, 12)
    }

    private func field(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Token.Typography.groupHeading)
                .tracking(label.allSatisfy(\.isASCII) ? 0.9 : 0)
                .foregroundStyle(Token.Foreground.subtle)
            content()
                .padding(8)
                .background(
                    Token.Surface.sunk,
                    in: RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
                        .strokeBorder(Token.Border.subtle, lineWidth: 0.5)
                }
        }
    }
}
