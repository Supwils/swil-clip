import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey.
///
/// Carbon's `RegisterEventHotKey` is used directly. It is the only mechanism
/// Apple provides — there is still no modern replacement in 2026, which is why
/// every clipboard manager, launcher and window tiler on the platform ends up
/// here. The popular Swift packages are wrappers over these same four calls, so
/// the spec's decision was to make the ~90 lines visible rather than take a
/// dependency to hide them.
///
/// Main-actor bound: Carbon's event target is the main run loop, and the handler
/// touches UI.
@MainActor
final class GlobalHotkey {
    /// A hotkey as the user configured it.
    struct Combination: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32

        static let defaultShortcut = Combination(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )

        /// Parse the v1 settings format (`"cmd+shift+v"`) so a migrated
        /// preference keeps working without the user re-recording it.
        init?(v1String: String) {
            var modifiers: UInt32 = 0
            var key: UInt32?

            for token in v1String.lowercased().split(separator: "+").map(String.init) {
                switch token.trimmingCharacters(in: .whitespaces) {
                case "cmd", "command", "meta": modifiers |= UInt32(cmdKey)
                case "shift": modifiers |= UInt32(shiftKey)
                case "alt", "option", "opt": modifiers |= UInt32(optionKey)
                case "ctrl", "control": modifiers |= UInt32(controlKey)
                default:
                    guard let code = Combination.keyCode(forCharacter: token) else { return nil }
                    key = code
                }
            }
            guard let key, modifiers != 0 else { return nil }
            self.keyCode = key
            self.modifiers = modifiers
        }

        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// Human-readable form for the settings UI.
        var displayString: String {
            var parts: [String] = []
            if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
            if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
            if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
            if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
            parts.append(Combination.character(forKeyCode: keyCode).uppercased())
            return parts.joined()
        }

        private static let characterMap: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab,
        ]

        static func keyCode(forCharacter character: String) -> UInt32? {
            characterMap[character].map(UInt32.init)
        }

        static func character(forKeyCode code: UInt32) -> String {
            characterMap.first { UInt32($0.value) == code }?.key ?? "?"
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onFire: (() -> Void)?

    /// Four-char code identifying our hotkey among any others in the process.
    private static let signature: OSType = 0x5357_4C43 // 'SWLC'

    /// Explicit teardown. Not a `deinit`: under Swift 6 a nonisolated `deinit`
    /// may not touch main-actor state, and the Carbon handles are exactly that.
    /// The instance lives for the process, so this is only used by tests.
    func tearDown() {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Register `combination`, replacing any previous registration.
    ///
    /// Returns `false` when the combination is already claimed by the system or
    /// another app. That is a normal outcome, not an error — the caller shows it
    /// in settings rather than failing to launch, because a clipboard manager
    /// that refuses to start over a taken shortcut is worse than one whose
    /// shortcut needs changing.
    @discardableResult
    func register(_ combination: Combination, onFire: @escaping () -> Void) -> Bool {
        unregister()
        self.onFire = onFire

        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        hotKeyRef = reference
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // `self` is passed unretained: the handler is removed in `deinit`, so it
        // cannot outlive the object it points at.
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                guard id.signature == GlobalHotkey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotkey.onFire?() }
                return noErr
            },
            1, &spec, context, &eventHandler
        )
    }
}
