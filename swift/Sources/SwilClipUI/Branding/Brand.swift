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

    /// The commit the bundle was built from, `-dirty` if from a working tree.
    /// Written by `scripts/bundle.sh`; absent under `swift run` and the tests.
    static let build: String? = {
        Bundle.main.object(forInfoDictionaryKey: "SwilClipBuild") as? String
    }()

    /// `SwilClip 2.1.0 (a1b2c3d)`, for the settings footer. The hash is what
    /// tells two builds of the same version apart.
    static var nameAndVersion: String {
        build.map { "\(name) \(shortVersion) (\($0))" } ?? "\(name) \(shortVersion)"
    }
}
