#![allow(deprecated)]

use crate::clipboard::types::{ClipItem, ClipType};

#[cfg(target_os = "macos")]
pub fn write_and_paste(item: &ClipItem) -> Result<(), String> {
    write_to_clipboard(item)?;
    std::thread::sleep(std::time::Duration::from_millis(50));
    simulate_cmd_v()?;
    Ok(())
}

#[cfg(not(target_os = "macos"))]
pub fn write_and_paste(_item: &ClipItem) -> Result<(), String> {
    Err("Paste simulation only supported on macOS".to_string())
}

#[cfg(target_os = "macos")]
fn write_to_clipboard(item: &ClipItem) -> Result<(), String> {
    use cocoa::appkit::NSPasteboard;
    use cocoa::base::{id, nil};
    use cocoa::foundation::{NSArray, NSString};
    use objc::msg_send;
    use objc::sel;
    use objc::sel_impl;

    unsafe {
        let pasteboard: id = NSPasteboard::generalPasteboard(nil);
        pasteboard.clearContents();

        match item.clip_type {
            ClipType::Text => {
                let ns_string_type = NSString::alloc(nil).init_str("public.utf8-plain-text");
                let ns_string = NSString::alloc(nil).init_str(&item.content);
                let types = NSArray::arrayWithObject(nil, ns_string_type);
                pasteboard.declareTypes_owner(types, nil);
                let _: bool = msg_send![pasteboard, setString: ns_string forType: ns_string_type];
            }
            ClipType::Image => {
                let decoded = base64::Engine::decode(
                    &base64::engine::general_purpose::STANDARD,
                    &item.content,
                )
                .map_err(|e| format!("Failed to decode image: {}", e))?;

                let format = item.image_format.as_deref().unwrap_or("png");
                let uti = match format {
                    "tiff" => "public.tiff",
                    _ => "public.png",
                };

                let ns_type = NSString::alloc(nil).init_str(uti);
                let types = NSArray::arrayWithObject(nil, ns_type);
                pasteboard.declareTypes_owner(types, nil);

                let ns_data: id = msg_send![
                    objc::class!(NSData),
                    dataWithBytes: decoded.as_ptr()
                    length: decoded.len()
                ];
                let _: bool = msg_send![pasteboard, setData: ns_data forType: ns_type];
            }
        }
    }

    Ok(())
}

#[cfg(target_os = "macos")]
fn simulate_cmd_v() -> Result<(), String> {
    use core_graphics::event::{CGEvent, CGEventFlags, CGKeyCode};
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

    let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
        .map_err(|_| "Failed to create event source".to_string())?;

    let key_v: CGKeyCode = 9;

    let key_down = CGEvent::new_keyboard_event(source.clone(), key_v, true)
        .map_err(|_| "Failed to create key down event".to_string())?;
    key_down.set_flags(CGEventFlags::CGEventFlagCommand);

    let key_up = CGEvent::new_keyboard_event(source, key_v, false)
        .map_err(|_| "Failed to create key up event".to_string())?;
    key_up.set_flags(CGEventFlags::CGEventFlagCommand);

    key_down.post(core_graphics::event::CGEventTapLocation::HID);
    key_up.post(core_graphics::event::CGEventTapLocation::HID);

    Ok(())
}
