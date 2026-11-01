import AppKit
import SwilClipCore

/// The menu-bar presence. With `LSUIElement` set, this is the app's only
/// permanent surface — there is no Dock icon and no ⌘Tab entry.
@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private let onToggle: () -> Void
    private let onSettings: () -> Void
    /// Read at the moment the menu opens rather than captured once. The menu is
    /// rebuilt on every open anyway, so a language switch needs no invalidation
    /// signal — it is already picked up the next time the menu is shown.
    private let strings: () -> Strings

    init(
        strings: @escaping () -> Strings,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.strings = strings
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            // A template image so macOS tints it for light, dark and the
            // menu-bar-behind-wallpaper cases in Tahoe.
            let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: Brand.name
            )
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick)
            // Left click toggles; right click opens the menu.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else {
            onToggle()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let strings = strings()
        let menu = NSMenu()
        menu.addItem(
            withTitle: strings.menuShow(Brand.name),
            action: #selector(menuToggle), keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: strings.menuSettings,
            action: #selector(menuSettings), keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: strings.menuQuit(Brand.name),
            action: #selector(menuQuit), keyEquivalent: "q"
        ).target = self

        // Attaching the menu to the item would make left-click open it too,
        // which is not what a toggle should do.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func menuToggle() { onToggle() }
    @objc private func menuSettings() { onSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
