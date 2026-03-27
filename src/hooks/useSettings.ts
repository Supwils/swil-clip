import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { AppSettings } from "@/types/settings";
import { DEFAULT_SETTINGS } from "@/types/settings";

interface UseSettingsReturn {
  settings: AppSettings;
  isLoading: boolean;
  updateGlobalShortcut: (shortcut: string) => Promise<void>;
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

  return { settings, isLoading, updateGlobalShortcut };
}
