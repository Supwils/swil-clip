use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};

use crate::focus_target::PasteTargetStore;

pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let show = MenuItem::with_id(app, "show", "Show SwilClip", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;

    let handle = app.clone();
    TrayIconBuilder::new()
        .icon(app.default_window_icon().cloned().expect("no app icon"))
        .menu(&menu)
        .tooltip("SwilClip")
        .on_menu_event(move |app_handle: &AppHandle, event| {
            match event.id().as_ref() {
                "show" => {
                    if let Some(window) = app_handle.get_webview_window("main") {
                        app_handle.state::<PasteTargetStore>().capture_frontmost();
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
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
                if let Some(window) = handle.get_webview_window("main") {
                    handle.state::<PasteTargetStore>().capture_frontmost();
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)?;

    Ok(())
}
