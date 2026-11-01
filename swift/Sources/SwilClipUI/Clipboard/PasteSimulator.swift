import AppKit
import CoreGraphics

/// Writes to the pasteboard and, optionally, synthesises `⌘V`.
enum PasteSimulator {
    /// Place text on the general pasteboard.
    ///
    /// The caller marks the write as ours first, so the poller does not read it
    /// back as a brand-new clip.
    static func write(text: String, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func write(imageData: Data, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: .png)
    }

    /// Synthesise `⌘V` into whichever app is frontmost.
    ///
    /// Requires Accessibility. Callers must check `AccessibilityPermission`
    /// first — posting without it fails silently, which is exactly the failure
    /// v1 shipped (SC-06).
    ///
    /// Events go to `.cghidEventTap` so they enter at the same point as real
    /// hardware and are seen by every app, including those that read the HID
    /// stream directly.
    static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Suppress this process's own event handling for the synthesised pair,
        // so the panel cannot observe and react to its own keystroke.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
