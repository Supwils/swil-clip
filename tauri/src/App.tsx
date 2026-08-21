import { useCallback, useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { ClipboardPanel } from "@/components/ClipboardPanel";
import { useClipboardHistory } from "@/hooks/useClipboardHistory";
import { useClipboardActions } from "@/hooks/useClipboardActions";
import { useUndoStack } from "@/hooks/useUndoStack";
import { useSettings } from "@/hooks/useSettings";
import type { ClipItem } from "@/types/clipboard";
import { QUICK_PASTE_LIMIT } from "@/constants";

function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) {
    return false;
  }

  if (target.isContentEditable || target.closest("[cmdk-input]")) {
    return true;
  }

  const tagName = target.tagName;
  return tagName === "INPUT" || tagName === "TEXTAREA" || tagName === "SELECT";
}

export function App(): React.ReactElement {
  // Single settings instance for the whole app — SettingsDialog receives this
  // via props, so updates made there are immediately visible here (footer
  // hints, paste behavior) instead of going stale until restart.
  const settingsApi = useSettings();
  const { settings } = settingsApi;
  const { items, refresh, error: historyError } = useClipboardHistory();
  const {
    isBusy,
    pasteItem,
    deleteItem,
    clearAll,
    clearUnpinned,
    restoreItems,
    pinItem,
    reorderItems,
  } = useClipboardActions(refresh);
  const { canUndo, pushUndo, popUndo } = useUndoStack();
  const [showCount, setShowCount] = useState(0);
  const [settingsRequestId, setSettingsRequestId] = useState(0);
  const itemsRef = useRef(items);
  itemsRef.current = items;

  const handlePaste = useCallback(
    (item: ClipItem) => pasteItem(item),
    [pasteItem],
  );

  const handleDelete = useCallback(
    async (id: string): Promise<boolean> => {
      const target = itemsRef.current.find((i) => i.id === id);
      const ok = await deleteItem(id);
      if (ok && target) pushUndo([target]);
      return ok;
    },
    [deleteItem, pushUndo],
  );

  const handleClearUnpinned = useCallback(async (): Promise<boolean> => {
    const removed = await clearUnpinned();
    if (removed.length > 0) pushUndo(removed);
    return removed.length > 0;
  }, [clearUnpinned, pushUndo]);

  const handleUndo = useCallback(async (): Promise<boolean> => {
    const batch = popUndo();
    if (!batch) return false;
    return restoreItems(batch);
  }, [popUndo, restoreItems]);

  const handleResetHistory = useCallback(async (): Promise<boolean> => {
    try {
      await invoke("reset_history");
      await refresh();
      return true;
    } catch (error) {
      console.error("Failed to reset history:", error);
      return false;
    }
  }, [refresh]);

  const handleHide = useCallback(() => {
    // Hide first, then bounce focus back to the app that owned the caret
    // when we opened. macOS panel windows (decorations:false +
    // alwaysOnTop) don't reliably restore focus on their own, so the prior
    // input field would lose its caret without this. Errors are swallowed
    // because hide() must still succeed even if the IPC call fails.
    void getCurrentWindow()
      .hide()
      .then(() => invoke("restore_previous_focus"))
      .catch((error) => {
        console.error("Failed to restore previous focus:", error);
      });
  }, []);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (isBusy || isEditableTarget(event.target)) {
        return;
      }

      // Skip while an IME (e.g. macOS Chinese) is composing — the keystroke
      // belongs to the input method, not to a quick-paste shortcut.
      if (event.isComposing || event.keyCode === 229) {
        return;
      }

      if (event.altKey && !event.metaKey && !event.shiftKey && !event.ctrlKey) {
        const num = parseInt(event.key, 10);
        if (num >= 1 && num <= QUICK_PASTE_LIMIT) {
          // Read through the ref so the listener isn't torn down and
          // re-registered on every clipboard-changed event.
          const target = itemsRef.current[num - 1];
          if (target) {
            event.preventDefault();
            void pasteItem(target);
          }
        }
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [isBusy, pasteItem]);

  useEffect(() => {
    const appWindow = getCurrentWindow();
    const unlisten = appWindow.onFocusChanged(({ payload: focused }) => {
      if (focused) {
        setShowCount((c) => c + 1);
        refresh();
      } else {
        appWindow.hide();
      }
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, [refresh]);

  // Tray menu → "Settings…" → open the dialog automatically once the panel is up.
  useEffect(() => {
    const unlisten = listen("open-settings", () => {
      setSettingsRequestId((id) => id + 1);
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  return (
    <div className="app-shell">
      <ClipboardPanel
        key={showCount}
        items={items}
        onPaste={handlePaste}
        onDelete={handleDelete}
        onClearAll={clearAll}
        onClearUnpinned={handleClearUnpinned}
        onUndo={handleUndo}
        canUndo={canUndo}
        onPin={pinItem}
        onReorder={reorderItems}
        onHide={handleHide}
        isBusy={isBusy}
        settingsRequestId={settingsRequestId}
        autoPaste={settings.autoPaste}
        settingsApi={settingsApi}
        historyError={historyError}
        onRetryHistory={refresh}
        onResetHistory={handleResetHistory}
      />
    </div>
  );
}
