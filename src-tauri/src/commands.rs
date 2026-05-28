use tauri::{AppHandle, Manager};
use tauri_plugin_global_shortcut::GlobalShortcutExt;

use crate::clipboard::types::ClipItem;
use crate::settings::AppSettings;
use crate::store;

#[tauri::command]
pub fn get_history(app_handle: AppHandle) -> Result<Vec<ClipItem>, String> {
    store::get_history(&app_handle)
}

#[tauri::command]
pub fn delete_item(app_handle: AppHandle, id: String) -> Result<(), String> {
    store::delete_item(&app_handle, &id)
}

#[tauri::command]
pub fn clear_history(app_handle: AppHandle) -> Result<(), String> {
    store::clear_history(&app_handle)
}

#[tauri::command]
pub fn paste_item(app_handle: AppHandle, id: String) -> Result<(), String> {
    let items = store::get_history(&app_handle)?;
    let item = items
        .iter()
        .find(|i| i.id == id)
        .ok_or_else(|| "Item not found".to_string())?;

    let auto_paste = crate::settings::get_settings(&app_handle)
        .map(|s| s.auto_paste)
        .unwrap_or(false);

    if auto_paste {
        // Re-activate the previously frontmost app so Cmd+V lands in the
        // right place, then write+paste.
        app_handle
            .state::<crate::focus_target::PasteTargetStore>()
            .activate_stored_before_paste();
        crate::simulate::write_and_paste(&item)?;
    } else {
        // Manual mode: just put the content on the clipboard. The frontend
        // has already hidden the window, so focus returns naturally to the
        // user's prior app; they press ⌘V themselves.
        crate::simulate::write_only(&item)?;
    }

    Ok(())
}

#[tauri::command]
pub fn pin_item(app_handle: AppHandle, id: String, pinned: bool) -> Result<(), String> {
    store::pin_item(&app_handle, &id, pinned)
}

#[tauri::command]
pub fn clear_unpinned(app_handle: AppHandle) -> Result<Vec<ClipItem>, String> {
    store::clear_unpinned(&app_handle)
}

#[tauri::command]
pub fn restore_items(app_handle: AppHandle, items: Vec<ClipItem>) -> Result<(), String> {
    store::restore_items(&app_handle, &items)
}

#[tauri::command]
pub fn get_settings(app_handle: AppHandle) -> Result<AppSettings, String> {
    crate::settings::get_settings(&app_handle)
}

#[tauri::command]
pub fn reorder_items(
    app_handle: AppHandle,
    ordered_ids: Vec<String>,
    pinned_ids: Option<Vec<String>>,
) -> Result<(), String> {
    store::reorder_items(&app_handle, &ordered_ids, pinned_ids.as_deref())
}

#[tauri::command]
pub fn update_auto_paste(app_handle: AppHandle, value: bool) -> Result<bool, String> {
    let mut current = crate::settings::get_settings(&app_handle)?;
    current.auto_paste = value;
    crate::settings::save_settings(&app_handle, &current)?;
    Ok(value)
}

#[tauri::command]
pub fn update_max_history(app_handle: AppHandle, value: usize) -> Result<usize, String> {
    let clamped = crate::settings::clamp_max_history(value);
    let mut current = crate::settings::get_settings(&app_handle)?;
    current.max_history = clamped;
    crate::settings::save_settings(&app_handle, &current)?;
    // Apply immediately so the user sees the truncation without waiting for a
    // new clip to come in.
    store::truncate_history(&app_handle, clamped)?;
    Ok(clamped)
}

#[tauri::command]
pub fn update_global_shortcut(app_handle: AppHandle, shortcut_str: String) -> Result<(), String> {
    // Validate the new shortcut parses correctly before touching anything
    let new_shortcut = crate::shortcut_util::parse_shortcut(&shortcut_str)?;

    // Load current settings to know the old shortcut
    let mut current_settings = crate::settings::get_settings(&app_handle)?;

    // Unregister the old shortcut (best-effort — ignore if it was already gone)
    if let Ok(old_shortcut) = crate::shortcut_util::parse_shortcut(&current_settings.global_shortcut) {
        app_handle.global_shortcut().unregister(old_shortcut).ok();
    }

    // Register the new shortcut
    app_handle
        .global_shortcut()
        .register(new_shortcut)
        .map_err(|e| format!("Failed to register shortcut: {}", e))?;

    // Persist
    current_settings.global_shortcut = shortcut_str;
    crate::settings::save_settings(&app_handle, &current_settings)?;

    Ok(())
}
