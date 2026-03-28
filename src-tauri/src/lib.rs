#![allow(unexpected_cfgs)]

mod clipboard;
mod commands;
mod focus_target;
mod settings;
mod shortcut_util;
mod simulate;
mod store;
mod store_logic;
mod tray;

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
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
            commands::paste_item,
            commands::pin_item,
            commands::get_settings,
            commands::update_global_shortcut,
        ])
        .setup(|app| {
            app.manage(focus_target::PasteTargetStore::default());

            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

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

            // Track last move time for debounced position saving
            let last_move: Arc<Mutex<Option<Instant>>> = Arc::new(Mutex::new(None));
            let last_move_for_listener = last_move.clone();
            let handle_for_move = handle.clone();

            {
                let window = app
                    .get_webview_window("main")
                    .expect("failed to get main window for move listener");
                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::Moved(pos) = event {
                        let x = pos.x;
                        let y = pos.y;
                        let now = Instant::now();
                        if let Ok(mut guard) = last_move_for_listener.lock() {
                            *guard = Some(now);
                        }
                        let last_move_check = last_move.clone();
                        let handle_check = handle_for_move.clone();
                        std::thread::spawn(move || {
                            std::thread::sleep(Duration::from_millis(300));
                            let is_last = last_move_check
                                .lock()
                                .ok()
                                .and_then(|g| *g)
                                .map(|t| t.elapsed() >= Duration::from_millis(250))
                                .unwrap_or(false);
                            if is_last {
                                if let Ok(mut s) = settings::get_settings(&handle_check) {
                                    s.window_position =
                                        Some(settings::WindowPosition { x, y });
                                    let _ = settings::save_settings(&handle_check, &s);
                                }
                            }
                        });
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

            let window = app
                .get_webview_window("main")
                .expect("failed to get main window");
            show_window(&handle, &window);
            let _ = window.show();
            let _ = window.set_focus();

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn show_window(app_handle: &tauri::AppHandle, window: &tauri::WebviewWindow) {
    // Use saved position if available, otherwise position near cursor.
    let saved = settings::get_settings(app_handle)
        .ok()
        .and_then(|s| s.window_position);

    if let Some(pos) = saved {
        let _ = window.set_position(tauri::PhysicalPosition::new(pos.x, pos.y));
    } else {
        position_window_at_cursor(window);
    }
}

fn position_window_at_cursor(window: &tauri::WebviewWindow) {
    #[cfg(target_os = "macos")]
    {
        use core_graphics::event::CGEvent;
        use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

        if let Ok(source) = CGEventSource::new(CGEventSourceStateID::HIDSystemState) {
            if let Ok(event) = CGEvent::new(source) {
                let cursor_pos = event.location();
                let x = cursor_pos.x as f64 - 170.0;
                let y = cursor_pos.y as f64;
                let _ = window.set_position(tauri::PhysicalPosition::new(
                    x.max(0.0) as i32,
                    y.max(0.0) as i32,
                ));
            }
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = window;
    }
}
