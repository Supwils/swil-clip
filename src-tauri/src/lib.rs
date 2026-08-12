#![allow(unexpected_cfgs)]

mod clipboard;
mod commands;
mod crypto;
mod focus_target;
mod settings;
mod shortcut_util;
mod simulate;
mod store;
mod store_logic;
mod tray;
mod window_placement;

use std::sync::mpsc;
use std::time::Duration;
use tauri::Manager;
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut};

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            commands::get_history,
            commands::delete_item,
            commands::clear_history,
            commands::reset_history,
            commands::paste_item,
            commands::pin_item,
            commands::clear_unpinned,
            commands::restore_items,
            commands::get_settings,
            commands::update_global_shortcut,
            commands::update_max_history,
            commands::update_auto_paste,
            commands::reorder_items,
            commands::restore_previous_focus,
        ])
        .setup(|app| {
            // Menu-bar utility, not an application: no Dock tile, no ⌘Tab
            // slot. Both would activate an app whose only window is a hidden
            // panel, so the user gets a focus flicker and nothing else.
            // Accessory apps can still take keyboard focus when we show the
            // panel, which is what the hotkey path relies on.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            app.manage(focus_target::PasteTargetStore::default());
            app.manage(store::HistoryCache::default());

            // Release builds log too (warnings/errors only) — history/keychain
            // failures are otherwise completely invisible in production.
            let log_level = if cfg!(debug_assertions) {
                log::LevelFilter::Info
            } else {
                log::LevelFilter::Warn
            };
            app.handle().plugin(
                tauri_plugin_log::Builder::default()
                    .level(log_level)
                    .build(),
            )?;

            #[cfg(target_os = "macos")]
            {
                let window = app
                    .get_webview_window("main")
                    .expect("failed to get main window");

                window_vibrancy::apply_vibrancy(
                    &window,
                    window_vibrancy::NSVisualEffectMaterial::UnderWindowBackground,
                    None,
                    Some(12.0),
                )
                .ok();
            }

            let handle = app.handle().clone();
            tray::setup_tray(&handle)?;

            let monitor = clipboard::monitor::ClipboardMonitor::new();
            monitor.start(handle.clone());

            let stored_settings = settings::get_settings(&handle).unwrap_or_default();
            let shortcut = shortcut_util::parse_shortcut(&stored_settings.global_shortcut)
                .unwrap_or_else(|_| {
                    Shortcut::new(Some(Modifiers::SUPER | Modifiers::SHIFT), Code::KeyV)
                });

            // Debounced window-position saving. Moved events fire at display
            // refresh rate during a drag, so a single long-lived worker
            // coalesces them: it keeps swallowing positions until 300ms pass
            // without a new one, then persists the last position seen.
            {
                let (pos_tx, pos_rx) = mpsc::channel::<(i32, i32)>();
                let handle_for_save = handle.clone();
                std::thread::spawn(move || {
                    let mut latest: Option<(i32, i32)> = None;
                    loop {
                        let received = if latest.is_some() {
                            match pos_rx.recv_timeout(Duration::from_millis(300)) {
                                Ok(pos) => Some(pos),
                                Err(mpsc::RecvTimeoutError::Timeout) => None,
                                Err(mpsc::RecvTimeoutError::Disconnected) => break,
                            }
                        } else {
                            match pos_rx.recv() {
                                Ok(pos) => Some(pos),
                                Err(_) => break,
                            }
                        };
                        match received {
                            Some(pos) => latest = Some(pos),
                            None => {
                                if let Some((x, y)) = latest.take() {
                                    if let Ok(mut s) = settings::get_settings(&handle_for_save) {
                                        s.window_position =
                                            Some(settings::WindowPosition { x, y });
                                        let _ = settings::save_settings(&handle_for_save, &s);
                                    }
                                }
                            }
                        }
                    }
                });

                let window = app
                    .get_webview_window("main")
                    .expect("failed to get main window for move listener");
                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::Moved(pos) = event {
                        let _ = pos_tx.send((pos.x, pos.y));
                    }
                });
            }

            let handle_for_shortcut = handle.clone();
            handle.plugin(
                tauri_plugin_global_shortcut::Builder::new()
                    .with_handler(move |_app, _shortcut, event| {
                        if let tauri_plugin_global_shortcut::ShortcutState::Pressed = event.state {
                            if let Some(window) =
                                handle_for_shortcut.get_webview_window("main")
                            {
                                let visible = window.is_visible().unwrap_or(false);
                                if visible {
                                    let _ = window.hide();
                                    // Toggling closed should also bounce focus
                                    // back to the prior app — the panel hijacked
                                    // it on show, so we restore on the matching
                                    // hide.
                                    handle_for_shortcut
                                        .state::<focus_target::PasteTargetStore>()
                                        .activate_stored_now();
                                } else {
                                    handle_for_shortcut
                                        .state::<focus_target::PasteTargetStore>()
                                        .capture_frontmost();
                                    show_window(&handle_for_shortcut, &window);
                                    let _ = window.show();
                                    let _ = window.set_focus();
                                }
                            }
                        }
                    })
                    .build(),
            )?;

            app.global_shortcut().register(shortcut).ok();

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// Place the panel before showing it: remembered position when it still lands
/// on a connected display, cursor otherwise.
///
/// The two paths deliberately work in DIFFERENT coordinate spaces, because
/// their inputs arrive in different ones and converting between them is where
/// mixed-DPI setups go wrong. A saved position was captured from
/// `WindowEvent::Moved` in physical pixels, so it is clamped against physical
/// work areas. The cursor arrives from CoreGraphics in logical points, so it
/// is clamped against logical ones — the previous code fed those points
/// straight into `PhysicalPosition`, which doubles every offset on a Retina
/// display and can push the panel clean off the screen.
fn show_window(app_handle: &tauri::AppHandle, window: &tauri::WebviewWindow) {
    let saved = settings::get_settings(app_handle)
        .ok()
        .and_then(|s| s.window_position);

    if let Some(pos) = saved {
        let (width, height) = physical_window_size(window);
        let placed = window_placement::placement_for_saved(
            &work_areas(window, Space::Physical),
            pos.x as f64,
            pos.y as f64,
            width,
            height,
        );
        if let Some((x, y)) = placed {
            let _ = window.set_position(tauri::PhysicalPosition::new(x as i32, y as i32));
            return;
        }
        // The remembered point is on no current display — an external monitor
        // was unplugged, or the layout changed. Falling through to the cursor
        // is the only way the panel stays reachable.
    }

    position_window_at_cursor(window);
}

