import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { AppSettings } from "@/types/settings";
import { DEFAULT_SETTINGS } from "@/types/settings";

interface UseSettingsReturn {
  settings: AppSettings;
  isLoading: boolean;
  updateGlobalShortcut: (shortcut: string) => Promise<void>;
  updateMaxHistory: (value: number) => Promise<void>;
  updateAutoPaste: (value: boolean) => Promise<void>;
}

export function useSettings(): UseSettingsReturn {
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [isLoading, setIsLoading] = useState(true);

  const fetchSettings = useCallback(async () => {
    try {
      const loaded = await invoke<AppSettings>("get_settings");
      setSettings(loaded);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to load settings";
      console.error("Failed to load settings:", message);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  const updateGlobalShortcut = useCallback(async (shortcut: string) => {
    await invoke("update_global_shortcut", { shortcutStr: shortcut });
    setSettings((prev) => ({ ...prev, globalShortcut: shortcut }));
  }, []);

  const updateMaxHistory = useCallback(async (value: number) => {
    // Backend clamps to [10, 1000] and returns the effective value.
    const effective = await invoke<number>("update_max_history", { value });
    setSettings((prev) => ({ ...prev, maxHistory: effective }));
  }, []);

  const updateAutoPaste = useCallback(async (value: boolean) => {
    const effective = await invoke<boolean>("update_auto_paste", { value });
    setSettings((prev) => ({ ...prev, autoPaste: effective }));
  }, []);

  return {
    settings,
    isLoading,
    updateGlobalShortcut,
    updateMaxHistory,
    updateAutoPaste,
  };
}
