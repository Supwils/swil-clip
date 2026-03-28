#![allow(deprecated)]

use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

use super::types::{ClipItem, ClipType};
use crate::store;

const POLL_INTERVAL_MS: u64 = 500;

pub struct ClipboardMonitor {
    last_change_count: Arc<Mutex<i64>>,
}

impl ClipboardMonitor {
    pub fn new() -> Self {
        Self {
            last_change_count: Arc::new(Mutex::new(0)),
        }
    }

    pub fn start(&self, app_handle: AppHandle) {
        let last_change_count = Arc::clone(&self.last_change_count);

        thread::spawn(move || {
            loop {
                thread::sleep(Duration::from_millis(POLL_INTERVAL_MS));
                Self::poll_clipboard(&app_handle, &last_change_count);
            }
        });
    }

    #[cfg(target_os = "macos")]
    fn poll_clipboard(app_handle: &AppHandle, last_change_count: &Arc<Mutex<i64>>) {
        use cocoa::appkit::NSPasteboard;
        use cocoa::base::{id, nil};
        use cocoa::foundation::{NSArray, NSString};
        use objc::msg_send;
        use objc::sel;
        use objc::sel_impl;
        use std::ffi::CStr;

        unsafe {
            let pasteboard: id = NSPasteboard::generalPasteboard(nil);
            let change_count = pasteboard.changeCount();

            let mut last = last_change_count.lock().unwrap_or_else(|e| e.into_inner());
            if change_count == *last {
                return;
            }
            *last = change_count;
            drop(last);

            let types: id = pasteboard.types();
            if types == nil {
                return;
            }

            let type_count = types.count() as usize;
            let mut has_string = false;
            let mut has_image = false;

            for i in 0..type_count {
                let t: id = types.objectAtIndex(i as u64);
                if t == nil {
                    continue;
                }

                let t_str = CStr::from_ptr(t.UTF8String()).to_string_lossy();
                if t_str.contains("public.utf8-plain-text") {
                    has_string = true;
                }
                if t_str.contains("public.tiff") || t_str.contains("public.png") {
                    has_image = true;
                }
            }

            if has_string {
                let text_type = NSString::alloc(nil).init_str("public.utf8-plain-text");
                let raw: id = msg_send![pasteboard, stringForType: text_type];
                if raw != nil {
                    let c_str = CStr::from_ptr(raw.UTF8String());
                    let text = c_str.to_string_lossy().to_string();

                    if !text.trim().is_empty() {
                        let preview = text.chars().take(200).collect::<String>();
                        let now = chrono::Utc::now().timestamp_millis();

                        let item = ClipItem {
                            id: uuid::Uuid::new_v4().to_string(),
                            clip_type: ClipType::Text,
                            content: text,
                            preview,
                            timestamp: now,
                            pinned: false,
                            app_name: None,
                            image_width: None,
                            image_height: None,
                            image_format: None,
                        };

                        if let Err(e) = store::add_item(app_handle, &item) {
                            log::error!("Failed to store clip item: {}", e);
                        }
                        if let Err(e) = app_handle.emit("clipboard-changed", &item) {
                            log::error!("Failed to emit clipboard event: {}", e);
                        }
                    }
                }
            } else if has_image {
                let png_type = NSString::alloc(nil).init_str("public.png");
                let tiff_type = NSString::alloc(nil).init_str("public.tiff");

                let data: id = msg_send![pasteboard, dataForType: png_type];
                let (raw_data, img_format): (id, &str) = if data != nil {
                    (data, "png")
                } else {
                    let tiff_data: id = msg_send![pasteboard, dataForType: tiff_type];
                    (tiff_data, "tiff")
                };

                if raw_data != nil {
                    let length: usize = msg_send![raw_data, length];
                    let bytes: *const u8 = msg_send![raw_data, bytes];
                    let slice = std::slice::from_raw_parts(bytes, length);
                    let b64 = base64::Engine::encode(
                        &base64::engine::general_purpose::STANDARD,
                        slice,
                    );

                    let now = chrono::Utc::now().timestamp_millis();
                    let item = ClipItem {
                        id: uuid::Uuid::new_v4().to_string(),
                        clip_type: ClipType::Image,
                        content: b64,
                        preview: format!("Image ({})", img_format),
                        timestamp: now,
                        pinned: false,
                        app_name: None,
                        image_width: None,
                        image_height: None,
                        image_format: Some(img_format.to_string()),
                    };

                    if let Err(e) = store::add_item(app_handle, &item) {
                        log::error!("Failed to store image clip: {}", e);
                    }
                    if let Err(e) = app_handle.emit("clipboard-changed", &item) {
                        log::error!("Failed to emit clipboard event: {}", e);
                    }
                }
            }
        }
    }

    #[cfg(not(target_os = "macos"))]
    fn poll_clipboard(_app_handle: &AppHandle, _last_change_count: &Arc<Mutex<i64>>) {}
}
