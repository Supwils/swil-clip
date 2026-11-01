import SwiftUI
import SwilClipCore

/// Create, rename, re-icon, reorder and delete collections.
///
/// ## Why this is in Settings and not in the panel
///
/// Creating a tab is a few-times-a-year action; the panel is a
/// high-frequency surface that has to stay fast. ADR-0002 already paid once for
/// "the panel now has a mode", and a management UI inside it would be a second
/// instalment on the same debt.
///
/// ## Why it is its own file
///
/// `SettingsView` was already the largest file in the tree at 664 lines, and
/// this pane is a self-contained responsibility: it is the only place the tab
/// list is edited, and nothing else in Settings needs the model.
struct CollectionsPane: View {
    @Bindable var model: AppModel
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    @State private var pending: LibraryCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach(model.collections) { collection in
                row(collection)
            }

            if model.collections.isEmpty {
                // Reachable: every collection can be deleted. Say so plainly
                // rather than showing an empty box that reads like a bug.
                Text(strings.statusNoCollections)
                    .font(Token.Typography.meta)
                    .foregroundStyle(Token.Foreground.muted)
            }

            Text(strings.collectionCapHint(LibraryCollection.maximumCount))
                .font(Token.Typography.meta)
                .foregroundStyle(Token.Foreground.faint)
        }
        .confirmationDialog(
            pending.map { strings.deleteCollectionTitle(displayName($0)) } ?? "",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible
        ) {
            deletionButtons
        } message: {
            if let pending {
                Text(strings.deleteCollectionBody(count: model.entryCount(in: pending.id)))
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(strings.collectionsSection)
                    .font(Token.Typography.groupHeading)
                    .foregroundStyle(Token.Foreground.subtle)
                Text(strings.collectionsHint)
                    .font(Token.Typography.meta)
                    .foregroundStyle(Token.Foreground.faint)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.createCollection(name: "", symbol: .tag) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                model.collections.count >= LibraryCollection.maximumCount
                    ? Token.Foreground.faint : theme.accent
            )
            .help(strings.newCollectionTooltip)
            .disabled(model.collections.count >= LibraryCollection.maximumCount)
        }
    }

    private func row(_ collection: LibraryCollection) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: symbolBinding(collection)) {
                ForEach(CollectionSymbol.allCases) { symbol in
                    Image(systemName: symbol.rawValue).tag(symbol)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 66)

            TextField(strings.collectionNamePlaceholder, text: nameBinding(collection))
                .textFieldStyle(.plain)
                .font(Token.Typography.body)
                .foregroundStyle(
                    collection.isUnreadable ? Token.Foreground.faint : Token.Foreground.primary
                )

            Button { move(collection, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Token.Foreground.muted)
            .disabled(collection.position == 0)

            Button { move(collection, by: +1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Token.Foreground.muted)
            .disabled(collection.position == model.collections.count - 1)

            Button { pending = collection } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Token.Foreground.muted)
        }
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

    /// Two buttons, and no guessing which one was meant.
    ///
    /// The non-destructive one is listed first and is what the sheet suggests.
    /// Settings is a separate `NSHostingView`, so `u` does not reach it — the
    /// user would have to close Settings, return to the panel and press `u`.
    /// Backstopping data loss with a cross-window undo is too thin for a project
    /// whose stated ordering puts silent data loss above new features.
    @ViewBuilder
    private var deletionButtons: some View {
        if let collection = pending {
            let count = model.entryCount(in: collection.id)
            let destination = model.collections.first { $0.id != collection.id }

            if count > 0, let destination {
                Button(strings.moveEntriesButton(to: displayName(destination), count: count)) {
                    delete(collection, movingTo: destination.id)
                }
            }
            Button(
                count > 0 ? strings.deleteCollectionButton(count: count) : strings.delete,
                role: .destructive
            ) {
                delete(collection, movingTo: nil)
            }
            Button(strings.cancel, role: .cancel) { pending = nil }
        }
    }

    private func delete(_ collection: LibraryCollection, movingTo destination: String?) {
        pending = nil
        Task { await model.deleteCollectionWithUndo(collection, movingEntriesTo: destination) }
    }

    private func move(_ collection: LibraryCollection, by offset: Int) {
        var ids = model.collections.map(\.id)
        guard let index = ids.firstIndex(of: collection.id),
              ids.indices.contains(index + offset)
        else { return }
        ids.swapAt(index, index + offset)
        Task { try? await model.reorderCollections(ids) }
    }

    private func displayName(_ collection: LibraryCollection) -> String {
        collection.isUnreadable ? strings.collectionUnreadable : collection.name
    }

    private func nameBinding(_ collection: LibraryCollection) -> Binding<String> {
        Binding(
            get: { collection.name },
            set: { newValue in
                var updated = collection
                updated.name = newValue
                Task { await model.updateCollection(updated) }
            }
        )
    }

    private func symbolBinding(_ collection: LibraryCollection) -> Binding<CollectionSymbol> {
        Binding(
            get: { collection.symbol },
            set: { newValue in
                var updated = collection
                updated.symbol = newValue
                Task { await model.updateCollection(updated) }
            }
        )
    }
}
