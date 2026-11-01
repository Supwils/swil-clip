import Foundation

/// The product's user-visible identity.
///
/// ## One place to change the name
///
/// Everything the user reads — the menu-bar menu, the login-item toggle, the
/// fatal alert, the settings footer, the `.app` in Finder, the DMG — comes from
/// here, and here comes from `CFBundleName`, which `scripts/bundle.sh` writes
/// from a single `PRODUCT_NAME` line. Renaming the product is that one line
/// plus a rebuild. There is no string literal to hunt for.
///
/// ## What deliberately does *not* follow the name
///
/// Two identifiers are frozen at `swilclip` and must stay that way, because
/// macOS keys durable state off them rather than off anything the user sees:
///
/// - **`CFBundleIdentifier`** — the Keychain ACL that grants this app access to
///   the encryption key is bound to it, as are the `UserDefaults` domain and the
///   `SMAppService` login-item registration. Changing it loses the key, and
///   losing the key loses every encrypted row.
/// - **the Application Support directory** (`StorageLocations`) — the database
///   and image sidecars live there.
///
/// Neither is ever shown to a user, so a rename does not need them. See the
/// header of `scripts/bundle.sh`.
enum Brand {
    /// Used when there is no `Info.plist`: `swift run`, and the tests. A
    /// bundled app never reaches it.
    private static let fallbackName = "SwilClip"

    static let name: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return value?.isEmpty == false ? value! : fallbackName
    }()

    static let shortVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()

    /// `SwilClip 2.0.0`, for the settings footer.
    static var nameAndVersion: String { "\(name) \(shortVersion)" }
}
