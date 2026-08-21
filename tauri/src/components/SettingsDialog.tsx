import { useCallback, useEffect, useRef, useState } from "react";
import { Settings2Icon } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import type { UseSettingsReturn } from "@/hooks/useSettings";
import { DEFAULT_GLOBAL_SHORTCUT } from "@/constants";
import { HISTORY_CAP_CHOICES } from "@/types/settings";

// Modifier keys we track (ignore-only keys that don't produce a usable shortcut)
const MODIFIER_KEYS = new Set(["Meta", "Control", "Shift", "Alt"]);

function keyEventToShortcut(event: KeyboardEvent): string | null {
  const modifiers: string[] = [];
  if (event.metaKey) modifiers.push("cmd");
  if (event.ctrlKey) modifiers.push("ctrl");
  if (event.shiftKey) modifiers.push("shift");
  if (event.altKey) modifiers.push("alt");

  if (MODIFIER_KEYS.has(event.key)) return null;
  if (modifiers.length === 0) return null;

  const key = event.key.toLowerCase();
  return [...modifiers, key].join("+");
}

function formatShortcutParts(shortcut: string): string[] {
  return shortcut.split("+").map((part) => {
    switch (part) {
      case "cmd":
        return "⌘";
      case "shift":
        return "⇧";
      case "alt":
        return "⌥";
      case "ctrl":
        return "⌃";
      default:
        return part.length === 1 ? part.toUpperCase() : part;
    }
  });
}

interface ShortcutRecorderProps {
  current: string;
  onRecord: (shortcut: string) => void;
}

function ShortcutRecorder({ current, onRecord }: ShortcutRecorderProps): React.ReactElement {
  const [recording, setRecording] = useState(false);
  const [preview, setPreview] = useState<string | null>(null);
  const recorderRef = useRef<HTMLDivElement>(null);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      event.preventDefault();
      event.stopPropagation();

      const shortcut = keyEventToShortcut(event.nativeEvent);
      if (shortcut) {
        setPreview(null);
        setRecording(false);
        onRecord(shortcut);
        recorderRef.current?.blur();
      } else {
        const modifiers: string[] = [];
        if (event.metaKey) modifiers.push("⌘");
        if (event.ctrlKey) modifiers.push("⌃");
        if (event.shiftKey) modifiers.push("⇧");
        if (event.altKey) modifiers.push("⌥");
        if (modifiers.length > 0) setPreview(modifiers.join(" ") + " …");
      }
    },
    [onRecord],
  );

  const handleKeyUp = useCallback(() => {
    setPreview(null);
  }, []);

  const parts = formatShortcutParts(current);

  return (
    <div
      ref={recorderRef}
      tabIndex={0}
      role="button"
      aria-label="Shortcut recorder — click and press new shortcut"
      onFocus={() => setRecording(true)}
      onBlur={() => {
        setRecording(false);
        setPreview(null);
      }}
      onKeyDown={handleKeyDown}
      onKeyUp={handleKeyUp}
      className={[
        "flex h-9 w-full cursor-pointer items-center justify-between gap-2 rounded-lg border px-2.5 text-sm outline-none transition-all duration-150",
        "select-none",
        recording
          ? "border-accent/60 bg-accent-soft text-foreground ring-2 ring-accent/25"
          : "border-border-subtle bg-surface-sunk text-foreground hover:border-border-strong",
      ].join(" ")}
    >
      {recording ? (
        <span className="text-foreground-subtle text-[12px]">
          {preview ?? "Press shortcut…"}
        </span>
      ) : (
        <div className="flex items-center gap-1">
          {parts.map((part, i) => (
            <kbd
              key={`${part}-${i}`}
              className="!h-6 min-w-[24px] px-1.5 text-[11px] font-medium text-foreground"
            >
              {part}
            </kbd>
          ))}
        </div>
      )}
      <span className="text-[10px] uppercase tracking-wider text-foreground-faint">
        {recording ? "Recording" : "Click to change"}
      </span>
    </div>
  );
}

interface HistoryCapSelectorProps {
  current: number;
  onChange: (value: number) => void;
  disabled?: boolean;
}

