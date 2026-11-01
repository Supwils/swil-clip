import AppKit
import SwiftUI
import SwilClipCore

/// Owns the panel window and everything about showing and hiding it.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let settings: Settings
    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(model: AppModel, settings: Settings) {
        self.model = model
        self.settings = settings
        super.init()

        model.onDismiss = { [weak self] in self?.hide() }
        model.onEditItem = { [weak self] entry, collectionID in
            self?.presentEditor(for: entry, startingIn: collectionID)
        }
        model.onOpenSettings = { [weak self] in self?.presentSettings() }
        settings.onPanelSizeChange = { [weak self] in self?.applyPanelSize() }
    }

    // MARK: - Presentation

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        // Order matters: the frontmost app must be recorded *before* the panel
        // takes focus, or restoration has nothing to restore to.
        model.focusTarget.capture()
        model.prepareForPresentation()

        let panel = existingOrNewPanel()
        // The size preference can change while the panel is closed, so the frame
        // is reconciled on every presentation rather than only at creation.
        let desired = Metrics(size: settings.panelSize)
        let size = NSSize(width: desired.panelWidth, height: desired.panelHeight)
        if panel.frame.size != size { panel.setContentSize(size) }
        panel.setFrameOrigin(resolveOrigin(panelSize: size))
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        // An accessory app has to ask, or a borderless panel never gets keys.
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    /// Open the panel and put the preferences sheet on it.
    ///
    /// The sheet is attached to the panel, so the panel has to be up first —
    /// which is why the menu-bar item cannot simply call `presentSettings()`.
    /// It used to call `show()` alone, and "Settings…" opened the clipboard.
    func showSettings() {
        if !isVisible { show() }
        presentSettings()
    }

    /// Resize an open panel when the size preference changes.
    ///
    /// `show()` already reconciles the frame, which covers a change made while
    /// the panel is closed. But the size control lives in a sheet *on* the
    /// panel, so the common case is changing it while it is open — and without
    /// this the content redrew at the new scale inside the old window until the
    /// next summon.
    func applyPanelSize() {
        guard let panel, panel.isVisible else { return }
        let desired = Metrics(size: settings.panelSize)
        let size = NSSize(width: desired.panelWidth, height: desired.panelHeight)
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
        panel.setFrameOrigin(resolveOrigin(panelSize: size))
    }

    func hide() {
        removeKeyMonitor()
        guard let panel, panel.isVisible else { return }
        // Remember where the user left it, but only if they actually moved it.
        settings.panelOrigin = panel.frame.origin
        panel.orderOut(nil)
        model.focusTarget.restore()
    }

    private func existingOrNewPanel() -> FloatingPanel {
        if let panel { return panel }

        let initial = Metrics(size: settings.panelSize)
        let rect = NSRect(
            x: 0, y: 0, width: initial.panelWidth, height: initial.panelHeight
        )
        let panel = FloatingPanel(contentRect: rect)
        // The gear goes through the model like every other command, so the
        // click and the keyboard route are one path rather than two.
        let root = PanelRootView(model: model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = rect
        panel.contentView = hosting
        panel.delegate = self
        self.panel = panel
        return panel
    }

    /// Resolve the panel on the display that currently contains the pointer.
    ///
    /// A remembered position may be restored only when it belongs to this same
    /// display. Looking for it across every attached display made a valid saved
    /// coordinate override the summon display, effectively pinning the panel to
    /// whichever monitor it had last been dragged on.
    private func resolveOrigin(panelSize: CGSize) -> CGPoint {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return .zero }
        return PanelPlacement.origin(
            forCursor: cursor,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            savedOrigin: settings.panelOrigin
        )
    }

    // MARK: - Keyboard

    /// One local monitor for the whole panel.
    ///
    /// Not `.onKeyPress` on a SwiftUI view: that routes through focus, and the
    /// moment two things can hold focus, "which one owns the arrow keys" becomes
    /// a runtime question. One monitor, one reducer, one answer.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            // While a sheet or the editor is up, it owns the keyboard.
            guard self.editorWindow == nil, self.settingsWindow == nil else { return event }

            // The inline editor works the same way, minus its two exits.
            if self.model.inlineEdit != nil {
                // An input method mid-composition owns Esc and Return: they
                // cancel or commit the candidate, not the edit.
                if let text = self.panel?.firstResponder as? NSTextView, text.hasMarkedText() {
                    return event
                }
                switch KeyMapping.inlineEditCommand(
                    keyCode: event.keyCode, modifiers: KeyboardAdapter.modifiers(from: event)
                ) {
                case .save: Task { await self.model.commitInlineEdit() }
                case .cancel: self.model.cancelInlineEdit()
                case nil: return event
                }
                return nil
            }

            guard let command = KeyboardAdapter.command(
                for: event,
                isSearching: self.model.selection.isSearching,
                tabSwitch: self.settings.tabSwitchKey
            ) else { return event }

            self.model.handle(command)
            return nil // consumed
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Clicking outside dismisses, the way every macOS popover behaves.
    func windowDidResignKey(_ notification: Notification) {
        guard editorWindow == nil, settingsWindow == nil else { return }
        hide()
    }

    // MARK: - Secondary windows

    private func presentEditor(for entry: LibraryEntry?, startingIn collectionID: String) {
        guard editorWindow == nil else { return }

        let editor = LibraryEditorView(
            entry: entry,
            collections: model.collections,
            initialCollectionID: collectionID,
            onCancel: { [weak self] in self?.dismissEditor() },
            onSave: { [weak self] title, body, target in
                guard let self else { return }
                Task {
                    await self.model.saveItem(
                        id: entry?.id, title: title, body: body, collectionID: target
                    )
                    self.dismissEditor()
                }
            }
        )

        let window = Self.makeSheetWindow(
            size: LibraryEditorView.preferredSize,
            content: Localized(settings: settings) { editor }
        )
        editorWindow = window
        panel?.beginSheet(window) { [weak self] _ in self?.editorWindow = nil }
    }

    private func dismissEditor() {
        guard let editorWindow else { return }
        panel?.endSheet(editorWindow)
        self.editorWindow = nil
    }

    private func presentSettings() {
        guard settingsWindow == nil else { return }
        let view = SettingsView(settings: settings, model: model) { [weak self] in
            self?.dismissSettings()
        }
        let window = Self.makeSheetWindow(size: SettingsView.preferredSize, content: view)
        settingsWindow = window
        panel?.beginSheet(window) { [weak self] _ in self?.settingsWindow = nil }
    }

    private func dismissSettings() {
        guard let settingsWindow else { return }
        panel?.endSheet(settingsWindow)
        self.settingsWindow = nil
    }

    private static func makeSheetWindow(size: CGSize, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: AnyView(content))
        return window
    }
}
