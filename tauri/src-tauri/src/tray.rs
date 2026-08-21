use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager,
};

use crate::focus_target::PasteTargetStore;

pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let show = MenuItem::with_id(app, "show", "Show SwilClip", true, Some("Cmd+Shift+V"))?;
    let settings = MenuItem::with_id(app, "settings", "Settings…", true, Some("Cmd+,"))?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit SwilClip", true, Some("Cmd+Q"))?;
    let menu = Menu::with_items(app, &[&show, &settings, &separator, &quit])?;

    let handle = app.clone();
    TrayIconBuilder::new()
        .icon(app.default_window_icon().cloned().expect("no app icon"))
        .menu(&menu)
        .tooltip("SwilClip")
        .on_menu_event(move |app_handle: &AppHandle, event| {
            match event.id().as_ref() {
                "show" => {
                    show_panel(app_handle);
                }
                "settings" => {
                    show_panel(app_handle);
                    // Frontend listens for this and opens the Settings dialog.
                    let _ = app_handle.emit("open-settings", ());
                }
                "quit" => {
                    app_handle.exit(0);
                }
                _ => {}
            }
        })
        .on_tray_icon_event(move |_tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                show_panel(&handle);
            }
        })
        .build(app)?;

    Ok(())
}

fn show_panel(app_handle: &AppHandle) {
    if let Some(window) = app_handle.get_webview_window("main") {
        app_handle.state::<PasteTargetStore>().capture_frontmost();
        let _ = window.show();
        let _ = window.set_focus();
    }
}
