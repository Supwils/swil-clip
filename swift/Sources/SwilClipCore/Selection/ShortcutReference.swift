import Foundation

/// Every way the user can drive the app, as data.
///
/// ## Why this exists rather than a hand-written list in the settings view
///
/// A shortcut list written by hand in a view is a second source of truth for
/// the keyboard, and it starts drifting the day someone adds a key. Here the
/// reference is structure — actions, groups, and which keys reach them — and
/// ``KeyCommand/documentedAction`` maps every command the reducer understands
/// onto one of these. That switch is exhaustive, so a new command does not
/// compile until it has somewhere in this list to live.
///
/// The *words* are not here. Labels come from ``Strings``, which means the
/// reference is one shape in both languages and neither can gain a row the
/// other lacks.
public enum ShortcutGroup: String, CaseIterable, Sendable, Identifiable {
    /// Works even when the panel is closed.
    case global
    case navigate
    /// Acts on the row the cursor is on.
    case act
    case search
    case prompts
    case mouse

    public var id: String { rawValue }
}

/// One documented capability. Deliberately finer-grained than ``KeyCommand``:
/// it also covers the things you can only do with the mouse or the menu bar.
public enum ShortcutAction: String, CaseIterable, Sendable, Identifiable {
    // Global
    case summon
    case menuBar

    // Navigate
    case moveUp
    case moveDown
    case moveToFirst
    case moveToLast
    case switchTab
    case focusTabs
    case dismiss

    // Act on the selection
    case confirm
    case toggleExpand
    case togglePin
    case deleteItem
    case promoteToPrompt
    case undo
    case focusRowActions
    case activateRowAction

    // Search
    case beginSearch
    case typeToFind
    case lettersAreTextWhileSearching
    case deleteQueryCharacter
    case clearQuery

    // Prompts
    case newPrompt
    case openSettings
    case editPrompt
    case savePromptEditor
    case cancelPromptEditor

    // Mouse
    case clickSelect
    case doubleClickConfirm
    case dragPanel
    case rowButtons

    public var id: String { rawValue }

    public var group: ShortcutGroup {
        switch self {
        case .summon, .menuBar: .global
        case .moveUp, .moveDown, .moveToFirst, .moveToLast,
             .switchTab, .focusTabs, .dismiss: .navigate
        case .confirm, .toggleExpand, .togglePin, .deleteItem, .promoteToPrompt, .undo,
             .focusRowActions, .activateRowAction: .act
        case .beginSearch, .typeToFind, .lettersAreTextWhileSearching,
             .deleteQueryCharacter, .clearQuery: .search
        case .newPrompt, .editPrompt, .savePromptEditor, .cancelPromptEditor: .prompts
        case .openSettings: .global
        case .clickSelect, .doubleClickConfirm, .dragPanel, .rowButtons: .mouse
        }
    }
}

/// An action plus what to draw in the reference's left column.
///
/// Either keycaps or a glyph, never both — the mouse and menu-bar entries have
/// no key to print, and an empty column next to them would read as a gap rather
/// than as "this one is not a keystroke".
///
/// The glyph is an SF Symbol name. That is a UI detail in an otherwise
/// UI-free module, but it is the same kind of value as `keys`: an identifier
/// for something printed, chosen once, next to the action it belongs to.
/// Splitting it into a parallel table in the view is how the two drift apart.
public struct ShortcutEntry: Sendable, Identifiable, Equatable {
    public let action: ShortcutAction
    public let keys: [String]
    public let symbol: String?

    public var id: String { action.rawValue }

    public init(_ action: ShortcutAction, keys: [String]) {
        self.action = action
        self.keys = keys
        self.symbol = nil
    }

    public init(_ action: ShortcutAction, symbol: String) {
        self.action = action
        self.keys = []
        self.symbol = symbol
    }
}

public struct ShortcutSection: Sendable, Identifiable, Equatable {
    public let group: ShortcutGroup
    public let entries: [ShortcutEntry]

    public var id: String { group.rawValue }
}

