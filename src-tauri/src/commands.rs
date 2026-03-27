use tauri::AppHandle;

use crate::clipboard::types::ClipItem;
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

    crate::simulate::write_and_paste(&item)?;

    Ok(())
}