function HistoryCapSelector({
  current,
  onChange,
  disabled,
}: HistoryCapSelectorProps): React.ReactElement {
  return (
    <div
      role="radiogroup"
      aria-label="History size"
      className="flex h-9 w-full items-center rounded-lg border border-border-subtle bg-surface-sunk p-0.5"
    >
      {HISTORY_CAP_CHOICES.map((value) => {
        const selected = value === current;
        return (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={selected}
            disabled={disabled}
            onClick={() => {
              if (!selected) onChange(value);
            }}
            className={[
              "flex h-full flex-1 items-center justify-center rounded-md text-[12px] font-medium tabular-nums transition-all duration-150",
              selected
                ? "bg-accent text-accent-foreground shadow-[0_1px_2px_rgba(0,0,0,0.2)]"
                : "text-foreground-muted hover:bg-surface-hover hover:text-foreground",
              "disabled:cursor-not-allowed disabled:opacity-50",
            ].join(" ")}
          >
            {value}
          </button>
        );
      })}
    </div>
  );
}

interface SettingsDialogProps {
  onClearAll: () => Promise<boolean>;
  /** Incrementing counter — when it changes, the dialog opens. */
  openRequestId?: number;
  /** The app-wide settings instance (owned by App) — shared, not re-fetched,
   *  so changes made here are immediately reflected everywhere. */
  settingsApi: UseSettingsReturn;
}

