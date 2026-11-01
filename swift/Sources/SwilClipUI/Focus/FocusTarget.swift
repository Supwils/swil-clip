import AppKit
import ApplicationServices

/// Remembers which app the user was in, and puts them back.
///
/// This is the whole reason the default `⏎` needs no Accessibility permission:
/// SwilClip restores focus and then stops. The user presses `⌘V` themselves,
/// wherever they actually want it. Auto Paste is the opt-in that goes further.
@MainActor
final class FocusTarget {
    private var previousApp: NSRunningApplication?

    /// Capture the frontmost app. Must be called **before** the panel is shown,
    /// because showing it makes SwilClip frontmost.
    func capture() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        // Never record ourselves; that would make restoration a no-op and leave
        // the user's caret stranded in a panel that just closed.
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApp = frontmost
    }

    /// Name of the captured app, for the row's source label.
    var capturedAppName: String? { previousApp?.localizedName }

    /// Return focus to the captured app.
    ///
    /// The completion runs only after activation has actually been requested,
    /// because synthesising `⌘V` into an app that is not yet frontmost delivers
    /// the keystroke to the wrong place — v1 learned this as a dropped first
    /// character.
    func restore(then completion: (@MainActor () -> Void)? = nil) {
        guard let previousApp, !previousApp.isTerminated else {
            completion?()
            return
        }
        previousApp.activate()

        guard let completion else { return }
        // A short settle before the synthetic keystroke. Activation is
        // asynchronous inside the window server; there is no completion
        // callback to wait on, so a small delay is the honest mechanism.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { completion() }
        }
    }

    func forget() { previousApp = nil }
}

/// Accessibility permission, which only Auto Paste needs.
enum AccessibilityPermission {
    /// Whether synthetic keystrokes will actually be delivered.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask the system to show its permission prompt.
    ///
    /// Closes SC-06: v1 posted the `⌘V` event regardless, `CGEvent.post`
    /// returned nothing, the command reported success, the panel hid — and
    /// nothing was pasted, with no way for the user to learn why. Auto Paste now
    /// refuses to switch on until this returns true.
    @discardableResult
    static func request() -> Bool {
        // The literal rather than `kAXTrustedCheckOptionPrompt`: that symbol is
        // an Objective-C `var`, so Swift 6 rejects it as shared mutable state.
        // The string is part of the framework's public contract and stable.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
