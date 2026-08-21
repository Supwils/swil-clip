use std::sync::Mutex;
use tauri::{AppHandle, Manager};
use tauri_plugin_store::StoreExt;

use crate::clipboard::types::ClipItem;
use crate::crypto;
use crate::settings;

const STORE_PATH: &str = "clipboard_history.json";
/// Legacy plaintext key — read for one-time migration, then removed.
const STORE_KEY: &str = "history";
/// Current key: base64(nonce ‖ AES-256-GCM ciphertext) of the history array.
const STORE_KEY_ENC: &str = "history_enc";

/// Process-wide cache of the decrypted history, managed as Tauri state.
///
/// The backend is the single writer (poll thread + UI commands, both routed
/// through this module), so after the first disk load every read is served
/// from memory — without this, each clipboard copy and each UI mutation paid
/// a full decrypt+parse of the entire blob (and the frontend's post-mutation
/// refresh a second one), which gets material once images live in the array.
/// Holds the last successfully persisted state; never populated from a
/// failed load, so a transient error can't mask real data.
#[derive(Default)]
pub struct HistoryCache(Mutex<Option<Vec<ClipItem>>>);

fn current_max_history(app_handle: &AppHandle) -> usize {
    settings::get_settings(app_handle)
        .map(|s| settings::clamp_max_history(s.max_history))
        .unwrap_or(settings::DEFAULT_MAX_HISTORY)
}

pub fn get_history(app_handle: &AppHandle) -> Result<Vec<ClipItem>, String> {
    let cache = app_handle.state::<HistoryCache>();
    let mut guard = cache.0.lock().unwrap_or_else(|e| e.into_inner());

    if guard.is_none() {
        *guard = Some(load_history_from_disk(app_handle)?);
    }

    let mut items = guard.as_ref().expect("cache filled above").clone();
    drop(guard);

    // Stable sort: pinned items float to the top, relative order preserved within each group.
    items.sort_by(|a, b| b.pinned.cmp(&a.pinned));

    Ok(items)
}

fn load_history_from_disk(app_handle: &AppHandle) -> Result<Vec<ClipItem>, String> {
    let store = app_handle
        .store(STORE_PATH)
        .map_err(|e| format!("Failed to open store: {}", e))?;

    if let Some(enc) = store.get(STORE_KEY_ENC) {
        // Encrypted path. Propagate any decrypt/parse error rather than
        // returning empty — a transient failure must never let a later save
        // overwrite good data with a blank history.
        let b64 = enc.as_str().ok_or("Corrupt encrypted history blob")?;
        let key = crypto::history_key()?;
        let bytes = crypto::decrypt(b64, &key)?;
        serde_json::from_slice(&bytes).map_err(|e| format!("Failed to parse history: {}", e))
    } else if let Some(v) = store.get(STORE_KEY) {
        // Legacy plaintext (pre-encryption builds); the next save_history
        // re-persists it encrypted and drops the plaintext key. Strict parse
        // for the same overwrite-protection reason as above: this read feeds
        // a one-shot, irreversible migration, so silently loading a corrupt
        // value as an empty list would destroy the only copy on next save.
        serde_json::from_value(v).map_err(|e| format!("Failed to parse legacy history: {}", e))
    } else {
        Ok(Vec::new())
    }
}

pub fn save_history(app_handle: &AppHandle, items: &[ClipItem]) -> Result<(), String> {
    let store = app_handle
        .store(STORE_PATH)
        .map_err(|e| format!("Failed to open store: {}", e))?;

    let json = serde_json::to_vec(items)
        .map_err(|e| format!("Failed to serialize history: {}", e))?;
    let key = crypto::history_key()?;
    let blob = crypto::encrypt(&json, &key)?;

    store.set(STORE_KEY_ENC, blob);
    // Drop any leftover plaintext copy from a pre-encryption build so secrets
    // never linger on disk after migration.
    store.delete(STORE_KEY);
    store.save().map_err(|e| format!("Failed to save store: {}", e))?;

    let cache = app_handle.state::<HistoryCache>();
    *cache.0.lock().unwrap_or_else(|e| e.into_inner()) = Some(items.to_vec());

    Ok(())
}

/// Last-resort recovery: wipe the persisted history (both encrypted and
/// legacy plaintext keys) WITHOUT touching the crypto layer, so it works even
/// when the Keychain is unreachable — the one situation where clear_history
/// (which must encrypt an empty list) cannot.
pub fn reset_history(app_handle: &AppHandle) -> Result<(), String> {
    let store = app_handle
        .store(STORE_PATH)
        .map_err(|e| format!("Failed to open store: {}", e))?;

    store.delete(STORE_KEY_ENC);
    store.delete(STORE_KEY);
    store.save().map_err(|e| format!("Failed to save store: {}", e))?;

    let cache = app_handle.state::<HistoryCache>();
    *cache.0.lock().unwrap_or_else(|e| e.into_inner()) = Some(Vec::new());

    Ok(())
}

