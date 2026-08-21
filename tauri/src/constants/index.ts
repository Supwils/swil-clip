export const MAX_HISTORY = 50;
export const WINDOW_WIDTH = 340;
export const WINDOW_HEIGHT = 480;
export const QUICK_PASTE_LIMIT = 9;
export const CLIPBOARD_POLL_INTERVAL_MS = 500;
export const PASTE_DELAY_MS = 50;
export const DEFAULT_GLOBAL_SHORTCUT = "cmd+shift+v";
/** Frameless window: height of the top strip that moves the window (Tauri drag region). */
export const PANEL_DRAG_REGION_HEIGHT_PX = 20;
/** Maximum number of undo operations retained in the undo stack. */
export const MAX_UNDO_OPERATIONS = 50;
/**
 * Total content bytes the undo stack may hold. Images are retained so Undo can
 * restore exactly what was deleted, so memory is bounded here instead — the
 * same trade the Rust store makes with MAX_TOTAL_CONTENT_BYTES.
 */
export const MAX_UNDO_BYTES = 32 * 1024 * 1024;
