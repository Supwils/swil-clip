import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import {
  ClipboardIcon,
  SearchIcon,
  Trash2Icon,
  Undo2Icon,
} from "lucide-react";
import {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
} from "@/components/ui/command";
import { ClipItem } from "@/components/ClipItem";
import { SettingsDialog } from "@/components/SettingsDialog";
import { PANEL_DRAG_REGION_HEIGHT_PX } from "@/constants";
import { useDragReorder } from "@/hooks/useDragReorder";
import type { ClipItem as ClipItemType } from "@/types/clipboard";

type PanelMode = "navigate" | "search";

interface ClipboardPanelProps {
  items: ClipItemType[];
  onPaste: (item: ClipItemType) => Promise<boolean>;
  onDelete: (id: string) => Promise<boolean>;
  onClearAll: () => Promise<boolean>;
  onClearUnpinned: () => Promise<boolean>;
  onUndo: () => Promise<boolean>;
  canUndo: boolean;
  onPin: (id: string, pinned: boolean) => Promise<boolean>;
  onReorder?: (orderedIds: string[], pinnedIds: string[]) => Promise<boolean>;
  onHide: () => void;
  isBusy: boolean;
  /** Incrementing token from App — when it bumps, open the Settings dialog. */
  settingsRequestId?: number;
  /** Whether Enter should auto-paste (true) or just copy (false). Drives the
   *  ⏎ hint label so users always see the truth about what's about to happen. */
  autoPaste?: boolean;
}

// MUST stay in sync with what cmdk persists on the rendered DOM. cmdk runs
// `String.prototype.trim()` on every item value before storing it on the
// `data-value` attribute (see cmdk/dist/index.mjs — `R.trim()` in the value
// effect, then `setAttribute("data-value", f)`). If we keep an untrimmed
// version on the React side, three things break in concert any time a
// preview ends in whitespace (extremely common, since
// `text.chars().take(200)` regularly cuts at a space/newline — and that is
// exactly what makes an item "expandable" too):
//
//   1. `getActiveItemValue()` reads the trimmed DOM value; `findItemByValue`
//      compares it to the untrimmed React value → mismatch → `d` no-ops.
//   2. `handleDelete`'s `targetingSelected` check has the same mismatch →
//      selection migration is skipped → cmdk's W() falls back to item[0]
//      and the highlight jumps to the top after delete.
//   3. The CSS-attribute selector used by ArrowDown/Up's `scrollIntoView`
//      would look for the untrimmed value and miss the element.
//
// Trimming on this side keeps a single normalized representation across
// React state, cmdk's internal store, and the rendered DOM.
function getItemValue(item: ClipItemType): string {
  return `${item.id}-${item.preview}`.trim();
}

function findItemByValue(items: ClipItemType[], cmdkValue: string): ClipItemType | undefined {
  return items.find((item) => cmdkValue === getItemValue(item));
}

interface KeyHintProps {
  keys: string[];
  label: string;
}

/** A compact (kbd + caption) pair for the footer hint reel. */
function KeyHint({ keys, label }: KeyHintProps): React.ReactElement {
  return (
    <span className="flex items-center gap-1 text-foreground-faint">
      {keys.map((k) => (
        <kbd key={k}>{k}</kbd>
      ))}
      <span className="text-[10px]">{label}</span>
    </span>
  );
}

