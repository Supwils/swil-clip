import AppKit
import SwilClipCore

/// Unwraps `NSEvent` into the parameters ``KeyMapping`` decides on.
///
/// This is the entire AppKit surface of the keyboard model, and it deliberately
/// makes no decisions — every rule lives in `SwilClipCore`, where it is a unit
/// test rather than something only discoverable by pressing keys.
enum KeyboardAdapter {
    static func command(
        for event: NSEvent,
        isSearching: Bool,
        tabSwitch: KeyBinding
    ) -> KeyCommand? {
        KeyMapping.command(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: modifiers(from: event),
            isSearching: isSearching,
            tabSwitch: tabSwitch
        )
    }

    private static func modifiers(from event: NSEvent) -> KeyModifiers {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}
