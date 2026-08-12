import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { ClipItem } from "@/types/clipboard";

interface UseClipboardHistoryReturn {
  items: ClipItem[];
  isLoading: boolean;
  /** Why the last fetch failed (Keychain denied, corrupt blob, …), or null.
   *  Drives the panel's error state — an unreadable history must never be
   *  indistinguishable from an empty one. */
  error: string | null;
  refresh: () => Promise<void>;
}

export function useClipboardHistory(): UseClipboardHistoryReturn {
  const [items, setItems] = useState<ClipItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const isMountedRef = useRef(true);

  const fetchHistory = useCallback(async () => {
    try {
      const history = await invoke<ClipItem[]>("get_history");
      if (isMountedRef.current) {
        setItems(history);
        setError(null);
      }
    } catch (err) {
      const message = typeof err === "string" ? err
        : err instanceof Error ? err.message
        : "Failed to fetch history";
      console.error("Failed to fetch clipboard history:", message);
      if (isMountedRef.current) {
        setError(message);
      }
    } finally {
      if (isMountedRef.current) {
        setIsLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    isMountedRef.current = true;
    fetchHistory();

    // The backend already ran the full merge (dedup, pin preservation,
    // pinned-first order, cap) before emitting — refetch the authoritative
    // list instead of re-implementing those rules here. Reads are served
    // from the backend's in-memory cache, so this costs one IPC round-trip.
    const unlisten = listen("clipboard-changed", () => {
      if (!isMountedRef.current) return;
      void fetchHistory();
    });

    return () => {
      isMountedRef.current = false;
      unlisten.then((fn) => fn());
    };
  }, [fetchHistory]);

  return { items, isLoading, error, refresh: fetchHistory };
}
