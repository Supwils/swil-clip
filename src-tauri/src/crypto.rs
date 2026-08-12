//! Transparent at-rest encryption for clipboard history.
//!
//! History entries frequently contain secrets (passwords, API tokens). We
//! persist the history blob encrypted with AES-256-GCM; the key lives in the
//! macOS login Keychain, so the on-disk JSON never holds plaintext.
//! Decryption happens in memory whenever the app reads history, so the UI and
//! paste flow still see the real values — nothing is dropped, masked or lost.

use aes_gcm::aead::{Aead, AeadCore, KeyInit, OsRng};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use base64::Engine;
use std::sync::OnceLock;

const KEYCHAIN_SERVICE: &str = "com.supwilsoft.swilclip";
const KEYCHAIN_ACCOUNT: &str = "history-encryption-key-v1";
const NONCE_LEN: usize = 12;
const KEY_LEN: usize = 32;

// Cached for the process lifetime so we touch the Keychain at most once per
// launch (avoids repeated access prompts and per-poll latency).
static KEY_CACHE: OnceLock<[u8; KEY_LEN]> = OnceLock::new();

/// Fetch the per-user history key, loading it from the Keychain or creating
/// and persisting a fresh random key on first run.
pub fn history_key() -> Result<[u8; KEY_LEN], String> {
    if let Some(k) = KEY_CACHE.get() {
        return Ok(*k);
    }
    let k = load_or_create_key()?;
    let _ = KEY_CACHE.set(k);
    Ok(k)
}

#[cfg(target_os = "macos")]
fn load_or_create_key() -> Result<[u8; KEY_LEN], String> {
    use security_framework::passwords::{get_generic_password, set_generic_password};

    // The ONLY read outcome that means "no key exists yet". Every other error
    // (locked keychain, user denying the access prompt, ACL mismatch from a
    // differently-signed binary, transient Security.framework failure) must
    // propagate: falling through to key generation would overwrite the real
    // key and permanently orphan all existing ciphertext.
    const ERR_SEC_ITEM_NOT_FOUND: i32 = -25300;

    match get_generic_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT) {
        Ok(existing) => {
            if existing.len() != KEY_LEN {
                // Wrong length → don't silently rekey (that would orphan
                // existing ciphertext); surface the problem instead.
                return Err("Existing history key in Keychain has unexpected length".to_string());
            }
            let mut k = [0u8; KEY_LEN];
            k.copy_from_slice(&existing);
            Ok(k)
        }
        Err(e) if e.code() == ERR_SEC_ITEM_NOT_FOUND => {
            // First run on this machine/account: generate and store a fresh key.
            let key: [u8; KEY_LEN] = Aes256Gcm::generate_key(OsRng).into();
            set_generic_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, &key)
                .map_err(|e| format!("Failed to store history key in Keychain: {e}"))?;
            Ok(key)
        }
        Err(e) => Err(format!(
            "Keychain read failed ({e}); refusing to touch the existing history key"
        )),
    }
}

#[cfg(not(target_os = "macos"))]
fn load_or_create_key() -> Result<[u8; KEY_LEN], String> {
    Err("History encryption is only implemented on macOS".to_string())
}

/// Encrypt `plaintext`, returning base64(nonce ‖ ciphertext+tag).
pub fn encrypt(plaintext: &[u8], key: &[u8; KEY_LEN]) -> Result<String, String> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));

    // Sized by the cipher's type-level NonceSize — cannot drift from NONCE_LEN
    // without failing the decrypt-side split below in tests.
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);

    let mut ciphertext = cipher
        .encrypt(&nonce, plaintext)
        .map_err(|_| "Encryption failed".to_string())?;

    // Prepend the nonce so decryption is self-contained.
    let mut blob = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    blob.extend_from_slice(&nonce);
    blob.append(&mut ciphertext);
    Ok(base64::engine::general_purpose::STANDARD.encode(blob))
}

/// Reverse of [`encrypt`]. Errors (rather than returning empty) on any
/// corruption or wrong-key condition, so callers never overwrite good data
/// with a blank history.
pub fn decrypt(b64: &str, key: &[u8; KEY_LEN]) -> Result<Vec<u8>, String> {
    let blob = base64::engine::general_purpose::STANDARD
        .decode(b64)
        .map_err(|e| format!("Bad ciphertext encoding: {e}"))?;
    if blob.len() < NONCE_LEN {
        return Err("Ciphertext too short".to_string());
    }
    let (nonce_bytes, ciphertext) = blob.split_at(NONCE_LEN);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    cipher
        .decrypt(Nonce::from_slice(nonce_bytes), ciphertext)
        .map_err(|_| "Decryption failed (wrong key or corrupt data)".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let key = [7u8; KEY_LEN];
        let msg = b"super secret api token: sk-abc123";
        let blob = encrypt(msg, &key).expect("encrypt");
        let out = decrypt(&blob, &key).expect("decrypt");
        assert_eq!(out, msg);
    }

    #[test]
    fn each_encryption_uses_a_fresh_nonce() {
        let key = [3u8; KEY_LEN];
        let a = encrypt(b"same", &key).unwrap();
        let b = encrypt(b"same", &key).unwrap();
        assert_ne!(a, b, "nonce reuse — identical ciphertext for identical input");
    }

    #[test]
    fn wrong_key_fails_instead_of_returning_garbage() {
        let blob = encrypt(b"data", &[1u8; KEY_LEN]).unwrap();
        assert!(decrypt(&blob, &[2u8; KEY_LEN]).is_err());
    }

    #[test]
    fn corrupt_input_errors() {
        assert!(decrypt("not-base64!!", &[0u8; KEY_LEN]).is_err());
        assert!(decrypt("AAAA", &[0u8; KEY_LEN]).is_err());
    }
}
