use serde::{Deserialize, Serialize};
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

const STORE_PATH: &str = "clipboard_history.json";
const SETTINGS_KEY: &str = "settings";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowPosition {
    pub x: i32,
    pub y: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub global_shortcut: String,
    #[serde(default)]
    pub window_position: Option<WindowPosition>,
}

impl Default for AppSettings {
    fn default() -> Self {
        AppSettings {
            global_shortcut: "cmd+shift+v".to_string(),
            window_position: None,
        }
    }
}

pub fn get_settings(app_handle: &AppHandle) -> Result<AppSettings, String> {
    let store = app_handle
        .store(STORE_PATH)
        .map_err(|e| format!("Failed to open store: {}", e))?;

    let settings: AppSettings = store
        .get(SETTINGS_KEY)
        .and_then(|v| serde_json::from_value(v).ok())
        .unwrap_or_default();

    Ok(settings)
}

pub fn save_settings(app_handle: &AppHandle, settings: &AppSettings) -> Result<(), String> {
    let store = app_handle
        .store(STORE_PATH)
        .map_err(|e| format!("Failed to open store: {}", e))?;

    let value = serde_json::to_value(settings)
        .map_err(|e| format!("Failed to serialize settings: {}", e))?;

    store.set(SETTINGS_KEY, value);
    store
        .save()
        .map_err(|e| format!("Failed to save settings: {}", e))?;

    Ok(())
}
