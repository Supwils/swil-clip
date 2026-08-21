import AppKit
import Observation
import SwilClipCore

// KeyBinding and PanelSize are the two rebindable/​resizable knobs added in v2.

/// User preferences, in `UserDefaults`.
///
/// Not in the encrypted database: none of it is sensitive, and settings must
/// stay readable even when the Keychain is not — otherwise a locked keychain
/// would cost the user their hotkey as well as their history.
@Observable
final class Settings {
    enum Key {
        static let hotkeyCode = "hotkey.keyCode"
        static let hotkeyModifiers = "hotkey.modifiers"
        static let historyLimit = "history.limit"
        static let autoPaste = "paste.auto"
        static let panelOriginX = "panel.originX"
        static let panelOriginY = "panel.originY"
        // No launchAtLogin key: SMAppService.mainApp.status is the state, and a
        // stored copy would drift the moment the user toggles the login item in
        // System Settings. See LoginItem.
        static let panelSize = "panel.size"
        static let tabSwitchKeyCode = "keys.tabSwitch.keyCode"
        static let tabSwitchModifiers = "keys.tabSwitch.modifiers"
        static let language = "ui.language"
        static let appearance = "ui.appearance"
        static let accentHue = "ui.accentHue"
        static let panelTint = "ui.panelTint"
    }

    /// Offered in the UI. Unlike v1 these are not a safety valve — per-row
    /// encryption made writes O(1) — so the choice is purely "how much history
    /// is useful to me".
    static let historyLimitChoices = [50, 100, 200, 500, 1000]

    private let defaults: UserDefaults

    /// The global summon shortcut.
    ///
    /// Carbon holds the real registration, and nothing observes this object on
    /// its behalf — so a change has to be announced. Without that the settings
    /// field showed the new keycap while the old combination kept firing, which
    /// is a settings screen telling the user something untrue.
    var hotkey: GlobalHotkey.Combination {
        didSet {
            guard hotkey != oldValue else { return }
            defaults.set(Int(hotkey.keyCode), forKey: Key.hotkeyCode)
            defaults.set(Int(hotkey.modifiers), forKey: Key.hotkeyModifiers)
            onHotkeyChange?(hotkey)
        }
    }

    /// Set by `AppDelegate`; see ``hotkey``.
    var onHotkeyChange: ((GlobalHotkey.Combination) -> Void)?

    /// Whether the summon shortcut is actually registered.
    ///
    /// Another app can already own a combination, and `RegisterEventHotKey`
    /// then fails. Reporting that only to the console meant the shortcut simply
    /// did not work with no way to find out why.
    private(set) var hotkeyIsRegistered = true

    func reportHotkeyRegistration(_ registered: Bool) {
        hotkeyIsRegistered = registered
    }

