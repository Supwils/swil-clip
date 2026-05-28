//! Remembers the macOS frontmost app when opening the panel so we can restore
//! focus before simulating Cmd+V (see paste flow in `commands::paste_item`).
#![allow(deprecated)]

use std::sync::Mutex;
use std::time::Duration;

#[derive(Default)]
pub struct PasteTargetStore(Mutex<Option<i32>>);

impl PasteTargetStore {
    /// Call immediately before `show` + `set_focus` on the main window.
    pub fn capture_frontmost(&self) {
        #[cfg(target_os = "macos")]
        {
            let self_pid = std::process::id() as i32;
            let target = macos::frontmost_pid().filter(|&p| p != self_pid);
            if let Ok(mut g) = self.0.lock() {
                *g = target;
            }
        }
    }

    /// Call before writing the pasteboard and posting Cmd+V.
    pub fn activate_stored_before_paste(&self) {
        #[cfg(target_os = "macos")]
        {
            let pid_opt = self.0.lock().ok().and_then(|g| *g);
            if let Some(pid) = pid_opt {
                let self_pid = std::process::id() as i32;
                if pid != self_pid {
                    let _ = macos::activate_pid(pid);
                    std::thread::sleep(Duration::from_millis(100));
                }
            }
        }
    }
}

#[cfg(target_os = "macos")]
mod macos {
    use cocoa::base::{id, nil};
    use objc::runtime::Class;
    use objc::{msg_send, sel, sel_impl};

    pub fn frontmost_pid() -> Option<i32> {
        unsafe {
            let cls = Class::get("NSWorkspace")?;
            let workspace: id = msg_send![cls, sharedWorkspace];
            if workspace == nil {
                return None;
            }
            let front: id = msg_send![workspace, frontmostApplication];
            if front == nil {
                return None;
            }
            let pid: i32 = msg_send![front, processIdentifier];
            Some(pid)
        }
    }

    pub fn activate_pid(pid: i32) -> bool {
        unsafe {
            let Some(cls) = Class::get("NSRunningApplication") else {
                return false;
            };
            let app: id = msg_send![cls, runningApplicationWithProcessIdentifier: pid];
            if app == nil {
                return false;
            }
            const NS_APPLICATION_ACTIVATE_IGNORING_OTHER_APPS: u64 = 1 << 1;
            let success: bool =
                msg_send![app, activateWithOptions: NS_APPLICATION_ACTIVATE_IGNORING_OTHER_APPS];
            success
        }
    }
}
