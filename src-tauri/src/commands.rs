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

    app_handle
        .state::<crate::focus_target::PasteTargetStore>()
        .activate_stored_before_paste();

    crate::simulate::write_and_paste(&item)?;

    Ok(())
}

#[tauri::command]
pub fn pin_item(app_handle: AppHandle, id: String, pinned: bool) -> Result<(), String> {
    store::pin_item(&app_handle, &id, pinned)
}

#[tauri::command]
pub fn get_settings(app_handle: AppHandle) -> Result<AppSettings, String> {
    crate::settings::get_settings(&app_handle)
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
