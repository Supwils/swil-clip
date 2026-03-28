use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

use crate::clipboard::types::ClipItem;

const STORE_PATH: &str = "clipboard_history.json";
const STORE_KEY: &str = "history";
const MAX_HISTORY: usize = 50;

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
    crate::store_logic::enforce_max_history(&mut items, MAX_HISTORY);

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