export function ClipboardPanel({
  items,
  onPaste,
  onDelete,
  onClearAll,
  onClearUnpinned,
  onUndo,
  canUndo,
  onPin,
  onReorder,
  onHide,
  isBusy,
  settingsRequestId,
  autoPaste = false,
}: ClipboardPanelProps): React.ReactElement {
  const [mode, setMode] = useState<PanelMode>("navigate");
  const [search, setSearch] = useState("");
  // Eager init — first render already has a valid selection so arrow keys
  // work from the very first keystroke. Without this, the initial paint had
  // selectedValue="" until a post-paint effect set it, and the very first
  // arrow key (or any keystroke) could fall through to an empty selection.
  const [selectedValue, setSelectedValue] = useState(() =>
    items.length > 0 ? getItemValue(items[0]!) : "",
  );
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  const commandRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const mutationInFlightRef = useRef(false);
  // See ClipboardPanel notes — guards cmdk auto-select during delete migration.
  const pendingTargetValueRef = useRef<string | null>(null);

  // Focus management — robust against Tauri WebView focus timing.
  //
  // Background: Tauri panel windows (decorations:false + alwaysOnTop) can be
  // shown without the OS-level keyboard focus landing on the WebView right
  // away. Calling commandRef.focus() once in a useLayoutEffect sometimes
  // fires before the WebView is "active" and silently no-ops — leaving
  // focus on <body>, which means arrow-key events never bubble through
  // cmdk-root and the keyboard appears dead.
  //
  // Previously we got lucky: cmdk's pointer-move side-effect would refocus
  // cmdk-root the moment the mouse touched an item, masking the timing
  // problem. With disablePointerSelection (intentional, to keep mouse from
  // hijacking keyboard nav) that implicit recovery is gone, so we own
  // focus explicitly:
  //
  // - Multi-stage retry on EVERY transition into navigate mode (layout +
  //   rAF + a 50ms safety net), gated by `mode === "navigate"` so the
  //   safety net doesn't steal focus from the search input after a `s` press.
  // - focusin listener bounces cmdk-input → root in navigate mode (cmdk
  //   tries to focus the search input on every setState("value")).
  // - window.focus listener re-anchors on every WebView gain-focus event.
  useLayoutEffect(() => {
    if (mode !== "navigate") return;
    commandRef.current?.focus();
    const rafHandle = requestAnimationFrame(() => {
      commandRef.current?.focus();
    });
    const timeoutHandle = setTimeout(() => {
      commandRef.current?.focus();
    }, 50);
    return () => {
      cancelAnimationFrame(rafHandle);
      clearTimeout(timeoutHandle);
    };
  }, [mode]);

  useEffect(() => {
    if (mode !== "navigate") return;
    const handleFocusIn = (event: FocusEvent) => {
      const target = event.target;
      if (target instanceof HTMLElement && target.hasAttribute("cmdk-input")) {
        commandRef.current?.focus();
      }
    };
    document.addEventListener("focusin", handleFocusIn);
    return () => document.removeEventListener("focusin", handleFocusIn);
  }, [mode]);

  useEffect(() => {
    if (mode !== "navigate") return;
    const handleWindowFocus = () => {
      requestAnimationFrame(() => commandRef.current?.focus());
    };
    window.addEventListener("focus", handleWindowFocus);
    return () => window.removeEventListener("focus", handleWindowFocus);
  }, [mode]);

  // Keep selectedValue aligned with a real item so keyboard shortcuts never
  // silently no-op on a stale or empty selection.
  useEffect(() => {
    if (pendingTargetValueRef.current !== null) return;
    if (items.length === 0) {
      if (selectedValue !== "") setSelectedValue("");
      return;
    }
    if (selectedValue && items.some((item) => getItemValue(item) === selectedValue)) {
      return;
    }
    setSelectedValue(getItemValue(items[0]!));
  }, [items, selectedValue]);

  const handleSelect = useCallback(
    (item: ClipItemType) => {
      void onPaste(item);
    },
    [onPaste],
  );

  const getActiveItemValue = useCallback((): string => {
    const selectedItem = commandRef.current?.querySelector('[cmdk-item][aria-selected="true"]');
    if (selectedItem instanceof HTMLElement) {
      return selectedItem.getAttribute("data-value") ?? selectedValue;
    }

    return selectedValue;
  }, [selectedValue]);

  const handleValueChange = useCallback((nextValue: string) => {
    const pendingTarget = pendingTargetValueRef.current;
    if (pendingTarget !== null && nextValue !== pendingTarget) {
      return;
    }
    setSelectedValue(nextValue);
  }, []);

  const runLockedMutation = useCallback(async (operation: () => Promise<boolean>) => {
    if (mutationInFlightRef.current) {
      return false;
    }

    mutationInFlightRef.current = true;
    try {
      return await operation();
    } finally {
      mutationInFlightRef.current = false;
    }
  }, []);

  const handleDelete = useCallback(
    (id: string, activeValue?: string) => {
      void runLockedMutation(async () => {
        const index = items.findIndex((item) => item.id === id);
        if (index === -1) {
          return false;
        }

        const item = items[index]!;
        const targetingSelected =
          (activeValue ?? selectedValue) === getItemValue(item);
        let targetValue: string | null = null;

        if (targetingSelected) {
          // "Stay in the same position, next term slides up" — pick the item
          // that will occupy this index after removal. If the deleted item
          // was the last, fall back to the previous one (cursor stays at the
          // new last row).
          const remaining = items.filter((existing) => existing.id !== id);
          const target = remaining[index] ?? remaining[index - 1];
          targetValue = target ? getItemValue(target) : "";
          // Lock selection before the items refresh so cmdk's W() (auto-pick
          // first when the selected item unmounts) can't slip a wrong value
          // through onValueChange while the migration is in flight.
          pendingTargetValueRef.current = targetValue;
        }

        try {
          const didDelete = await onDelete(id);

          if (targetingSelected && didDelete && targetValue !== null) {
            // Items have refreshed — commit the migrated selection now.
            setSelectedValue(targetValue);
            // Release the lock after the React batch settles so cmdk's
            // post-render onValueChange (if any) has already been suppressed.
            await new Promise<void>((resolve) => setTimeout(resolve, 0));
          }

          return didDelete;
        } finally {
          if (targetingSelected && pendingTargetValueRef.current === targetValue) {
            pendingTargetValueRef.current = null;
          }
        }
      });
    },
    [items, onDelete, runLockedMutation, selectedValue],
  );

  const handlePin = useCallback(
    (id: string, pinned: boolean) =>
      runLockedMutation(() => onPin(id, pinned)),
    [onPin, runLockedMutation],
  );

  const handleToggleExpand = useCallback((id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (e.nativeEvent.isComposing || e.keyCode === 229) {
        return;
      }

      if (
        (isBusy || mutationInFlightRef.current) &&
        (e.key === "Enter" || e.key === "d" || e.key === "p" || e.key === "u")
      ) {
        e.preventDefault();
        e.stopPropagation();
        return;
      }

      if (mode === "navigate") {
        // ── Direct keyboard navigation (don't delegate to cmdk's Q()) ──
        //
        // We previously let cmdk handle Arrow/Home/End. Its Q() function
        // walks `V()` (a live DOM queryAll) to find the current item, and
        // under some combinations of disablePointerSelection + controlled
        // value + display:none search input, that DOM walk would land on
        // the wrong row (e.g. Down from Pinned[0] no-ops, Up from
        // Pinned[last] jumps to Pinned[0]). The symptoms looked like
        // "middle pinned items aren't in the navigation list."
        //
        // Solution: do the navigation ourselves against the React `items`
        // array (which is the source of truth) and just push the chosen
        // value into selectedValue. cmdk syncs the highlight from there.
        if (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Home" || e.key === "End") {
          if (items.length === 0) {
            e.preventDefault();
            return;
          }
          e.preventDefault();
          e.stopPropagation();
          const currentIdx = items.findIndex(
            (item) => getItemValue(item) === selectedValue,
          );
          let nextIdx: number;
          if (e.key === "Home") {
            nextIdx = 0;
          } else if (e.key === "End") {
            nextIdx = items.length - 1;
          } else if (e.key === "ArrowDown") {
            // Cmd+Down jumps to end (matches cmdk's Cmd+Down semantics)
            if (e.metaKey) {
              nextIdx = items.length - 1;
            } else if (currentIdx === -1) {
              nextIdx = 0;
            } else if (currentIdx === items.length - 1) {
              nextIdx = 0; // loop to top
            } else {
              nextIdx = currentIdx + 1;
            }
          } else {
            // ArrowUp
            if (e.metaKey) {
              nextIdx = 0;
            } else if (currentIdx === -1) {
              nextIdx = items.length - 1;
            } else if (currentIdx === 0) {
              nextIdx = items.length - 1; // loop to bottom
            } else {
              nextIdx = currentIdx - 1;
            }
          }
          const nextItem = items[nextIdx]!;
          setSelectedValue(getItemValue(nextItem));
          // Scroll the row into view — cmdk normally does this via its own
          // selection path, but since we bypassed it we need to do it here.
          requestAnimationFrame(() => {
            const el = commandRef.current?.querySelector<HTMLElement>(
              `[cmdk-item][data-value="${CSS.escape(getItemValue(nextItem))}"]`,
            );
            el?.scrollIntoView({ block: "nearest" });
          });
          return;
        }

        if (e.key === "s") {
          e.preventDefault();
          e.stopPropagation();
          setMode("search");
          requestAnimationFrame(() => inputRef.current?.focus());
          return;
        }
        if (e.key === "d") {
          e.preventDefault();
          e.stopPropagation();
          const activeValue = getActiveItemValue();
          const item = findItemByValue(items, activeValue);
          if (!item) return;
          handleDelete(item.id, activeValue);
          return;
        }
        if (e.key === "p") {
          e.preventDefault();
          e.stopPropagation();
          const item = findItemByValue(items, getActiveItemValue());
          if (item) {
            void handlePin(item.id, !item.pinned);
          }
          return;
        }
        if (e.key === "e") {
          e.preventDefault();
          e.stopPropagation();
          const item = findItemByValue(items, getActiveItemValue());
          if (item && item.clipType !== "image" && item.content.length > item.preview.length) {
            handleToggleExpand(item.id);
          }
          return;
        }
        if (e.key === "u") {
          e.preventDefault();
          e.stopPropagation();
          if (canUndo) void onUndo();
          return;
        }
        if (e.key === "Escape") {
          e.preventDefault();
          onHide();
          return;
        }
        if (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) {
          e.preventDefault();
          return;
        }
      }

      if (mode === "search") {
        if (e.key === "Escape") {
          e.preventDefault();
          e.stopPropagation();
          setSearch("");
          setMode("navigate");
          inputRef.current?.blur();
          requestAnimationFrame(() => commandRef.current?.focus());
          return;
        }
      }
    },
    [
      canUndo,
      handleDelete,
      getActiveItemValue,
      handleToggleExpand,
      isBusy,
      items,
      mode,
      onHide,
      onUndo,
      handlePin,
      selectedValue,
    ],
  );

  const { pinnedItems, recentItems } = useMemo(() => {
    const pinned: ClipItemType[] = [];
    const recent: ClipItemType[] = [];
    for (const item of items) {
      if (item.pinned) pinned.push(item);
      else recent.push(item);
    }
    return { pinnedItems: pinned, recentItems: recent };
  }, [items]);

  // Drag-and-drop reorder. onReorder is optional — when absent (e.g. unit
  // tests that don't wire reorder), drag handlers stay no-op and the grip
  // handle is hidden via the falsy section/handler check in ClipItem.
  const dragCommit = useCallback(
    async (orderedIds: string[], pinnedIds: string[]) => {
      if (!onReorder) return false;
      return onReorder(orderedIds, pinnedIds);
    },
    [onReorder],
  );
  const dragApi = useDragReorder({
    pinned: pinnedItems,
    recent: recentItems,
    onCommit: dragCommit,
  });
  const { drag, isDragging, onDragStart, onItemDragOver, onItemDragLeave, onItemDrop, onDragEnd } =
    dragApi;

  const dropPositionFor = useCallback(
    (id: string) => {
      if (!drag || drag.overItemId !== id) return null;
      return drag.position;
    },
    [drag],
  );

  const itemCount = items.length;
  const canClear = items.some((i) => !i.pinned);
  const isSearching = mode === "search";
  const reorderEnabled = Boolean(onReorder);

  return (
    <Command
      ref={commandRef}
      tabIndex={-1}
      className="flex h-full flex-col bg-transparent p-0 outline-none"
      loop
      // Keyboard is the source of truth for selection — disable cmdk's
      // pointer-move auto-select so the mouse cursor's accidental position
      // can't hijack the keyboard cursor (especially during the async window
      // right after a delete/pin, where the list re-flows under the cursor).
      // Click-to-paste still works (that's a separate handler).
      disablePointerSelection
      value={selectedValue}
      onValueChange={handleValueChange}
      onKeyDown={handleKeyDown}
    >
      {/* Drag region — the strip you grab to move the window */}
      <div
        className="panel-drag-region"
        data-tauri-drag-region
        style={{ height: PANEL_DRAG_REGION_HEIGHT_PX }}
        aria-label="Drag to move window"
      />

      {/* Header — brand + count + settings */}
      <div
        className="flex shrink-0 items-center justify-between"
        style={{
          paddingLeft: "var(--px-edge)",
          paddingRight: "6px",
          paddingTop: "1px",
          paddingBottom: "4px",
        }}
      >
        <div className="flex items-center gap-1.5">
          <span className="text-[10.5px] font-semibold tracking-tight text-foreground-muted">
            SwilClip
          </span>
          {itemCount > 0 && (
            <span className="rounded-full bg-surface-soft px-1.5 py-px text-[8.5px] font-medium tabular-nums leading-none text-foreground-faint ring-[0.5px] ring-inset ring-border-subtle">
              {itemCount}
            </span>
          )}
        </div>
        <SettingsDialog onClearAll={onClearAll} openRequestId={settingsRequestId} />
      </div>

      {/* Search input — always mounted (so React state can clear it
       * on Escape and tests can hold a stable ref), but `display: none`
       * when not searching.
       *
       * Critical: cmdk's setState("value") side-effect calls
       * cmdk-input.focus() on every arrow keypress if the cmdk root is
       * focused. On a `display: none` element, focus() is a no-op in all
       * major browsers — so focus stays on the cmdk root and arrow keys
       * keep flowing to it. THIS is what makes keyboard navigation
       * reliable. Do not change to a visually-hidden-but-displayed
       * approach (visibility: hidden, opacity: 0, max-height: 0, etc.) —
       * those keep the element focusable and re-introduce the focus theft. */}
      <div
        className="shrink-0"
        style={{
          paddingLeft: "var(--px-edge)",
          paddingRight: "var(--px-edge)",
          display: isSearching ? undefined : "none",
        }}
        aria-hidden={!isSearching}
      >
        <CommandInput
          ref={inputRef}
          placeholder="Search clipboard..."
          value={search}
          onValueChange={setSearch}
        />
      </div>

      {/* List */}
      <CommandList
        className="max-h-none flex-1 overflow-y-auto"
        style={{
          paddingLeft: "calc(var(--px-edge) - var(--px-row))",
          paddingRight: "calc(var(--px-edge) - var(--px-row))",
          paddingTop: "1px",
          paddingBottom: "2px",
        }}
      >
        <CommandEmpty className="flex flex-col items-center justify-center gap-3 px-6 py-14 text-center">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-surface-soft ring-[0.5px] ring-inset ring-border-subtle">
            <ClipboardIcon className="size-5 text-foreground-faint" strokeWidth={1.5} />
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-[12px] font-medium text-foreground-muted">
              {search ? "No matches" : "Clipboard is empty"}
            </span>
            <span className="text-[10.5px] text-foreground-faint">
              {search ? "Try a different query" : "Copy anything to get started"}
            </span>
          </div>
        </CommandEmpty>

        {pinnedItems.length > 0 && (
          <CommandGroup heading="Pinned">
            {pinnedItems.map((item, index) => (
              <ClipItem
                key={item.id}
                item={item}
                index={index}
                onSelect={handleSelect}
                onDelete={handleDelete}
                onPin={handlePin}
                isExpanded={expandedIds.has(item.id)}
                onToggleExpand={handleToggleExpand}
                searchQuery={isSearching ? search : undefined}
                section={reorderEnabled ? "pinned" : undefined}
                isDragging={drag?.itemId === item.id}
                isAnyDragging={isDragging}
                dropPosition={dropPositionFor(item.id)}
                onItemDragStart={reorderEnabled ? onDragStart : undefined}
                onItemDragOver={reorderEnabled ? onItemDragOver : undefined}
                onItemDragLeave={reorderEnabled ? onItemDragLeave : undefined}
                onItemDrop={reorderEnabled ? onItemDrop : undefined}
                onItemDragEnd={reorderEnabled ? onDragEnd : undefined}
              />
            ))}
          </CommandGroup>
        )}
        <CommandGroup heading={pinnedItems.length > 0 ? "Recent" : undefined}>
          {recentItems.map((item, index) => (
            <ClipItem
              key={item.id}
              item={item}
              index={pinnedItems.length + index}
              onSelect={handleSelect}
              onDelete={handleDelete}
              onPin={handlePin}
              isExpanded={expandedIds.has(item.id)}
              onToggleExpand={handleToggleExpand}
              searchQuery={isSearching ? search : undefined}
              section={reorderEnabled ? "recent" : undefined}
              isDragging={drag?.itemId === item.id}
              isAnyDragging={isDragging}
              dropPosition={dropPositionFor(item.id)}
              onItemDragStart={reorderEnabled ? onDragStart : undefined}
              onItemDragOver={reorderEnabled ? onItemDragOver : undefined}
              onItemDragLeave={reorderEnabled ? onItemDragLeave : undefined}
              onItemDrop={reorderEnabled ? onItemDrop : undefined}
              onItemDragEnd={reorderEnabled ? onDragEnd : undefined}
            />
          ))}
        </CommandGroup>
      </CommandList>

      {/* Footer — unified actions + hint reel */}
      <div className="hairline" aria-hidden />
      <div
        className="flex shrink-0 items-center justify-between gap-2"
        style={{
          paddingLeft: "calc(var(--px-edge) - 2px)",
          paddingRight: "calc(var(--px-edge) - 2px)",
          paddingTop: "3px",
          paddingBottom: "4px",
        }}
      >
        {/* Left: tool buttons */}
        <div className="flex items-center gap-0.5">
          <button
            type="button"
            disabled={isBusy || !canClear}
            onClick={() => void onClearUnpinned()}
            onMouseDown={(e) => e.preventDefault()}
            className="flex h-6 items-center gap-1 rounded-md px-1.5 text-[10px] font-medium text-foreground-faint transition-colors hover:bg-destructive/12 hover:text-destructive disabled:pointer-events-none disabled:opacity-30"
            aria-label="Clear all unpinned items"
            title="Clear unpinned"
          >
            <Trash2Icon className="size-3" />
            <span>Clear</span>
          </button>
          <button
            type="button"
            disabled={isBusy || !canUndo}
            onClick={() => void onUndo()}
            onMouseDown={(e) => e.preventDefault()}
            className="flex h-6 items-center gap-1 rounded-md px-1.5 text-[10px] font-medium text-foreground-faint transition-colors hover:bg-accent-soft hover:text-foreground disabled:pointer-events-none disabled:opacity-30"
            aria-label="Undo last deletion"
            title="Undo"
          >
            <Undo2Icon className="size-3" />
            <span>Undo</span>
          </button>
          {!isSearching && (
            <button
              type="button"
              onClick={() => {
                setMode("search");
                requestAnimationFrame(() => inputRef.current?.focus());
              }}
              onMouseDown={(e) => e.preventDefault()}
              className="flex h-6 items-center gap-1 rounded-md px-1.5 text-[10px] font-medium text-foreground-faint transition-colors hover:bg-surface-hover hover:text-foreground"
              aria-label="Search clipboard"
              title="Search"
            >
              <SearchIcon className="size-3" />
              <span>Search</span>
            </button>
          )}
        </div>

        {/* Right: kbd hint reel */}
        <div className="flex items-center gap-2 text-[10px]">
          {isSearching ? (
            <>
              <KeyHint keys={["↵"]} label={autoPaste ? "Paste" : "Copy"} />
              <KeyHint keys={["esc"]} label="Back" />
            </>
          ) : (
            <>
              <KeyHint keys={["↵"]} label={autoPaste ? "Paste" : "Copy"} />
              <KeyHint keys={["d"]} label="Del" />
              <KeyHint keys={["p"]} label="Pin" />
              <KeyHint keys={["esc"]} label="Close" />
            </>
          )}
        </div>
      </div>
    </Command>
  );
}
