use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

use crate::clipboard::types::ClipItem;
use crate::settings;

const STORE_PATH: &str = "clipboard_history.json";
const STORE_KEY: &str = "history";

fn current_max_history(app_handle: &AppHandle) -> usize {
    settings::get_settings(app_handle)
        .map(|s| settings::clamp_max_history(s.max_history))
        .unwrap_or(settings::DEFAULT_MAX_HISTORY)
}

pub fn get_history(app_handle: &AppHandle) -> Result<Vec<ClipItem>, String> {
    let store = app_handle
        .store(STORE_PATH)
        .map_err(|e| format!("Failed to open store: {}", e))?;

    let mut items: Vec<ClipItem> = store
        .get(STORE_KEY)
        .and_then(|v| serde_json::from_value(v).ok())
        .unwrap_or_default();

    // Stable sort: pinned items float to the top, relative order preserved within each group.
    items.sort_by(|a, b| b.pinned.cmp(&a.pinned));

    Ok(items)
}

pub fn save_history(app_handle: &AppHandle, items: &[ClipItem]) -> Result<(), String> {
    let store = app_handle
        .store(STORE_PATH)
        .map_err(|e| format!("Failed to open store: {}", e))?;

    let value = serde_json::to_value(items)
        .map_err(|e| format!("Failed to serialize history: {}", e))?;

    store.set(STORE_KEY, value);
    store.save().map_err(|e| format!("Failed to save store: {}", e))?;

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
pub fn restore_items(app_handle: &AppHandle, restored: &[ClipItem]) -> Result<(), String> {
    let mut items = get_history(app_handle)?;
    for r in restored.iter().rev() {
        crate::store_logic::apply_dedup(&mut items, r);
        items.insert(0, r.clone());
    }
    crate::store_logic::enforce_max_history(&mut items, current_max_history(app_handle));
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

/// Truncate the persisted history to `new_max` items if it currently exceeds
/// that cap. Called after the user lowers their history-size setting.
pub fn truncate_history(app_handle: &AppHandle, new_max: usize) -> Result<(), String> {
    let mut items = get_history(app_handle)?;
    if items.len() <= new_max {
        return Ok(());
    }
    // Keep pinned items first (they're already at the top after get_history's
    // stable sort), then fill remaining slots with the newest unpinned items.
    crate::store_logic::enforce_max_history(&mut items, new_max);
    save_history(app_handle, &items)
}