#[derive(Clone, Copy)]
enum Space {
    Physical,
    Logical,
}

/// Every connected display's usable area (menu bar and Dock excluded).
///
/// Empty when the platform can't tell us — callers then leave the window
/// wherever it already is rather than guessing.
fn work_areas(window: &tauri::WebviewWindow, space: Space) -> Vec<window_placement::Rect> {
    window
        .available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|monitor| {
            // Each display converts with ITS OWN scale factor; a single
            // global divisor would misplace windows on mixed-DPI layouts.
            let divisor = match space {
                Space::Physical => 1.0,
                Space::Logical => monitor.scale_factor().max(0.1),
            };
            let area = monitor.work_area();
            window_placement::Rect::new(
                area.position.x as f64 / divisor,
                area.position.y as f64 / divisor,
                area.size.width as f64 / divisor,
                area.size.height as f64 / divisor,
            )
        })
        .collect()
}

/// Configured panel size, used only when the window can't report its own —
/// before the first show it may not have one yet. Mirrors tauri.conf.json.
const FALLBACK_LOGICAL_SIZE: (f64, f64) = (340.0, 480.0);

fn physical_window_size(window: &tauri::WebviewWindow) -> (f64, f64) {
    match window.outer_size() {
        Ok(size) => (size.width as f64, size.height as f64),
        Err(_) => {
            let scale = window.scale_factor().unwrap_or(1.0);
            (
                FALLBACK_LOGICAL_SIZE.0 * scale,
                FALLBACK_LOGICAL_SIZE.1 * scale,
            )
        }
    }
}

fn logical_window_size(window: &tauri::WebviewWindow) -> (f64, f64) {
    let scale = window.scale_factor().unwrap_or(1.0).max(0.1);
    match window.outer_size() {
        Ok(size) => (size.width as f64 / scale, size.height as f64 / scale),
        Err(_) => FALLBACK_LOGICAL_SIZE,
    }
}

fn position_window_at_cursor(window: &tauri::WebviewWindow) {
    #[cfg(target_os = "macos")]
    {
        use core_graphics::event::CGEvent;
        use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

        if let Ok(source) = CGEventSource::new(CGEventSourceStateID::HIDSystemState) {
            if let Ok(event) = CGEvent::new(source) {
                // CGEvent locations are global display coordinates in POINTS,
                // top-left origin — the same space work_areas(Logical)
                // returns, so the two are directly comparable.
                let cursor = event.location();
                let (width, height) = logical_window_size(window);
                if let Some((x, y)) = window_placement::placement_for_cursor(
                    &work_areas(window, Space::Logical),
                    cursor.x,
                    cursor.y,
                    width,
                    height,
                ) {
                    let _ = window.set_position(tauri::LogicalPosition::new(x, y));
                }
            }
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = window;
    }
}
