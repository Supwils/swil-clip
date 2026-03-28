import { useCallback, useRef, useState } from "react";
import { Settings2Icon } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogClose,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useSettings } from "@/hooks/useSettings";

// Modifier keys we track (ignore-only keys that don't produce a usable shortcut)
const MODIFIER_KEYS = new Set(["Meta", "Control", "Shift", "Alt"]);

function keyEventToShortcut(event: KeyboardEvent): string | null {
  const modifiers: string[] = [];
  if (event.metaKey) modifiers.push("cmd");
  if (event.ctrlKey) modifiers.push("ctrl");
  if (event.shiftKey) modifiers.push("shift");
  if (event.altKey) modifiers.push("alt");

  // Don't commit if only modifiers are held
  if (MODIFIER_KEYS.has(event.key)) return null;
  // Require at least one modifier to avoid overriding single-key behavior
  if (modifiers.length === 0) return null;

  const key = event.key.toLowerCase();
  return [...modifiers, key].join("+");
}

function formatShortcutDisplay(shortcut: string): string {
  return shortcut
    .split("+")
    .map((part) => {
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
          return part.toUpperCase();
      }
    })
    .join(" ");
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
        // Show partial state (only modifiers pressed so far)
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
        "flex h-8 w-full cursor-pointer items-center rounded-md border px-3 text-sm outline-none transition-colors",
        "select-none font-mono",
        recording
          ? "border-primary bg-primary/5 text-foreground ring-1 ring-primary"
          : "border-border bg-muted/40 text-foreground hover:border-foreground/30",
      ].join(" ")}
    >
      {recording ? (
        <span className="text-foreground-subtle">
          {preview ?? "Press shortcut…"}
        </span>
      ) : (
        <span>{formatShortcutDisplay(current)}</span>
      )}
    </div>
  );
}

interface SettingsDialogProps {
  onClearAll: () => Promise<void>;
}

export function SettingsDialog({ onClearAll }: SettingsDialogProps): React.ReactElement {
  const { settings, isLoading, updateGlobalShortcut } = useSettings();
  const [pendingShortcut, setPendingShortcut] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmingClear, setConfirmingClear] = useState(false);

  const displayShortcut = pendingShortcut ?? settings.globalShortcut;

  const handleSave = useCallback(async () => {
    if (!pendingShortcut) return;
    setSaving(true);
    setError(null);
    try {
      await updateGlobalShortcut(pendingShortcut);
      setPendingShortcut(null);
    } catch {
      setError("This shortcut is already in use or unsupported. Try another.");
    } finally {
      setSaving(false);
    }
  }, [pendingShortcut, updateGlobalShortcut]);

  const handleOpenChange = useCallback((open: boolean) => {
    if (!open) {
      setPendingShortcut(null);
      setError(null);
      setConfirmingClear(false);
    }
  }, []);

  const handleClearConfirm = useCallback(async () => {
    await onClearAll();
    setConfirmingClear(false);
  }, [onClearAll]);

  return (
    <Dialog onOpenChange={handleOpenChange}>
      <DialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label="Settings"
            className="text-foreground-subtle hover:text-foreground"
          />
        }
      >
        <Settings2Icon className="size-3.5" />
      </DialogTrigger>

      <DialogContent showCloseButton>
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-4 py-1">
          <div className="flex flex-col gap-1.5">
            <label className="text-xs font-medium text-foreground-subtle">
              Global Shortcut
            </label>
            {!isLoading && (
              <ShortcutRecorder
                current={displayShortcut}
                onRecord={setPendingShortcut}
              />
            )}
            <p className="text-xs text-foreground-subtle opacity-70">
              Click the field and press your desired key combination.
            </p>
            {error && (
              <p className="text-xs text-red-400">{error}</p>
            )}
          </div>

          <div className="flex flex-col gap-1.5 border-t border-border/40 pt-3">
            <label className="text-xs font-medium text-foreground-subtle">
              History
            </label>
            {confirmingClear ? (
              <div className="flex items-center gap-2">
                <span className="flex-1 text-xs text-foreground-subtle">
                  Clear all clipboard history?
                </span>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setConfirmingClear(false)}
                  className="h-7 text-xs"
                >
                  Cancel
                </Button>
                <Button
                  size="sm"
                  onClick={() => void handleClearConfirm()}
                  className="h-7 bg-destructive/80 text-xs text-white hover:bg-destructive"
                >
                  Clear
                </Button>
              </div>
            ) : (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setConfirmingClear(true)}
                className="h-7 w-fit text-xs text-destructive/70 hover:bg-destructive/10 hover:text-destructive"
              >
                Clear History
              </Button>
            )}
          </div>
        </div>

        <DialogFooter showCloseButton>
          {pendingShortcut && (
            <DialogClose
              render={
                <Button
                  onClick={handleSave}
                  disabled={saving}
                  size="sm"
                  className="min-w-16"
                />
              }
            >
              {saving ? "Saving…" : "Save"}
            </DialogClose>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
