import AppKit
import CryptoKit
import SwilClipCore

/// Wires the app together and owns everything that must outlive a window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: Settings!
    private var model: AppModel!
    private var panelController: PanelController!
    private var statusItem: StatusItemController!
    private let hotkey = GlobalHotkey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: menu bar only. No Dock icon, no ⌘Tab entry. Also declared
        // as LSUIElement in Info.plist; doing both means a bundle-less debug run
        // behaves the same as the shipped app.
        NSApp.setActivationPolicy(.accessory)

        settings = Settings()
        // Before any window exists, so the first paint is already correct —
        // a panel that flashes dark then turns light is worse than either.
        settings.appearance.apply()
        settings.onAppearanceChange = { $0.apply() }
        // Rebinding in Settings has to reach Carbon, or the field lies.
        settings.onHotkeyChange = { [weak self] _ in self?.registerHotkey() }

        do {
            let locations = try StorageLocations.standard()
            let keyStore = SystemKeychainKeyStore(backend: SystemKeychain())
            let key = try keyStore.loadOrCreateKey()
            let store = try LocalStore(locations: locations, key: key)

            model = AppModel(store: store, settings: settings)
            panelController = PanelController(model: model, settings: settings)

            Task { await bootstrap(store: store, locations: locations, key: key) }
        } catch {
            // Without a key or a database there is no app. Say so plainly rather
            // than launching into a panel that can never show anything — an
            // empty history is exactly what a silent failure would look like.
            presentFatal(error)
            return
        }

        statusItem = StatusItemController(
            strings: { [weak self] in self?.settings.strings ?? Strings(.english) },
            onToggle: { [weak self] in self?.panelController.toggle() },
            onSettings: { [weak self] in self?.panelController.showSettings() }
        )

        registerHotkey()
    }

    /// First-launch work: migrate v1 data, then start watching the pasteboard.
    private func bootstrap(
        store: LocalStore,
        locations: StorageLocations,
        key: SymmetricKey
    ) async {
        do {
            let summary = try await LegacyImporter().importIfNeeded(
                into: store,
                from: locations.legacyHistoryURL,
                cipher: FieldCipher(key: key),
                limit: settings.historyLimit
            )
            if let summary {
                NSLog("\(Brand.name): imported \(summary.imported) entries from v1")
                if let legacy = summary.legacySettings {
                    settings.adoptLegacy(legacy)
                    registerHotkey()
                }
            }
        } catch {
            // The import failed and, by design, did not mark itself done — the
            // next launch tries again. The v1 file is untouched either way.
            NSLog("\(Brand.name): legacy import deferred — \(error)")
        }
        await model.start()
    }

    private func registerHotkey() {
        let registered = hotkey.register(settings.hotkey) { [weak self] in
            self?.panelController.toggle()
        }
        // Recorded on `settings` rather than only logged: a shortcut that
        // another app already owns silently does nothing, and the one place the
        // user will look for why is the field they just typed it into.
        settings.reportHotkeyRegistration(registered)
        if !registered {
            NSLog("\(Brand.name): hotkey \(settings.hotkey.displayString) is already claimed")
        }
    }

    private func presentFatal(_ error: Error) {
        // `settings` is built before anything that can fail, so the one message
        // the user may ever see from a broken launch is still in their language.
        let strings = settings?.strings ?? Strings(.system)
        let alert = NSAlert()
        alert.messageText = strings.fatalTitle(Brand.name)
        alert.informativeText = strings.fatalBody(Brand.name, detail: "\(error)")
        alert.alertStyle = .critical
        alert.addButton(withTitle: strings.quit)
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// MARK: - Entry point

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
