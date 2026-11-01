import Foundation
import Testing

@testable import SwilClipCore
@testable import SwilClipUI

/// Roadmap 2.1.2: the callbacks are a manifest the tests can read.
@Suite("Shell wiring")
struct ShellWiringTests {
    /// The scan has to see the callbacks it is meant to police. If `@Observable`
    /// ever changes how it names storage, this fails loudly instead of letting
    /// ``unwiredAfterLaunchWiring()`` pass because it matched nothing.
    @MainActor
    @Test("reflection finds the callbacks we know about")
    func reflectionSeesCallbacks() throws {
        let temp = try TempModel()
        let modelNames = Set(Wiring.callbacks(in: temp.model).map(\.name))
        let settingsNames = Set(Wiring.callbacks(in: temp.settings).map(\.name))
        #expect(modelNames.isSuperset(of: ["onDismiss", "onEditItem", "onOpenSettings"]))
        #expect(settingsNames.isSuperset(of: [
            "onHotkeyChange", "onPanelSizeChange", "onAppearanceChange",
        ]))
    }

    @MainActor
    @Test("a fresh model and settings start with every callback unset")
    func freshObjectsAreUnwired() throws {
        let temp = try TempModel()
        #expect(!Wiring.unwired(in: temp.model).isEmpty)
        #expect(!Wiring.unwired(in: temp.settings).isEmpty)
    }

    /// The launch path minus the keychain and the window: exactly what
    /// `AppDelegate` connects. A callback added without wiring fails here.
    @MainActor
    @Test("after launch wiring, no callback is left unset")
    func unwiredAfterLaunchWiring() throws {
        let temp = try TempModel()
        let controller = PanelController(model: temp.model, settings: temp.settings)
        Wiring.connect(settings: temp.settings) {}

        #expect(Wiring.unwired(in: temp.model) == [])
        #expect(Wiring.unwired(in: temp.settings) == [])
        withExtendedLifetime(controller) {}
    }

    @MainActor
    @Test("changing the summon shortcut reaches the re-registration (SW-01)")
    func hotkeyChangeRebinds() throws {
        let temp = try TempModel()
        var rebinds = 0
        Wiring.connect(settings: temp.settings) { rebinds += 1 }

        temp.settings.hotkey = .init(keyCode: 8, modifiers: 768)
        #expect(rebinds == 1)
        // Assigning the same combination is not a change.
        temp.settings.hotkey = .init(keyCode: 8, modifiers: 768)
        #expect(rebinds == 1)
    }

    // MARK: - Routing

    @MainActor
    @Test("Esc on a quiet panel reaches onDismiss")
    func dismissRoutes() throws {
        let temp = try TempModel()
        var dismissed = false
        temp.model.onDismiss = { dismissed = true }
        temp.model.handle(.dismiss)
        #expect(dismissed)
    }

    @MainActor
    @Test("n on the clipboard opens a new entry aimed at the first collection")
    func newItemRoutes() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        var received: (LibraryEntry?, String)?
        temp.model.onEditItem = { received = ($0, $1) }

        temp.model.handle(.newItem)
        #expect(received?.0 == nil)
        #expect(received?.1 == LibraryCollection.Seed.prompts)
    }

    /// SW-02's neighbour: the gear is reached by arrowing up to the bar and
    /// along it, and `⏎` there must open settings rather than copy a row.
    @MainActor
    @Test("⏎ on the gear reaches onOpenSettings")
    func gearRoutes() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        var opened = false
        temp.model.onOpenSettings = { opened = true }

        temp.model.handle(.moveUp) // empty clipboard: straight to the tabs
        for _ in 0..<(temp.model.tabs.count + 1) { temp.model.handle(.moveRight) }
        #expect(temp.model.selection.focus == .topBar(.settings))
        temp.model.handle(.confirm)
        #expect(opened)
    }
}

/// Roadmap 2.1.4: every preference survives a relaunch.
///
/// Each key is a string typed by hand in two places — the `didSet` and the
/// `init`. A typo in either is invisible until a restart quietly forgets the
/// setting, which is exactly the kind of bug nobody files.
@Suite("Settings persistence")
struct SettingsPersistenceTests {
    @MainActor
    @Test("every preference written is read back by a fresh instance")
    func roundTrip() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-settings-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try #require(UserDefaults(suiteName: root.appendingPathComponent("prefs").path))

        let written = Settings(defaults: suite)
        written.hotkey = .init(keyCode: 8, modifiers: 2304)
        written.historyLimit = 500
        written.autoPaste = true
        written.panelSize = .large
        written.tabSwitchKey = KeyBinding(keyCode: KeyCode.tab, modifiers: .command)
        written.language = .chinese
        written.appearance = .dark
        written.accentHue = 140
        written.panelTint = .solid
        // After `panelSize`, whose `didSet` clears the remembered origin.
        written.panelOrigin = CGPoint(x: 120, y: 340)

        let read = Settings(defaults: suite)
        #expect(read.hotkey == written.hotkey)
        #expect(read.historyLimit == 500)
        #expect(read.autoPaste)
        #expect(read.panelSize == .large)
        #expect(read.tabSwitchKey == written.tabSwitchKey)
        #expect(read.language == .chinese)
        #expect(read.appearance == .dark)
        #expect(read.accentHue == AccentPalette.normalized(140))
        #expect(read.panelTint == .solid)
        #expect(read.panelOrigin == CGPoint(x: 120, y: 340))
    }

    @MainActor
    @Test("an empty domain yields the documented defaults")
    func defaults() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-settings-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = try #require(UserDefaults(suiteName: root.appendingPathComponent("prefs").path))

        let settings = Settings(defaults: suite)
        #expect(settings.hotkey == .defaultShortcut)
        #expect(settings.historyLimit == 50)
        #expect(!settings.autoPaste)
        #expect(settings.panelSize == .small)
        #expect(settings.tabSwitchKey == .tab)
        #expect(settings.panelOrigin == nil)
    }
}