    var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }

    /// When on, `⏎` also synthesises `⌘V`. Off by default: it needs
    /// Accessibility, and pasting into the wrong field is a worse first
    /// impression than one extra keystroke.
    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Key.autoPaste) }
    }

    /// How large the panel is. Changing it rescales the whole design system,
    /// not just the window — see ``Metrics``.
    var panelSize: PanelSize {
        didSet {
            defaults.set(panelSize.rawValue, forKey: Key.panelSize)
            // A remembered position belongs to the old dimensions. Keeping it
            // would place a Large panel using a Small panel's corner and push it
            // off the edge it was previously clear of.
            if panelSize != oldValue { panelOrigin = nil }
            onPanelSizeChange?()
        }
    }

    /// Set by `PanelController`, which owns the window the size applies to.
    var onPanelSizeChange: (() -> Void)?

    /// Key that switches between the Clipboard and Prompts tabs.
    ///
    /// Rebindable because `⇥` is consumed by some input methods, and because a
    /// chord is muscle memory for some people.
    var tabSwitchKey: KeyBinding {
        didSet {
            defaults.set(Int(tabSwitchKey.keyCode), forKey: Key.tabSwitchKeyCode)
            defaults.set(tabSwitchKey.modifiers.rawValue, forKey: Key.tabSwitchModifiers)
        }
    }

    /// Which language the interface is drawn in.
    ///
    /// `.system` by default, so a Chinese user sees Chinese on first launch
    /// without knowing this setting exists — and an explicit choice then
    /// outranks the system for people whose Mac is not in the language they
    /// want to read software in.
    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    /// The catalog for the current language.
    ///
    /// Reading this from a SwiftUI body registers an observation on
    /// ``language``, so a switch re-renders every view that draws words with no
    /// notification of any kind. The one AppKit surface — the status-item menu —
    /// is rebuilt each time it opens, so it needs no signal either. That is why
    /// there is no `onLanguageChange` here: nothing would subscribe to it.
    var strings: Strings { Strings(language) }

    /// Light, dark, or follow the Mac.
    ///
    /// The only preference here that AppKit has to be *told* about: `NSApp`
    /// holds the appearance, and nothing observes this object on its behalf.
    /// Contrast ``language``, where `@Observable` already reaches every view
    /// that draws a word and the one AppKit surface rebuilds itself on open.
    var appearance: Appearance {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            onAppearanceChange?(appearance)
        }
    }

    /// Hue of the one colour that means "selected". See ``AccentPalette``.
    var accentHue: Double {
        didSet { defaults.set(AccentPalette.normalized(accentHue), forKey: Key.accentHue) }
    }

    /// How much of the desktop shows through the panel.
    var panelTint: PanelTint {
        didSet { defaults.set(panelTint.rawValue, forKey: Key.panelTint) }
    }

    /// The two colour decisions, bundled for the environment. Reading this from
    /// a SwiftUI body observes both, so a change re-renders whatever drew with
    /// it — the same mechanism as ``strings``.
    var theme: Theme { Theme(accentHue: accentHue, tint: panelTint) }

    /// Set by `AppDelegate`. See ``appearance`` for why this hook exists when
    /// the language deliberately has none.
    var onAppearanceChange: ((Appearance) -> Void)?

    /// Where the panel was last moved to, if the user dragged it.
    var panelOrigin: CGPoint? {
        didSet {
            guard let panelOrigin else {
                defaults.removeObject(forKey: Key.panelOriginX)
                defaults.removeObject(forKey: Key.panelOriginY)
                return
            }
            defaults.set(Double(panelOrigin.x), forKey: Key.panelOriginX)
            defaults.set(Double(panelOrigin.y), forKey: Key.panelOriginY)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedCode = defaults.object(forKey: Key.hotkeyCode) as? Int
        let storedModifiers = defaults.object(forKey: Key.hotkeyModifiers) as? Int
        if let storedCode, let storedModifiers {
            self.hotkey = .init(keyCode: UInt32(storedCode), modifiers: UInt32(storedModifiers))
        } else {
            self.hotkey = .defaultShortcut
        }

        self.historyLimit = (defaults.object(forKey: Key.historyLimit) as? Int) ?? 50
        self.autoPaste = defaults.bool(forKey: Key.autoPaste)

        self.panelSize = (defaults.string(forKey: Key.panelSize))
            .flatMap(PanelSize.init(rawValue:)) ?? .small

        self.language = (defaults.string(forKey: Key.language))
            .flatMap(AppLanguage.init(rawValue:)) ?? .system

        self.appearance = (defaults.string(forKey: Key.appearance))
            .flatMap(Appearance.init(rawValue:)) ?? .system
        self.panelTint = (defaults.string(forKey: Key.panelTint))
            .flatMap(PanelTint.init(rawValue:)) ?? .standard
        self.accentHue = AccentPalette.normalized(
            (defaults.object(forKey: Key.accentHue) as? Double) ?? AccentPalette.defaultHue
        )

        if let code = defaults.object(forKey: Key.tabSwitchKeyCode) as? Int {
            let raw = defaults.object(forKey: Key.tabSwitchModifiers) as? Int ?? 0
            self.tabSwitchKey = KeyBinding(
                keyCode: UInt16(code), modifiers: KeyModifiers(rawValue: raw)
            )
        } else {
            self.tabSwitchKey = .tab
        }

        if let x = defaults.object(forKey: Key.panelOriginX) as? Double,
           let y = defaults.object(forKey: Key.panelOriginY) as? Double {
            self.panelOrigin = CGPoint(x: x, y: y)
        } else {
            self.panelOrigin = nil
        }
    }

    /// Adopt the v1 preferences carried across by the importer, so the shortcut
    /// the author's fingers already know keeps working after the switch.
    ///
    /// Only fills values the user has not already set here — a preference
    /// expressed in v2 outranks one inherited from v1.
    func adoptLegacy(_ legacy: LegacyImporter.LegacySettings) {
        if defaults.object(forKey: Key.hotkeyCode) == nil,
           let shortcut = legacy.globalShortcut,
           let parsed = GlobalHotkey.Combination(v1String: shortcut) {
            hotkey = parsed
        }
        if defaults.object(forKey: Key.historyLimit) == nil, let limit = legacy.maxHistory {
            historyLimit = limit
        }
        if defaults.object(forKey: Key.autoPaste) == nil, let auto = legacy.autoPaste {
            autoPaste = auto
        }
    }
}
