import CryptoKit
import Foundation
import Security

/// An `OSStatus` in `Error` clothing. `OSStatus` is `Int32`, which cannot be a
/// `Result` failure on its own, and the exact code is the whole point here —
/// "absent" and "locked" must stay distinguishable all the way up.
public struct KeychainStatus: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: OSStatus

    public init(_ code: OSStatus) { self.code = code }

    public static let itemNotFound = KeychainStatus(errSecItemNotFound)

    public var description: String {
        let message = SecCopyErrorMessageString(code, nil) as String? ?? "unknown"
        return "OSStatus \(code) (\(message))"
    }
}

/// Raw Keychain primitives, abstracted so the decision logic in
/// ``KeychainKeyStore`` can be tested without touching the real Keychain —
/// which would prompt, and whose failure modes are the entire point here.
public protocol KeychainBackend: Sendable {
    /// Returns the stored bytes, or the `OSStatus` explaining why not.
    func read(service: String, account: String) -> Result<Data, KeychainStatus>
    func write(_ data: Data, service: String, account: String) -> OSStatus
}

public enum KeyStoreError: Error, Equatable {
    /// The Keychain refused the read for a reason other than "no such item":
    /// locked keychain, a denied access prompt, an ACL mismatch after
    /// re-signing, a transient Security.framework failure.
    case unreadable(KeychainStatus)
    case unwritable(KeychainStatus)
    /// An item exists but is not a valid 256-bit key.
    case corruptKeyMaterial
}

/// Loads — or on genuine first run, creates — the per-user history key.
///
/// ## The rule this type exists to enforce
///
/// **`errSecItemNotFound` is the only read outcome that means "no key exists
/// yet."** Every other failure must propagate.
///
/// Treating a locked keychain or a denied prompt as "absent" would generate a
/// fresh key, and the next write would seal history under it — permanently
/// orphaning everything sealed under the real key. The user would see an empty
/// history and no error. This is the single most destructive bug this codebase
/// can have, so the check is narrow, explicit, and tested.
public struct KeychainKeyStore<Backend: KeychainBackend>: Sendable {
    public static var defaultService: String { "com.supwilsoft.swilclip" }
    public static var defaultAccount: String { "history-encryption-key-v1" }

    static var keyByteCount: Int { 32 }

    private let backend: Backend
    private let service: String
    private let account: String

    public init(
        backend: Backend,
        service: String = KeychainKeyStore.defaultService,
        account: String = KeychainKeyStore.defaultAccount
    ) {
        self.backend = backend
        self.service = service
        self.account = account
    }

    public func loadOrCreateKey() throws -> SymmetricKey {
        switch backend.read(service: service, account: account) {
        case .success(let data):
            guard data.count == Self.keyByteCount else {
                throw KeyStoreError.corruptKeyMaterial
            }
            return SymmetricKey(data: data)

        case .failure(.itemNotFound):
            // The one and only branch permitted to mint a new key.
            let fresh = SymmetricKey(size: .bits256)
            let bytes = fresh.withUnsafeBytes { Data($0) }
            let status = backend.write(bytes, service: service, account: account)
            guard status == errSecSuccess else {
                throw KeyStoreError.unwritable(KeychainStatus(status))
            }
            return fresh

        case .failure(let status):
            throw KeyStoreError.unreadable(status)
        }
    }
}

/// The real Keychain, backing the login keychain's generic-password class.
public struct SystemKeychain: KeychainBackend {
    public init() {}

    public func read(service: String, account: String) -> Result<Data, KeychainStatus> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return .failure(KeychainStatus(status)) }
        guard let data = item as? Data else { return .failure(.init(errSecDecode)) }
        return .success(data)
    }

    public func write(_ data: Data, service: String, account: String) -> OSStatus {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // The key is only ever needed while the user is at the machine, and
            // must never sync to another device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(attributes as CFDictionary, nil)
    }
}

public typealias SystemKeychainKeyStore = KeychainKeyStore<SystemKeychain>
