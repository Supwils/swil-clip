export interface AppSettings {
  globalShortcut: string;
  maxHistory: number;
  /** When true, Enter on a clip both writes the clipboard AND simulates ⌘V
   *  into the previously-focused app. When false, Enter only copies. */
  autoPaste: boolean;
}

/** Curated cap choices exposed in the Settings UI. */
export const HISTORY_CAP_CHOICES = [50, 100, 200, 500] as const;
export type HistoryCap = (typeof HISTORY_CAP_CHOICES)[number];

export const DEFAULT_SETTINGS: AppSettings = {
  globalShortcut: "cmd+shift+v",
  maxHistory: 50,
  autoPaste: false,
};
