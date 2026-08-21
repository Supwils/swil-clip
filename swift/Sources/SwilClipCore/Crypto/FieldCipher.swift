import CryptoKit
import Foundation

/// Transparent at-rest encryption for a single stored value.
///
/// v1 sealed the entire history as one blob, so every mutation cost
/// O(entire history) — 167 ms once screenshots were involved, which is why that
/// version needed a 50-entry cap, a 10 MB per-clip rejection and a 32 MB total
/// budget just to stay usable. Sealing one value at a time makes a write O(1)
/// and lets all three limits go away.
///
/// Each sealed value carries its own random nonce, so identical plaintexts do
/// not produce identical ciphertexts and no nonce is ever reused under one key.
public struct FieldCipher: Sendable {
    public enum Failure: Error, Equatable {
        /// The stored bytes are not a well-formed sealed box.
        case malformed
        /// Authentication failed: wrong key, or the ciphertext was tampered with.
        case authenticationFailed
    }

    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public init(keyBytes: Data) {
        self.init(key: SymmetricKey(data: keyBytes))
    }

    /// Seal `plaintext` into a self-describing blob (nonce ‖ ciphertext ‖ tag).
    public func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        // `combined` is non-nil for the default 12-byte nonce, which `seal`
        // generates. Treating a nil as malformed keeps the API total.
        guard let combined = box.combined else { throw Failure.malformed }
        return combined
    }

    public func seal(_ string: String) throws -> Data {
        try seal(Data(string.utf8))
    }

    /// Open a blob produced by `seal`.
    ///
    /// A tampered or truncated value fails loudly. It must never fall back to
    /// returning the raw bytes: silently handing back ciphertext as if it were
    /// plaintext is how encrypted stores leak.
    public func open(_ sealed: Data) throws -> Data {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: sealed)
        } catch {
            throw Failure.malformed
        }
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            throw Failure.authenticationFailed
        }
    }

    public func openString(_ sealed: Data) throws -> String {
        let data = try open(sealed)
        guard let string = String(data: data, encoding: .utf8) else {
            throw Failure.malformed
        }
        return string
    }
}
