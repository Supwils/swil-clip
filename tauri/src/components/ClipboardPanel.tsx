import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { flushSync } from "react-dom";
import {
  AlertTriangleIcon,
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
import { canExpandItem } from "@/lib/clip";
import { fuzzyMatches } from "@/lib/highlight";
import type { UseSettingsReturn } from "@/hooks/useSettings";
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
  /** The app-wide settings instance, threaded through to SettingsDialog. */
  settingsApi: UseSettingsReturn;
  /** Incrementing token from App — when it bumps, open the Settings dialog. */
  settingsRequestId?: number;
  /** Whether Enter should auto-paste (true) or just copy (false). Drives the
   *  ⏎ hint label so users always see the truth about what's about to happen. */
  autoPaste?: boolean;
  /** Why history failed to load (Keychain denied, corrupt blob, …). When set
   *  the empty state becomes an error state with recovery actions — an
   *  unreadable history must never masquerade as an empty one. */
  historyError?: string | null;
  onRetryHistory?: () => Promise<void>;
  /** Wipes the persisted history without needing the encryption key. */
  onResetHistory?: () => Promise<boolean>;
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
  settingsApi,
  settingsRequestId,
  autoPaste = false,
  historyError = null,
  onRetryHistory,
  onResetHistory,
}: ClipboardPanelProps): React.ReactElement {
  const [mode, setMode] = useState<PanelMode>("navigate");
  const [search, setSearch] = useState("");
  // Selection is tracked by item id — stable, whitespace-free, never derived
  // from content. cmdk's value prop is fed from this and cmdk's internal
  // normalization (String.trim) can't change a uuid, so React state, cmdk's
  // store and the DOM data-value attribute agree by construction.
  //
  // Eager init — first render already has a valid selection so arrow keys
  // work from the very first keystroke.
  const [selectedId, setSelectedId] = useState(() => items[0]?.id ?? "");
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [confirmingReset, setConfirmingReset] = useState(false);

  const commandRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const isSearching = mode === "search";

  // Search filtering happens HERE, not inside cmdk (shouldFilter={false}):
  // the rendered list, keyboard navigation, delete-succession and the match
  // highlighting all read the same array, so they can never disagree — and
  // results keep their chronological/pinned order instead of cmdk's score
  // order.
  const visibleItems = useMemo(() => {
    if (!isSearching || search.trim() === "") return items;
    return items.filter((item) => fuzzyMatches(item.preview, search));
  }, [items, isSearching, search]);

  // Ref mirrors so action handlers stay referentially stable (ClipItem is
  // memoized — unstable handlers would defeat that).
  const selectedIdRef = useRef(selectedId);
  selectedIdRef.current = selectedId;
  const visibleItemsRef = useRef(visibleItems);
  visibleItemsRef.current = visibleItems;

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

  // Selection realignment — the single rule for every way a selected item can
  // vanish from the rendered list (deleted under us by another flow, re-id'd
  // by the monitor's dedup when identical content is copied again, filtered
  // out by a narrowing search): keep the user's POSITION. The item now
  // occupying the last known index is selected, clamped to the list end —
  // never a snap back to the top. Because this always produces a value-prop
  // change, cmdk re-syncs its internal store from us and the highlight
  // follows.
  //
  // Deleting via d/click doesn't reach this effect: handleDelete migrates the
  // selection before the item unmounts (see below).
  const lastSelectedIndexRef = useRef(0);
  useEffect(() => {
    if (visibleItems.length === 0) {
      if (selectedId !== "") setSelectedId("");
      return;
    }
    const index = visibleItems.findIndex((item) => item.id === selectedId);
    if (index !== -1) {
      lastSelectedIndexRef.current = index;
      return;
    }
    const nearest =
      visibleItems[Math.min(lastSelectedIndexRef.current, visibleItems.length - 1)]!;
    setSelectedId(nearest.id);
  }, [visibleItems, selectedId]);

  // Last line of defence against React and cmdk disagreeing about what is
  // selected.
  //
  // cmdk keeps its OWN copy of the selected value and there are paths where it
  // rewrites that copy without being asked: it auto-selects the first row when
  // the selected item unmounts, and it selects the clicked row on click. In
  // controlled mode those writes land in cmdk's store, fire `onValueChange`,
  // and return — cmdk's `value`-sync effect only re-runs when `props.value`
  // changes, and it didn't. So with no listener the drift is PERMANENT: the
  // highlight renders from cmdk's store while `d`/`p`/`e` act on React's id.
  // That is how the shipped 0.1.2 build ended up deleting the top row while
  // the user was looking at a different one.
  //
  // Following cmdk here trades a possible surprise cursor move for a
  // guarantee that the row you see highlighted is the row a keystroke hits.
  // The empty case is excluded on purpose: an empty selection belongs to the
  // realignment effect below, which restores the remembered position instead
  // of cmdk's "just take row 0".
  const handleCmdkValueChange = useCallback((nextId: string) => {
    const current = selectedIdRef.current;
    if (current === "" || nextId === current) return;
    if (!visibleItemsRef.current.some((item) => item.id === nextId)) return;
    setSelectedId(nextId);
  }, []);

  const handleSelect = useCallback(
    (item: ClipItemType) => {
      void onPaste(item);
    },
    [onPaste],
  );

  // Rows whose delete is queued but hasn't come back yet. They are still
  // rendered — the backend hasn't confirmed — but they are already doomed, so
  // the successor search below must never land the cursor on one. Without
  // this, holding `d` parks the cursor on a row that is itself about to
  // vanish, and cmdk's selectFirstItem fires when it does.
  const pendingDeletesRef = useRef<Set<string>>(new Set());

  const handleDelete = useCallback(
    async (id: string): Promise<boolean> => {
      const pending = pendingDeletesRef.current;
      // A second delete for the same row (double-click, key repeat racing the
      // list update) is a no-op, not a queued duplicate.
      if (pending.has(id)) return false;

      const list = visibleItemsRef.current;
      const previousSelectedId = selectedIdRef.current;
      let migratedTo: string | null = null;
      pending.add(id);

      if (previousSelectedId === id) {
        // Migrate the selection BEFORE the delete lands, and commit it
        // synchronously: cmdk auto-selects the first row whenever the
        // currently-selected item unmounts, so the row being deleted must
        // already be unselected in the DOM by the time it unmounts. Without
        // flushSync, React can batch this state change into the same commit
        // as the list update (delete resolving fast), and cmdk's unmount
        // cleanup still sees the deleted row as selected → highlight jumps
        // to the top. Successor rule: the item that will occupy the same
        // position in the *rendered* list — with an active search this is
        // the next visible match, never a hidden item.
        // Successor = the row that will occupy this position once every
        // queued delete has landed, so the index has to be measured among
        // survivors rather than in the list as currently rendered.
        const index = list.findIndex((item) => item.id === id);
        const survivors = list.filter((item) => !pending.has(item.id));
        const survivorsAbove = list
          .slice(0, index)
          .filter((item) => !pending.has(item.id)).length;
        const target = survivors[survivorsAbove] ?? survivors[survivorsAbove - 1];
        const nextId = target ? target.id : "";
        migratedTo = nextId;
        flushSync(() => setSelectedId(nextId));
      }

      let didDelete = false;
      try {
        didDelete = await onDelete(id);
      } finally {
        pending.delete(id);
      }

      if (!didDelete && migratedTo !== null && selectedIdRef.current === migratedTo) {
        // The delete failed and the row is still there, so put the cursor back
        // on it — but only if nothing has moved the cursor since. Deletes are
        // queued now, so this can resolve long after the user pressed `d`
        // several more times; yanking the cursor backwards then would be worse
        // than leaving it where they put it.
        setSelectedId(previousSelectedId);
      }
      return didDelete;
    },
    [onDelete],
  );

  const handleDeleteFromRow = useCallback(
    (id: string) => {
      void handleDelete(id);
    },
    [handleDelete],
  );

  const handlePin = useCallback(
    (id: string, pinned: boolean) => onPin(id, pinned),
    [onPin],
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

      // `d` and `p` are deliberately NOT gated on isBusy: the actions hook
      // queues mutations instead of rejecting them, so holding `d` to clear a
      // run of entries lands every press. Gating them here is what used to eat
      // roughly three keystrokes in four.
      //
      // Enter and `u` stay gated. Paste hides the window, and undo re-inserts
      // rows — either one arriving in the middle of a burst of deletes is
      // disorienting rather than useful.
      if (isBusy && (e.key === "Enter" || e.key === "u")) {
        e.preventDefault();
        e.stopPropagation();
        return;
      }

      // ── Direct keyboard navigation (don't delegate to cmdk's Q()) ──
      //
      // We previously let cmdk handle Arrow/Home/End. Its Q() function walks
      // a live DOM queryAll to find the current item, and under some
      // combinations of disablePointerSelection + controlled value +
      // display:none search input, that DOM walk would land on the wrong
      // row. So navigation runs against the same `visibleItems` array the
      // list renders from, in BOTH modes; cmdk only syncs its highlight from
      // the controlled value. Home/End stay with the input caret in search
      // mode.
      const isArrow = e.key === "ArrowDown" || e.key === "ArrowUp";
      const isJump = (e.key === "Home" || e.key === "End") && mode === "navigate";
      if (isArrow || isJump) {
        e.preventDefault();
        e.stopPropagation();
        if (visibleItems.length === 0) {
          return;
        }
        const currentIdx = visibleItems.findIndex((item) => item.id === selectedId);
        let nextIdx: number;
        if (e.key === "Home") {
          nextIdx = 0;
        } else if (e.key === "End") {
          nextIdx = visibleItems.length - 1;
        } else if (e.key === "ArrowDown") {
          // Cmd+Down jumps to end (matches cmdk's Cmd+Down semantics)
          if (e.metaKey) {
            nextIdx = visibleItems.length - 1;
          } else if (currentIdx === -1) {
            nextIdx = 0;
          } else if (currentIdx === visibleItems.length - 1) {
            nextIdx = 0; // loop to top
          } else {
            nextIdx = currentIdx + 1;
          }
        } else {
          // ArrowUp
          if (e.metaKey) {
            nextIdx = 0;
          } else if (currentIdx === -1) {
            nextIdx = visibleItems.length - 1;
          } else if (currentIdx === 0) {
            nextIdx = visibleItems.length - 1; // loop to bottom
          } else {
            nextIdx = currentIdx - 1;
          }
        }
        const nextItem = visibleItems[nextIdx]!;
        setSelectedId(nextItem.id);
        // Scroll the row into view — cmdk normally does this via its own
        // selection path, but since we bypassed it we need to do it here.
        requestAnimationFrame(() => {
          const el = commandRef.current?.querySelector<HTMLElement>(
            `[cmdk-item][data-value="${CSS.escape(nextItem.id)}"]`,
          );
          el?.scrollIntoView({ block: "nearest" });
        });
        return;
      }

      if (mode === "navigate") {
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
          if (selectedId) void handleDelete(selectedId);
          return;
        }
        if (e.key === "p") {
          e.preventDefault();
          e.stopPropagation();
          const item = visibleItems.find((i) => i.id === selectedId);
          if (item) {
            void handlePin(item.id, !item.pinned);
          }
          return;
        }
        if (e.key === "e") {
          e.preventDefault();
          e.stopPropagation();
          const item = visibleItems.find((i) => i.id === selectedId);
          if (item && canExpandItem(item)) {
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
      handlePin,
      handleToggleExpand,
      isBusy,
      mode,
      onHide,
      onUndo,
      selectedId,
      visibleItems,
    ],
  );

  const { pinnedItems, recentItems } = useMemo(() => {
    const pinned: ClipItemType[] = [];
    const recent: ClipItemType[] = [];
    for (const item of visibleItems) {
      if (item.pinned) pinned.push(item);
      else recent.push(item);
    }
    return { pinnedItems: pinned, recentItems: recent };
  }, [visibleItems]);

  // Drag-and-drop reorder. onReorder is optional — when absent (e.g. unit
  // tests that don't wire reorder), drag handlers stay no-op and the grip
  // handle is hidden via the falsy section/handler check in ClipItem.
  // Disabled while searching: committing an order computed from a filtered
  // subset would scramble the full list.
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
  const reorderEnabled = Boolean(onReorder) && !isSearching;

  return (
    <Command
      ref={commandRef}
      tabIndex={-1}
      className="flex h-full flex-col bg-transparent p-0 outline-none"
      loop
      // Filtering and navigation are owned by this component (see
      // visibleItems); cmdk renders what it's given and syncs the highlight
      // from the controlled value.
      shouldFilter={false}
      // Keyboard is the source of truth for selection — disable cmdk's
      // pointer-move auto-select so the mouse cursor's accidental position
      // can't hijack the keyboard cursor (especially during the async window
      // right after a delete/pin, where the list re-flows under the cursor).
      // Click-to-paste still works (that's a separate handler).
      disablePointerSelection
      value={selectedId}
      // Not decorative — see handleCmdkValueChange: without a listener,
      // cmdk's self-initiated selection changes desync from React silently.
      onValueChange={handleCmdkValueChange}
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
        <SettingsDialog
          onClearAll={onClearAll}
          openRequestId={settingsRequestId}
          settingsApi={settingsApi}
        />
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
          {historyError && !search ? (
            <>
              <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-destructive/10 ring-[0.5px] ring-inset ring-destructive/20">
                <AlertTriangleIcon className="size-5 text-destructive" strokeWidth={1.5} />
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-[12px] font-medium text-foreground-muted">
                  History unavailable
                </span>
                <span className="max-w-[240px] break-words text-[10.5px] text-foreground-faint">
                  {historyError}
                </span>
              </div>
              <div className="flex items-center gap-2">
                {onRetryHistory && !confirmingReset && (
                  <button
                    type="button"
                    onClick={() => void onRetryHistory()}
                    className="flex h-6 items-center rounded-md bg-surface-soft px-2 text-[10.5px] font-medium text-foreground-muted ring-[0.5px] ring-inset ring-border-subtle transition-colors hover:bg-surface-hover hover:text-foreground"
                  >
                    Retry
                  </button>
                )}
                {onResetHistory &&
                  (confirmingReset ? (
                    <>
                      <span className="text-[10.5px] text-foreground-faint">
                        Erase stored history?
                      </span>
                      <button
                        type="button"
                        onClick={() => setConfirmingReset(false)}
                        className="flex h-6 items-center rounded-md px-2 text-[10.5px] font-medium text-foreground-muted transition-colors hover:bg-surface-hover"
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setConfirmingReset(false);
                          void onResetHistory();
                        }}
                        className="flex h-6 items-center rounded-md bg-destructive/10 px-2 text-[10.5px] font-medium text-destructive transition-colors hover:bg-destructive/20"
                      >
                        Reset
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      onClick={() => setConfirmingReset(true)}
                      className="flex h-6 items-center rounded-md px-2 text-[10.5px] font-medium text-destructive/80 transition-colors hover:bg-destructive/10 hover:text-destructive"
                    >
                      Reset history…
                    </button>
                  ))}
              </div>
            </>
          ) : (
            <>
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
            </>
          )}
        </CommandEmpty>

        {pinnedItems.length > 0 && (
          <CommandGroup heading="Pinned">
            {pinnedItems.map((item, index) => (
              <ClipItem
                key={item.id}
                item={item}
                index={index}
                onSelect={handleSelect}
                onDelete={handleDeleteFromRow}
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
              onDelete={handleDeleteFromRow}
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
