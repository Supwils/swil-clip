import { useCallback, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { ClipItem } from "@/types/clipboard";

interface UseClipboardActionsReturn {
  isBusy: boolean;
  pasteItem: (item: ClipItem) => Promise<boolean>;
  deleteItem: (id: string) => Promise<boolean>;
  clearAll: () => Promise<boolean>;
  clearUnpinned: () => Promise<ClipItem[]>;
  restoreItems: (items: ClipItem[]) => Promise<boolean>;
  pinItem: (id: string, pinned: boolean) => Promise<boolean>;
  reorderItems: (orderedIds: string[], pinnedIds: string[]) => Promise<boolean>;
}

export function useClipboardActions(
  onHistoryChanged: () => Promise<void>,
): UseClipboardActionsReturn {
  const busyRef = useRef(false);
  const [isBusy, setIsBusy] = useState(false);

  const runSerialized = useCallback(
    async <T,>(
      operation: () => Promise<T>,
      fallbackValue: T,
      logPrefix: string,
      fallbackMessage: string,
    ): Promise<T> => {
      if (busyRef.current) {
        return fallbackValue;
      }

      busyRef.current = true;
      setIsBusy(true);

      try {
        return await operation();
      } catch (error) {
        const message =
          error instanceof Error ? error.message : fallbackMessage;
        console.error(`${logPrefix}:`, message);
        return fallbackValue;
      } finally {
        busyRef.current = false;
        setIsBusy(false);
      }
    },
    [],
  );

  const pasteItem = useCallback(
    (item: ClipItem) =>
      runSerialized(
        async () => {
          const appWindow = getCurrentWindow();
          await appWindow.hide();
          await invoke("paste_item", { id: item.id });
          return true;
        },
        false,
        "Failed to paste item",
        "Paste failed",
      ),
    [runSerialized],
  );

  const deleteItem = useCallback(
    (id: string) =>
      runSerialized(
        async () => {
          await invoke("delete_item", { id });
          await onHistoryChanged();
          return true;
        },
        false,
        "Failed to delete item",
        "Delete failed",
      ),
    [onHistoryChanged, runSerialized],
  );

  const clearAll = useCallback(
    () =>
      runSerialized(
        async () => {
          await invoke("clear_history");
          await onHistoryChanged();
          return true;
        },
        false,
        "Failed to clear history",
        "Clear failed",
      ),
    [onHistoryChanged, runSerialized],
  );

  const clearUnpinned = useCallback(
    () =>
      runSerialized(
        async () => {
          const removed: ClipItem[] = await invoke("clear_unpinned");
          await onHistoryChanged();
          return removed;
        },
        [] as ClipItem[],
        "Failed to clear unpinned",
        "Clear unpinned failed",
      ),
    [onHistoryChanged, runSerialized],
  );

  const restoreItems = useCallback(
    (items: ClipItem[]) =>
      runSerialized(
        async () => {
          await invoke("restore_items", { items });
          await onHistoryChanged();
          return true;
        },
        false,
        "Failed to restore items",
        "Restore failed",
      ),
    [onHistoryChanged, runSerialized],
  );

  const pinItem = useCallback(
    (id: string, pinned: boolean) =>
      runSerialized(
        async () => {
          await invoke("pin_item", { id, pinned });
          await onHistoryChanged();
          return true;
        },
        false,
        "Failed to pin item",
        "Pin failed",
      ),
    [onHistoryChanged, runSerialized],
  );

  const reorderItems = useCallback(
    (orderedIds: string[], pinnedIds: string[]) =>
      runSerialized(
        async () => {
          await invoke("reorder_items", { orderedIds, pinnedIds });
          await onHistoryChanged();
          return true;
        },
        false,
        "Failed to reorder items",
        "Reorder failed",
      ),
    [onHistoryChanged, runSerialized],
  );

  return {
    isBusy,
    pasteItem,
    deleteItem,
    clearAll,
    clearUnpinned,
    restoreItems,
    pinItem,
    reorderItems,
  };
}