pub fn add_item(app_handle: &AppHandle, item: &ClipItem) -> Result<(), String> {
    let mut items = get_history(app_handle)?;

    // Preserve pin state when a previously-pinned item is re-copied.
    let was_pinned = items
        .iter()
        .find(|e| e.clip_type == item.clip_type && e.content == item.content)
        .map(|e| e.pinned)
        .unwrap_or(false);

    crate::store_logic::apply_dedup(&mut items, item);

    let mut new_item = item.clone();
    new_item.pinned = was_pinned;
    items.insert(0, new_item);
    crate::store_logic::enforce_max_history(&mut items, current_max_history(app_handle));
    crate::store_logic::enforce_byte_budget(
        &mut items,
        crate::store_logic::MAX_TOTAL_CONTENT_BYTES,
    );

    save_history(app_handle, &items)
}

pub fn pin_item(app_handle: &AppHandle, id: &str, pinned: bool) -> Result<(), String> {
    let mut items = get_history(app_handle)?;
    if let Some(item) = items.iter_mut().find(|i| i.id == id) {
        item.pinned = pinned;
    }
    save_history(app_handle, &items)
}

pub fn delete_item(app_handle: &AppHandle, id: &str) -> Result<(), String> {
    let mut items = get_history(app_handle)?;
    items.retain(|item| item.id != id);
    save_history(app_handle, &items)
}

pub fn clear_history(app_handle: &AppHandle) -> Result<(), String> {
    save_history(app_handle, &[])
}

/// Remove all non-pinned items and return them so the caller can track undo.
pub fn clear_unpinned(app_handle: &AppHandle) -> Result<Vec<ClipItem>, String> {
    let items = get_history(app_handle)?;
    let (pinned, unpinned): (Vec<ClipItem>, Vec<ClipItem>) =
        items.into_iter().partition(|i| i.pinned);
    save_history(app_handle, &pinned)?;
    Ok(unpinned)
}

/// Re-insert previously deleted items back into history.
///
/// Both caps are re-applied because this path GROWS the list. Restored entries
/// go to the front, so they survive an eviction and undo still does what it
/// says — what gets dropped is the oldest tail, exactly as on a fresh copy.
pub fn restore_items(app_handle: &AppHandle, restored: &[ClipItem]) -> Result<(), String> {
    let mut items = get_history(app_handle)?;
    for r in restored.iter().rev() {
        crate::store_logic::apply_dedup(&mut items, r);
        items.insert(0, r.clone());
    }
    crate::store_logic::enforce_max_history(&mut items, current_max_history(app_handle));
    crate::store_logic::enforce_byte_budget(
        &mut items,
        crate::store_logic::MAX_TOTAL_CONTENT_BYTES,
    );
    save_history(app_handle, &items)
}

/// Reorder the persisted history to match `ordered_ids`. Items not referenced
/// in `ordered_ids` keep their relative order and are appended after the
/// referenced set — defensive against client/backend drift.
///
/// If `pinned_ids` is provided, pin states are rewritten to exactly that set
/// (any id in the list becomes pinned; everything else becomes unpinned). This
/// lets a single round-trip carry both reorder + cross-section drags.
pub fn reorder_items(
    app_handle: &AppHandle,
    ordered_ids: &[String],
    pinned_ids: Option<&[String]>,
) -> Result<(), String> {
    let mut items = get_history(app_handle)?;

    // Bucket by id for O(1) lookup, then reassemble in the requested order.
    let mut by_id: std::collections::HashMap<String, ClipItem> =
        items.drain(..).map(|i| (i.id.clone(), i)).collect();

    let mut reordered: Vec<ClipItem> = Vec::with_capacity(by_id.len());
    for id in ordered_ids {
        if let Some(item) = by_id.remove(id) {
            reordered.push(item);
        }
    }
    // Append leftovers in their original-but-now-broken order; preserves data
    // even if the client only sent a partial reorder list.
    for (_id, leftover) in by_id.into_iter() {
        reordered.push(leftover);
    }

    if let Some(pin_list) = pinned_ids {
        let pin_set: std::collections::HashSet<&String> = pin_list.iter().collect();
        for item in reordered.iter_mut() {
            item.pinned = pin_set.contains(&item.id);
        }
    }

    save_history(app_handle, &reordered)
}

/// Trim the persisted history down to `new_max` unpinned items. Called after
/// the user lowers their history-size setting; pinned items are exempt from
/// the cap (see `store_logic::enforce_max_history`), so lowering it can be a
/// no-op even when the total item count is well above the new value.
pub fn truncate_history(app_handle: &AppHandle, new_max: usize) -> Result<(), String> {
    let mut items = get_history(app_handle)?;
    let before = items.len();
    crate::store_logic::enforce_max_history(&mut items, new_max);
    if items.len() == before {
        return Ok(());
    }
    save_history(app_handle, &items)
}