public enum ShortcutReference {
    /// The full reference, with the two rebindable keys filled in from the
    /// user's actual settings.
    ///
    /// Passing them in rather than reading a preference is what keeps this
    /// pure — and it is also why the printed keycap can never disagree with the
    /// key that really works.
    ///
    /// - Parameters:
    ///   - summon: `Settings.hotkey.displayString`.
    ///   - tabSwitch: `Settings.tabSwitchKey.displayString`.
    public static func sections(summon: String, tabSwitch: String) -> [ShortcutSection] {
        [
            ShortcutSection(group: .global, entries: [
                ShortcutEntry(.summon, keys: [summon]),
                ShortcutEntry(.menuBar, symbol: "menubar.arrow.up.rectangle"),
                ShortcutEntry(.openSettings, symbol: "gearshape"),
            ]),
            ShortcutSection(group: .navigate, entries: [
                ShortcutEntry(.moveUp, keys: ["↑"]),
                ShortcutEntry(.moveDown, keys: ["↓"]),
                ShortcutEntry(.moveToFirst, keys: ["⌘↑"]),
                ShortcutEntry(.moveToLast, keys: ["⌘↓"]),
                ShortcutEntry(.switchTab, keys: [tabSwitch]),
                ShortcutEntry(.focusTabs, keys: ["↑"]),
                ShortcutEntry(.dismiss, keys: ["⎋"]),
            ]),
            ShortcutSection(group: .act, entries: [
                ShortcutEntry(.confirm, keys: ["⏎"]),
                ShortcutEntry(.toggleExpand, keys: ["e"]),
                ShortcutEntry(.togglePin, keys: ["p"]),
                ShortcutEntry(.deleteItem, keys: ["d"]),
                ShortcutEntry(.promoteToPrompt, keys: ["⇧", "S"]),
                ShortcutEntry(.undo, keys: ["u"]),
                ShortcutEntry(.focusRowActions, keys: ["←", "→"]),
                ShortcutEntry(.activateRowAction, keys: ["⏎"]),
            ]),
            ShortcutSection(group: .search, entries: [
                ShortcutEntry(.beginSearch, keys: ["s", "/"]),
                ShortcutEntry(.typeToFind, keys: ["A–Z"]),
                ShortcutEntry(.lettersAreTextWhileSearching, symbol: "textformat.abc"),
                ShortcutEntry(.deleteQueryCharacter, keys: ["⌫"]),
                ShortcutEntry(.clearQuery, keys: ["⎋"]),
            ]),
            ShortcutSection(group: .prompts, entries: [
                ShortcutEntry(.newPrompt, keys: ["n"]),
                ShortcutEntry(.editPrompt, symbol: "pencil"),
                ShortcutEntry(.savePromptEditor, keys: ["⌘", "⏎"]),
                ShortcutEntry(.cancelPromptEditor, keys: ["⎋"]),
            ]),
            ShortcutSection(group: .mouse, entries: [
                ShortcutEntry(.clickSelect, symbol: "cursorarrow.click"),
                ShortcutEntry(.doubleClickConfirm, symbol: "cursorarrow.click.2"),
                ShortcutEntry(.rowButtons, symbol: "hand.point.up.left"),
                ShortcutEntry(.dragPanel, symbol: "hand.draw"),
            ]),
        ]
    }

    /// Every action the reference actually lists. Used by the tests that keep
    /// this file honest.
    public static var documentedActions: Set<ShortcutAction> {
        Set(sections(summon: "⌘⇧V", tabSwitch: "⇥").flatMap(\.entries).map(\.action))
    }
}

// MARK: - Commands are documented by construction

extension KeyCommand {
    /// The reference entry that explains this command to the user.
    ///
    /// Exhaustive on purpose. Adding a case to ``KeyCommand`` breaks this
    /// switch, and the only way to fix it is to say where the new key is
    /// documented — which is exactly the drift this file exists to prevent.
    public var documentedAction: ShortcutAction {
        switch self {
        case .moveUp: .moveUp
        case .moveDown: .moveDown
        case .moveToFirst: .moveToFirst
        case .moveToLast: .moveToLast
        case .beginSearch: .beginSearch
        case .appendToQuery: .typeToFind
        case .deleteQueryCharacter: .deleteQueryCharacter
        case .clearQuery: .clearQuery
        case .switchTab: .switchTab
        case .confirm: .confirm
        case .deleteItem: .deleteItem
        case .togglePin: .togglePin
        case .toggleExpand: .toggleExpand
        case .undo: .undo
        case .newPrompt: .newPrompt
        case .promoteToPrompt: .promoteToPrompt
        case .editPrompt: .editPrompt
        case .moveLeft, .moveRight: .focusRowActions
        case .dismiss: .dismiss
        case .selectID: .clickSelect
        }
    }
}
