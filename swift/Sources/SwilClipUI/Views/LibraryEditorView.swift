import SwiftUI
import SwilClipCore

/// Write or edit a library entry.
///
/// The title is pre-filled from the body's first line with the cursor already
/// on it — `⏎` accepts, typing overrides. Recording friction is what decides
/// whether a personal tool gets used, and "think of a name" is the step that
/// stops people saving things.
///
/// The collection picker is also the *only* "move between collections"
/// affordance. Saving writes membership like any other field, so there is no
/// second code path anywhere that could disagree about where an entry lives.
struct LibraryEditorView: View {
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    let entry: LibraryEntry?
    let collections: [LibraryCollection]
    let onCancel: () -> Void
    /// `(title, body, collectionID)`.
    let onSave: (String, String, String) -> Void

    @State private var title: String
    @State private var body_: String
    @State private var collectionID: String
    /// Whether the user has taken control of the title. Until they do, it keeps
    /// tracking the body so pasting a new body does not leave a stale name.
    @State private var titleIsManual: Bool
    @FocusState private var focus: Field?

    /// Ordered, because `⇥` walks them in this order and the order is the
    /// reading order of the form.
    private enum Field: CaseIterable { case title, body, collection }

    /// The window is built by ``PanelController`` and the frame by this view.
    /// One constant so they cannot drift into a sheet with a scroll bar or a
    /// margin of dead space.
    static let preferredSize = CGSize(width: 460, height: 420)

    init(
        entry: LibraryEntry?,
        collections: [LibraryCollection],
        initialCollectionID: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, String) -> Void
    ) {
        self.entry = entry
        self.collections = collections
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: entry?.title ?? "")
        _body_ = State(initialValue: entry?.body ?? "")
        _collectionID = State(initialValue: entry?.collectionID ?? initialCollectionID)
        _titleIsManual = State(initialValue: entry != nil)
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

                field(label: strings.fieldCollection) {
                    Picker("", selection: $collectionID) {
                        ForEach(collections) { collection in
                            Label(
                                collection.isUnreadable
                                    ? strings.collectionUnreadable : collection.name,
                                systemImage: collection.symbol.rawValue
                            )
                            .tag(collection.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .focused($focus, equals: .collection)
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
        .onAppear { focus = entry == nil ? .body : .title }
        // The editor owns its keyboard the way the panel does. Without this,
        // AppKit's own focus ring decides where ⇥ goes — and a picker the
        // keyboard cannot reach is a control that does not exist for anyone
        // driving this app the way it is meant to be driven. `roadmap.md` 2.2
        // recorded the editor as the one place in the app that needed a mouse;
        // a third field is what made fixing it non-optional.
        .onKeyPress(.tab) {
            let order = Field.allCases
            guard let current = focus, let index = order.firstIndex(of: current) else {
                focus = .title
                return .handled
            }
            focus = order[(index + 1) % order.count]
            return .handled
        }
    }

    private var header: some View {
        HStack {
            Text(entry == nil ? strings.newItemTitle : strings.editItemTitle)
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

            Button(strings.save) { onSave(title, body_, collectionID) }
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
