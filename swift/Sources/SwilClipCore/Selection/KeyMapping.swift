import Foundation

/// Which modifier keys were held. Mirrors the flags AppKit reports, without
/// depending on AppKit — that is what keeps the keyboard model testable.
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// Virtual key codes for the keys that mean something structural. Named because
/// a bare `126` in a switch is unreadable and unverifiable.
public enum KeyCode {
    public static let upArrow: UInt16 = 126
    public static let downArrow: UInt16 = 125
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let home: UInt16 = 115
    public static let end: UInt16 = 119
    public static let `return`: UInt16 = 36
    public static let enter: UInt16 = 76
    public static let escape: UInt16 = 53
    public static let tab: UInt16 = 48
    public static let delete: UInt16 = 51
    public static let space: UInt16 = 49
    public static let leftBracket: UInt16 = 33
    public static let rightBracket: UInt16 = 30

    /// Printable label for a key code, for the settings UI.
    static func symbol(for code: UInt16) -> String {
        switch code {
        case upArrow: "↑"
        case downArrow: "↓"
        case leftArrow: "←"
        case rightArrow: "→"
        case home: "↖"
        case end: "↘"
        case `return`, enter: "⏎"
        case escape: "⎋"
        case tab: "⇥"
        case delete: "⌫"
        case space: "␣"
        case leftBracket: "["
        case rightBracket: "]"
        default: letters[code] ?? "key \(code)"
        }
    }

    private static let letters: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]
}

/// A key plus modifiers, as a rebindable binding.
///
/// Used for in-panel shortcuts, which are matched here in pure code — unlike the
/// global summon hotkey, which has to go through Carbon.
public struct KeyBinding: Equatable, Sendable, Codable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Plain `⇥`. Chosen as the default because the panel owns its keyboard
    /// entirely — there is no focus ring for Tab to move between, so the key is
    /// free, and "Tab switches tab" needs no explaining.
    public static let tab = KeyBinding(keyCode: KeyCode.tab)

    public func matches(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    /// Human-readable form for the settings UI.
    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(KeyCode.symbol(for: keyCode))
        return parts.joined()
    }
}

extension KeyModifiers: Codable {}

/// Turns a keypress into a ``KeyCommand``.
///
/// Pure, and in `SwilClipCore` rather than the app target, so every rule below
/// is a unit test rather than something only discoverable by pressing keys. The
/// app target's only job is unwrapping `NSEvent` into these parameters.
public enum KeyMapping {
    /// - Parameters:
    ///   - characters: the text the keypress produces, with layout and dead-key
    ///     composition already applied. This is what makes CJK input work
    ///     without a special case.
    ///   - charactersIgnoringModifiers: the base key, used for command letters
    ///     so `⇧S` and `s` resolve to the same letter.
    ///   - isSearching: passed in rather than read from anywhere. In search mode
    ///     letters are text; outside it they are commands, and that single bit
    ///     decides most of this function.
    ///   - tabSwitch: the user's binding for switching tabs. Rebindable because
    ///     `⇥` is claimed by some input methods, and because a chord like `⌘⇥`
    ///     is muscle memory for some people.
    public static func command(
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: KeyModifiers,
        isSearching: Bool,
        tabSwitch: KeyBinding = .tab
    ) -> KeyCommand? {
        // The rebindable binding is checked first, so a user who maps it onto a
        // key this function would otherwise claim still gets tab switching.
        if tabSwitch.matches(keyCode: keyCode, modifiers: modifiers) { return .switchTab }

        // Control or Option means the combination belongs to the system or
        // another app. Swallowing those makes a panel feel like it eats input.
        guard !modifiers.contains(.control), !modifiers.contains(.option) else { return nil }
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)

        switch keyCode {
        case KeyCode.upArrow: return hasCommand ? .moveToFirst : .moveUp
        case KeyCode.downArrow: return hasCommand ? .moveToLast : .moveDown
        // Left and right stay bare. `⌘←` is left free rather than aliased onto
        // the same step: the panel should not claim a chord it has no use for.
        case KeyCode.leftArrow: return hasCommand ? nil : .moveLeft
        case KeyCode.rightArrow: return hasCommand ? nil : .moveRight
        case KeyCode.home: return .moveToFirst
        case KeyCode.end: return .moveToLast
        case KeyCode.return, KeyCode.enter: return .confirm
        case KeyCode.escape: return .dismiss
        case KeyCode.delete: return isSearching ? .deleteQueryCharacter : nil
        default: break
        }

        // ⌘-anything else belongs to the system: ⌘Q, ⌘W, ⌘,.
        guard !hasCommand else { return nil }

        if isSearching {
            guard let typed = characters, isTypable(typed) else { return nil }
            return .appendToQuery(typed)
        }

        switch charactersIgnoringModifiers?.lowercased() {
        case "s": return hasShift ? .promoteToPrompt : .beginSearch
        case "d": return .deleteItem
        case "p": return .togglePin
        case "e": return .toggleExpand
        case "u": return .undo
        case "n": return .newPrompt
        case "/": return .beginSearch
        default:
            // Type-to-find: any other printable key opens search with that
            // character, the way every macOS list behaves. `s` stays the
            // explicit opener because v1 trained that muscle memory.
            guard let typed = characters, isTypable(typed) else { return nil }
            return .appendToQuery(typed)
        }
    }

    /// Whether a string is real typed text rather than a function key.
    ///
    /// AppKit reports arrows, F-keys and friends as scalars in the Unicode
    /// private-use area; letting those into a search query would fill it with
    /// invisible characters that match nothing.
    static func isTypable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }
}
