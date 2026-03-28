import { useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { ClipItem } from "@/types/clipboard";

interface UseClipboardActionsReturn {
  pasteItem: (item: ClipItem) => Promise<void>;
  deleteItem: (id: string) => Promise<void>;
  clearAll: () => Promise<void>;
  pinItem: (id: string, pinned: boolean) => Promise<void>;
}

export function useClipboardActions(
  onHistoryChanged: () => Promise<void>,
): UseClipboardActionsReturn {
  const pasteItem = useCallback(async (item: ClipItem) => {
    try {
      const appWindow = getCurrentWindow();
      await appWindow.hide();
      await invoke("paste_item", { id: item.id });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Paste failed";
      console.error("Failed to paste item:", message);
    }
  }, []);

  const deleteItem = useCallback(
    async (id: string) => {
      try {
        await invoke("delete_item", { id });
        await onHistoryChanged();
      } catch (error) {
        const message =
          error instanceof Error ? error.message : "Delete failed";
        console.error("Failed to delete item:", message);
      }
    },
    [onHistoryChanged],
  );

  const clearAll = useCallback(async () => {
    try {
      await invoke("clear_history");
      await onHistoryChanged();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Clear failed";
      console.error("Failed to clear history:", message);
    }
  }, [onHistoryChanged]);

  const pinItem = useCallback(
    async (id: string, pinned: boolean) => {
      try {
        await invoke("pin_item", { id, pinned });
        await onHistoryChanged();
      } catch (error) {
        const message =
          error instanceof Error ? error.message : "Pin failed";
        console.error("Failed to pin item:", message);
      }
    },
    [onHistoryChanged],
  );

  return { pasteItem, deleteItem, clearAll, pinItem };
}
