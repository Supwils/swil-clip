mod clipboard;
mod commands;
mod simulate;
mod store;
mod tray;

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
        ])
        .setup(|app| {
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

            let shortcut = Shortcut::new(
                Some(Modifiers::SUPER | Modifiers::SHIFT),
                Code::KeyV,
            );

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
                                    position_window_at_cursor(&window);
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
            let _ = window.show();
            let _ = window.set_focus();

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
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
