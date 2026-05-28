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

/// Allowed history caps. Kept small + bounded so users can't accidentally
/// blow up memory (images can be hundreds of KB each, even bigger for
/// retina screenshots).
#[allow(dead_code)]
pub const HISTORY_CAP_CHOICES: &[usize] = &[50, 100, 200, 500];
pub const DEFAULT_MAX_HISTORY: usize = 50;
const MIN_MAX_HISTORY: usize = 10;
const MAX_MAX_HISTORY: usize = 1000;

/// Clamp a requested history cap into the safe range.
pub fn clamp_max_history(requested: usize) -> usize {
    requested.clamp(MIN_MAX_HISTORY, MAX_MAX_HISTORY)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub global_shortcut: String,
    #[serde(default)]
    pub window_position: Option<WindowPosition>,
    #[serde(default = "default_max_history")]
    pub max_history: usize,
    /// When true, pressing Enter writes to clipboard AND simulates Cmd+V into
    /// the previously-focused app. When false (default), we only write to the
    /// clipboard — the user pastes manually wherever they want.
    #[serde(default = "default_auto_paste")]
    pub auto_paste: bool,
}

fn default_max_history() -> usize {
    DEFAULT_MAX_HISTORY
}

fn default_auto_paste() -> bool {
    false
}

impl Default for AppSettings {
    fn default() -> Self {
        AppSettings {
            global_shortcut: "cmd+shift+v".to_string(),
            window_position: None,
            max_history: DEFAULT_MAX_HISTORY,
            auto_paste: false,
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