export function SettingsDialog({
  onClearAll,
  openRequestId,
  settingsApi,
}: SettingsDialogProps): React.ReactElement {
  const { settings, isLoading, updateGlobalShortcut, updateMaxHistory, updateAutoPaste } =
    settingsApi;
  const [open, setOpen] = useState(false);
  const [pendingShortcut, setPendingShortcut] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmingClear, setConfirmingClear] = useState(false);
  const [savingHistorySize, setSavingHistorySize] = useState(false);
  const [savingAutoPaste, setSavingAutoPaste] = useState(false);

  const lastRequestIdRef = useRef(openRequestId ?? 0);

  // Open externally via tray "Settings…" menu (incrementing request id).
  useEffect(() => {
    if (openRequestId === undefined) return;
    if (openRequestId !== lastRequestIdRef.current) {
      lastRequestIdRef.current = openRequestId;
      setOpen(true);
    }
  }, [openRequestId]);

  const displayShortcut = pendingShortcut ?? settings.globalShortcut;
  const canResetShortcut =
    !pendingShortcut && settings.globalShortcut !== DEFAULT_GLOBAL_SHORTCUT;

  const handleSave = useCallback(async () => {
    if (!pendingShortcut) return;
    setSaving(true);
    setError(null);
    try {
      await updateGlobalShortcut(pendingShortcut);
      setPendingShortcut(null);
      // Close only on success — a failed save must keep the dialog open so
      // the error below is actually visible and the recording isn't lost.
      setOpen(false);
    } catch {
      setError("This shortcut is already in use or unsupported. Try another.");
    } finally {
      setSaving(false);
    }
  }, [pendingShortcut, updateGlobalShortcut]);

  const handleResetShortcut = useCallback(() => {
    setPendingShortcut(DEFAULT_GLOBAL_SHORTCUT);
  }, []);

  const handleOpenChange = useCallback((nextOpen: boolean) => {
    setOpen(nextOpen);
    if (!nextOpen) {
      setPendingShortcut(null);
      setError(null);
      setConfirmingClear(false);
    }
  }, []);

  const handleClearConfirm = useCallback(async () => {
    await onClearAll();
    setConfirmingClear(false);
  }, [onClearAll]);

  const handleHistoryCapChange = useCallback(
    async (value: number) => {
      setSavingHistorySize(true);
      try {
        await updateMaxHistory(value);
      } finally {
        setSavingHistorySize(false);
      }
    },
    [updateMaxHistory],
  );

  const handleAutoPasteToggle = useCallback(async () => {
    setSavingAutoPaste(true);
    try {
      await updateAutoPaste(!settings.autoPaste);
    } finally {
      setSavingAutoPaste(false);
    }
  }, [settings.autoPaste, updateAutoPaste]);

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label="Settings"
            className="h-7 w-7 rounded-md text-foreground-muted hover:bg-surface-hover hover:text-foreground"
          />
        }
      >
        <Settings2Icon className="size-3.5" />
      </DialogTrigger>

      <DialogContent showCloseButton className="gap-3 p-5">
        <DialogHeader className="gap-1">
          <DialogTitle className="text-[15px] tracking-tight">Settings</DialogTitle>
          <p className="text-[11px] text-foreground-faint">
            Personalize how SwilClip behaves.
          </p>
        </DialogHeader>

        <div className="flex flex-col gap-5 py-1">
          {/* Global shortcut */}
          <section className="flex flex-col gap-2">
            <div className="flex items-baseline justify-between">
              <label className="text-[11px] font-semibold uppercase tracking-wider text-foreground-faint">
                Global Shortcut
              </label>
              {canResetShortcut && (
                <button
                  type="button"
                  onClick={handleResetShortcut}
                  className="text-[10px] text-foreground-faint underline-offset-2 transition-colors hover:text-accent hover:underline"
                >
                  Reset to default
                </button>
              )}
            </div>
            {!isLoading && (
              <ShortcutRecorder
                current={displayShortcut}
                onRecord={setPendingShortcut}
              />
            )}
            <p className="text-[11px] leading-snug text-foreground-faint">
              Press this combination from anywhere to summon the panel.
            </p>
            {error && <p className="text-[11px] text-destructive">{error}</p>}
          </section>

          <div className="hairline" aria-hidden />

          {/* History size */}
          <section className="flex flex-col gap-2">
            <label className="text-[11px] font-semibold uppercase tracking-wider text-foreground-faint">
              History size
            </label>
            <HistoryCapSelector
              current={settings.maxHistory}
              onChange={(v) => void handleHistoryCapChange(v)}
              disabled={isLoading || savingHistorySize}
            />
            <p className="text-[11px] leading-snug text-foreground-faint">
              How many unpinned items to keep. Lowering immediately trims the
              oldest. Pinned items never count toward this and are always kept.
            </p>
          </section>

          <div className="hairline" aria-hidden />

          {/* Paste behavior */}
          <section className="flex flex-col gap-2">
            <label className="text-[11px] font-semibold uppercase tracking-wider text-foreground-faint">
              Paste behavior
            </label>
            <button
              type="button"
              role="switch"
              aria-checked={settings.autoPaste}
              disabled={isLoading || savingAutoPaste}
              onClick={() => void handleAutoPasteToggle()}
              className="flex items-center justify-between gap-3 rounded-lg border border-border-subtle bg-surface-sunk px-3 py-2 text-left transition-colors hover:border-border-strong disabled:cursor-not-allowed disabled:opacity-50"
            >
              <span className="flex flex-col gap-0.5">
                <span className="text-[12px] font-medium text-foreground">
                  Auto-paste after selecting
                </span>
                <span className="text-[10.5px] text-foreground-faint">
                  {settings.autoPaste
                    ? "Press ⏎ to copy AND paste into your previous app."
                    : "Press ⏎ to copy only — paste with ⌘V yourself."}
                </span>
              </span>
              <span
                className={[
                  "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors duration-150",
                  settings.autoPaste ? "bg-accent" : "bg-surface-hover",
                ].join(" ")}
              >
                <span
                  className={[
                    "absolute top-0.5 h-4 w-4 rounded-full bg-white shadow-sm transition-transform duration-150",
                    settings.autoPaste ? "translate-x-[18px]" : "translate-x-0.5",
                  ].join(" ")}
                />
              </span>
            </button>
          </section>

          <div className="hairline" aria-hidden />

          {/* Clear history */}
          <section className="flex flex-col gap-2">
            <label className="text-[11px] font-semibold uppercase tracking-wider text-foreground-faint">
              Danger zone
            </label>
            {confirmingClear ? (
              <div className="flex items-center gap-2 rounded-lg bg-destructive/10 px-2.5 py-2">
                <span className="flex-1 text-[11px] text-foreground">
                  Delete all history? This can't be undone.
                </span>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setConfirmingClear(false)}
                  className="h-7 px-2.5 text-xs"
                >
                  Cancel
                </Button>
                <Button
                  size="sm"
                  onClick={() => void handleClearConfirm()}
                  className="h-7 bg-destructive px-2.5 text-xs text-white hover:bg-destructive/90"
                >
                  Delete
                </Button>
              </div>
            ) : (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setConfirmingClear(true)}
                className="h-7 w-fit px-2.5 text-xs text-destructive/80 hover:bg-destructive/10 hover:text-destructive"
              >
                Clear all history…
              </Button>
            )}
          </section>
        </div>

        <DialogFooter showCloseButton className="mt-1">
          {pendingShortcut && (
            <Button
              onClick={() => void handleSave()}
              disabled={saving}
              size="sm"
              className="min-w-16 bg-accent text-accent-foreground hover:bg-accent/90"
            >
              {saving ? "Saving…" : "Save shortcut"}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
