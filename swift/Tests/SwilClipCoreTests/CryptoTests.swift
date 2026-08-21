import CryptoKit
import Foundation
import Security
import Testing

@testable import SwilClipCore

// MARK: - FieldCipher

@Suite("FieldCipher")
struct FieldCipherTests {
    private let cipher = FieldCipher(key: SymmetricKey(size: .bits256))

    @Test("round-trips arbitrary bytes")
    func roundTripsData() throws {
        let plaintext = Data((0..<4096).map { UInt8($0 % 256) })
        let sealed = try cipher.seal(plaintext)
        #expect(try cipher.open(sealed) == plaintext)
    }

    @Test("round-trips text, including CJK and emoji")
    func roundTripsText() throws {
        let plaintext = "请优化语言描述，降低 AI 感 — 🎯 git rebase -i HEAD~3"
        let sealed = try cipher.seal(plaintext)
        #expect(try cipher.openString(sealed) == plaintext)
    }

    @Test("round-trips an empty value")
    func roundTripsEmpty() throws {
        let sealed = try cipher.seal(Data())
        #expect(try cipher.open(sealed).isEmpty)
    }

    @Test("identical plaintexts seal to different ciphertexts")
    func nonceIsFresh() throws {
        // A reused nonce under one key breaks GCM outright. Sealing twice must
        // never produce identical bytes.
        let a = try cipher.seal("same")
        let b = try cipher.seal("same")
        #expect(a != b)
        #expect(try cipher.openString(a) == "same")
        #expect(try cipher.openString(b) == "same")
    }

    @Test("rejects a tampered ciphertext instead of returning garbage")
    func rejectsTamperedCiphertext() throws {
        var sealed = try cipher.seal("secret token")
        sealed[sealed.count - 1] ^= 0xFF // flip a bit in the auth tag
        #expect(throws: FieldCipher.Failure.authenticationFailed) {
            _ = try cipher.open(sealed)
        }
    }

    @Test("rejects a value sealed under a different key")
    func rejectsWrongKey() throws {
        let sealed = try cipher.seal("secret token")
        let other = FieldCipher(key: SymmetricKey(size: .bits256))
        #expect(throws: FieldCipher.Failure.authenticationFailed) {
            _ = try other.open(sealed)
        }
    }

    @Test("rejects bytes that are not a sealed box")
    func rejectsMalformed() {
        #expect(throws: FieldCipher.Failure.malformed) {
            _ = try cipher.open(Data([0x01, 0x02, 0x03]))
        }
    }
}

// MARK: - KeychainKeyStore

/// A scriptable stand-in for the Keychain. The real one prompts, and its
/// failure modes are exactly what needs testing.
private final class FakeKeychain: KeychainBackend, @unchecked Sendable {
    var readResult: Result<Data, KeychainStatus>
    var writeStatus: OSStatus = errSecSuccess
    private(set) var written: Data?
    private(set) var writeCount = 0

    init(readResult: Result<Data, KeychainStatus>) {
        self.readResult = readResult
    }

    func read(service: String, account: String) -> Result<Data, KeychainStatus> { readResult }

    func write(_ data: Data, service: String, account: String) -> OSStatus {
        written = data
        writeCount += 1
        return writeStatus
    }
}

@Suite("KeychainKeyStore")
struct KeychainKeyStoreTests {
    private func store(_ backend: FakeKeychain) -> KeychainKeyStore<FakeKeychain> {
        KeychainKeyStore(backend: backend)
    }

    @Test("returns the existing key without writing")
    func returnsExistingKey() throws {
        let existing = Data(repeating: 0xAB, count: 32)
        let backend = FakeKeychain(readResult: .success(existing))

        let key = try store(backend).loadOrCreateKey()

        #expect(key.withUnsafeBytes { Data($0) } == existing)
        #expect(backend.writeCount == 0)
    }

    @Test("creates a key only when the item is genuinely absent")
    func createsOnNotFound() throws {
        let backend = FakeKeychain(readResult: .failure(.itemNotFound))

        let key = try store(backend).loadOrCreateKey()

        #expect(key.bitCount == 256)
        #expect(backend.writeCount == 1)
        #expect(backend.written?.count == 32)
    }

    /// The load-bearing test. A locked keychain, a denied prompt or an ACL
    /// mismatch must surface as an error — never as "no key yet", which would
    /// mint a fresh key and orphan every sealed row on disk.
    @Test(
        "never rekeys on a non-absence failure",
        arguments: [
            errSecInteractionNotAllowed, // keychain locked
            errSecAuthFailed,            // user denied the prompt
            errSecUserCanceled,          // user dismissed the prompt
            errSecMissingEntitlement,    // ACL mismatch after re-signing
            errSecIO,                    // transient Security.framework failure
            errSecDecode,
        ] as [OSStatus]
    )
    func neverRekeysOnOtherFailures(status: OSStatus) {
        let backend = FakeKeychain(readResult: .failure(KeychainStatus(status)))

        #expect(throws: KeyStoreError.unreadable(KeychainStatus(status))) {
            _ = try store(backend).loadOrCreateKey()
        }
        #expect(backend.writeCount == 0, "a failed read must never mint a key")
    }

    @Test("rejects key material of the wrong length rather than using it")
    func rejectsCorruptKeyMaterial() {
        let backend = FakeKeychain(readResult: .success(Data(repeating: 0x01, count: 16)))

        #expect(throws: KeyStoreError.corruptKeyMaterial) {
            _ = try store(backend).loadOrCreateKey()
        }
        #expect(backend.writeCount == 0)
    }

    @Test("surfaces a failed write instead of returning an unpersisted key")
    func surfacesWriteFailure() {
        let backend = FakeKeychain(readResult: .failure(.itemNotFound))
        backend.writeStatus = errSecDuplicateItem

        #expect(throws: KeyStoreError.unwritable(KeychainStatus(errSecDuplicateItem))) {
            _ = try store(backend).loadOrCreateKey()
        }
    }
}
