import Foundation

/// One of the buttons a row carries.
///
/// ## Why this is a type and not a button index
///
/// Focus travels with the *identity* of an action, never its position. A text
/// clip offers four buttons and an image clip three — walking from one to the
/// other with an index would silently slide focus from "save as prompt" onto
/// "expand", and one `⏎` later the user has run something they did not aim at.
/// That is the delete-wrong-row failure wearing a different hat, so the answer
/// is the same one: make the wrong state unrepresentable rather than guard
/// against it.
///
/// The rows render *from this list*, and ``SelectionReducer`` is handed the same
/// list. They cannot disagree about what the fourth button is, because neither
/// of them counts.
public enum RowAction: String, Sendable, Equatable, CaseIterable, Identifiable {
    case pin
    case promote
    case edit
    case expand
    case delete

    public var id: String { rawValue }

    /// The command this button stands for.
    ///
    /// Activating a focused button routes through here and back into
    /// ``SelectionReducer/reduce(_:_:visibleIDs:actions:)``, so `⏎` on the trash
    /// icon and pressing `d` are not two implementations of delete — they are
    /// one, reached two ways. In particular both compute the next selection
    /// *before* the removal, which is the property that keeps v1's bug dead.
    public var command: KeyCommand {
        switch self {
        case .pin: .togglePin
        case .promote: .promoteToPrompt
        case .edit: .editPrompt
        case .expand: .toggleExpand
        case .delete: .deleteItem
        }
    }
}

/// A stop in the top bar, left to right.
///
/// The bar is not just the two tabs: it also carries the controls that act on
/// the panel rather than on a row. Giving them stops is what makes "new prompt"
/// and "settings" reachable without knowing a letter — `n` was the only route
/// to the first and the mouse was the only route to the second.
public enum TopBarItem: String, Sendable, Equatable, CaseIterable, Identifiable {
    /// The Clipboard / Prompts pair. Which one is lit *is* `State.tab`;
    /// arrowing between them switches live, so they share one stop.
    case tabs
    /// `+`. Only present on the Prompts tab — a plus next to "Clipboard" would
    /// read as "add a clip", which is not a thing you can do.
    case newPrompt
    case settings

    public var id: String { rawValue }
}

extension PanelTab {
    /// The stops this tab's top bar actually draws, left to right.
    ///
    /// Derived rather than passed in, because unlike a row's buttons this
    /// depends only on state the reducer already holds. The bar renders from
    /// the same array — same rule as ``RowAction``, same reason.
    public var topBarItems: [TopBarItem] {
        self == .prompts ? [.tabs, .newPrompt, .settings] : [.tabs, .settings]
    }
}

/// Where the keyboard is, above and beyond *which row* is selected.
///
/// The panel has two bands a user can be in: the top bar, and the list. Inside
/// the list a row is either "the row" — where `⏎` copies, as it always has — or
/// one of its buttons.
public enum PanelFocus: Equatable, Sendable {
    /// The bar above the list. `←`/`→` move along it, `⏎` activates the stop.
    case topBar(TopBarItem)
    /// The list. `action == nil` means the row itself.
    case row(action: RowAction? = nil)

    /// The resting state: a row, no button singled out.
    public static let list = PanelFocus.row()
    /// Arriving in the top bar always lands on the tabs — the stop that is
    /// always there, whichever tab you came from.
    public static let tabs = PanelFocus.topBar(.tabs)

    public var focusedAction: RowAction? {
        if case .row(let action) = self { return action }
        return nil
    }

    public var topBarItem: TopBarItem? {
        if case .topBar(let item) = self { return item }
        return nil
    }

    public var isOnTopBar: Bool { topBarItem != nil }
    public var isOnTabs: Bool { self == .tabs }
}
