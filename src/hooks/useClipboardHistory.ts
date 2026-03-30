import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { ClipItem } from "@/types/clipboard";
import { MAX_HISTORY } from "@/constants";

interface UseClipboardHistoryReturn {
  items: ClipItem[];
  isLoading: boolean;
  refresh: () => Promise<void>;
}

export function useClipboardHistory(): UseClipboardHistoryReturn {
  const [items, setItems] = useState<ClipItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const isMountedRef = useRef(true);

  const fetchHistory = useCallback(async () => {
    try {
      const history = await invoke<ClipItem[]>("get_history");
      if (isMountedRef.current) {
        setItems(history);
      }
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Failed to fetch history";
      console.error("Failed to fetch clipboard history:", message);
    } finally {
      if (isMountedRef.current) {
        setIsLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    isMountedRef.current = true;
    fetchHistory();

    const unlisten = listen<ClipItem>("clipboard-changed", (event) => {
      if (!isMountedRef.current) return;

      setItems((prev) => {
        const filtered = prev.filter(
          (existing) =>
            !(
              existing.clipType === event.payload.clipType &&
              existing.content === event.payload.content
            ),
        );
        // Preserve pin state if the incoming item was previously pinned in the list.
        const wasPayloadPinned = prev.find(
          (e) =>
            e.clipType === event.payload.clipType &&
            e.content === event.payload.content,
        )?.pinned ?? false;
        const incomingItem = wasPayloadPinned
          ? { ...event.payload, pinned: true }
          : event.payload;
        const updated = [incomingItem, ...filtered];
        // Re-sort so pinned items always stay at the top, matching Rust get_history order.
        updated.sort((a, b) => Number(b.pinned ?? false) - Number(a.pinned ?? false));
        return updated.slice(0, MAX_HISTORY);
      });
    });

    return () => {
      isMountedRef.current = false;
      unlisten.then((fn) => fn());
    };
  }, [fetchHistory]);

  return { items, isLoading, refresh: fetchHistory };
}
