import AppKit
import ServiceManagement

/// Whether SwilClip starts when the user logs in.
///
/// ## Why there is no stored preference
///
/// The obvious implementation keeps a `Bool` in `UserDefaults` and calls
/// `register()` when it flips. That creates two sources of truth, and they drift
/// the first time the user opens **System Settings › General › Login Items** and
/// switches SwilClip off there — the app keeps showing "on" and never launches.
///
/// `SMAppService.mainApp.status` *is* the state. It is read live on every access
/// and never cached, which costs a cheap XPC round trip and buys a toggle that
/// cannot lie. This is the same rule as the selection reducer: one home for a
/// piece of state, no shadow copy.
///
/// ## Why this matters more than it looks
///
/// A clipboard manager that is not running is not failing loudly — it is
/// silently not recording. You find out the next time you press `⌘⇧V` and
/// nothing happens, and everything copied since the last reboot is gone. For a
/// tool whose whole value is "it was already there when I needed it", starting
/// at login is closer to a correctness property than a convenience.
enum LoginItem {
    enum State: Equatable {
        /// Registered and will launch at the next login.
        case enabled
        /// Not registered. The normal "off" state.
        case disabled
        /// Registered, but the user has to approve it in System Settings. macOS
        /// puts new login items here when the user has previously denied one.
        case requiresApproval
        /// The service is not installable from where the app currently lives —
        /// in practice, running from a build directory rather than /Applications.
        case unavailable

        var isOn: Bool { self == .enabled || self == .requiresApproval }
    }

    /// Read live. See the type documentation for why this is not cached.
    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    /// Turn the login item on or off.
    ///
    /// - Returns: the state afterwards, read back from the system rather than
    ///   assumed — `register()` can succeed and still land in `requiresApproval`.
    @discardableResult
    static func set(_ enabled: Bool) -> Result<State, Error> {
        do {
            if enabled {
                // Registering something already registered throws; treat an
                // existing registration as success rather than an error.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(state)
        } catch {
            return .failure(error)
        }
    }

    /// Open the pane where the user can approve or revoke the login item.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Whether the app is running from a location macOS will accept as a login
    /// item.
    ///
    /// `SMAppService` refuses to register an app outside `/Applications` (or the
    /// user's own Applications folder). Rather than let the toggle fail with an
    /// opaque error, the UI disables itself and says why.
    static var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
}
