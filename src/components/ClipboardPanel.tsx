import { useCallback, useEffect, useRef, useState } from "react";
import { ClipboardIcon } from "lucide-react";
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
import type { ClipItem as ClipItemType } from "@/types/clipboard";

type PanelMode = "navigate" | "search";

interface ClipboardPanelProps {
  items: ClipItemType[];
  onPaste: (item: ClipItemType) => void;
  onDelete: (id: string) => void;
  onClearAll: () => Promise<void>;
  onPin: (id: string, pinned: boolean) => Promise<void>;
  onHide: () => void;
}

function findItemByValue(
  items: ClipItemType[],
  cmdkValue: string,
): ClipItemType | undefined {
  return items.find((item) => cmdkValue === `${item.id}-${item.preview}`);
}

export function ClipboardPanel({
  items,
  onPaste,
  onDelete,
  onClearAll,
  onPin,
  onHide,
}: ClipboardPanelProps): React.ReactElement {
  const [mode, setMode] = useState<PanelMode>("navigate");
  const [search, setSearch] = useState("");
  const [selectedValue, setSelectedValue] = useState("");
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  const commandRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Focus the command root on mount for arrow key navigation
  useEffect(() => {
    commandRef.current?.focus();
  }, []);

  const handleSelect = useCallback(
    (item: ClipItemType) => {
      onPaste(item);
    },
    [onPaste],
  );

  const handleDelete = useCallback(
    (id: string) => {
      onDelete(id);
    },
    [onDelete],
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
          const idx = items.findIndex(
            (it) => selectedValue === `${it.id}-${it.preview}`,
          );
          if (idx === -1) return;
          // Pre-set selection to the nearest neighbor before deleting
          const neighbor = items[idx + 1] ?? items[idx - 1];
          setSelectedValue(
            neighbor ? `${neighbor.id}-${neighbor.preview}` : "",
          );
          onDelete(items[idx]!.id);
          return;
        }
        if (e.key === "p") {
          e.preventDefault();
          e.stopPropagation();
          const item = findItemByValue(items, selectedValue);
          if (item) void onPin(item.id, !item.pinned);
          return;
        }
        if (e.key === "e") {
          e.preventDefault();
          e.stopPropagation();
          const item = findItemByValue(items, selectedValue);
          if (item && item.clipType !== "image" && item.content.length > item.preview.length) {
            handleToggleExpand(item.id);
          }
          return;
        }
        if (e.key === "Escape") {
          e.preventDefault();
          onHide();
          return;
        }
        // Block printable chars from reaching cmdk input in navigate mode
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
    [mode, selectedValue, items, onDelete, onPin, onHide, handleToggleExpand],
  );

  const pinnedItems = items.filter((item) => item.pinned);
  const recentItems = items.filter((item) => !item.pinned);

  return (
    <Command
      ref={commandRef}
      tabIndex={-1}
      className="flex h-full flex-col bg-transparent outline-none"
      loop
      value={selectedValue}
      onValueChange={setSelectedValue}
      onKeyDown={handleKeyDown}
    >
      <div
        className="panel-drag-region"
        data-tauri-drag-region
        style={{ height: PANEL_DRAG_REGION_HEIGHT_PX }}
        aria-label="Drag to move window"
      />

      <div className="flex items-center justify-between px-2 pt-2 pb-0.5">
        <span className="text-xs font-medium text-foreground-subtle opacity-60">Clipboard</span>
        <SettingsDialog onClearAll={onClearAll} />
      </div>

      <div
        className={[
          "search-input-wrapper transition-all duration-150 ease-out",
          mode === "search"
            ? "max-h-12 opacity-100"
            : "max-h-0 overflow-hidden opacity-0",
        ].join(" ")}
      >
        <CommandInput
          ref={inputRef}
          placeholder="Search clipboard..."
          value={search}
          onValueChange={setSearch}
        />
      </div>

      <CommandList className="max-h-none flex-1 overflow-y-auto py-1">
        <CommandEmpty className="flex flex-col items-center justify-center gap-2 py-12 text-foreground-subtle">
          <ClipboardIcon className="size-8 opacity-20" />
          <span className="text-xs font-medium opacity-60">No clipboard history</span>
          <span className="text-[11px] opacity-40">Copy something to get started</span>
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
                onPin={onPin}
                isExpanded={expandedIds.has(item.id)}
                onToggleExpand={handleToggleExpand}
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
              onPin={onPin}
              isExpanded={expandedIds.has(item.id)}
              onToggleExpand={handleToggleExpand}
            />
          ))}
        </CommandGroup>
      </CommandList>

      {/* Hint bar */}
      <div className="flex items-center gap-3 border-t border-border/20 px-3 py-1.5 text-[10px] text-foreground-subtle/50">
        {mode === "navigate" ? (
          <>
            <span><kbd className="font-mono">↑↓</kbd> Navigate</span>
            <span><kbd className="font-mono">⏎</kbd> Paste</span>
            <span><kbd className="font-mono">d</kbd> Delete</span>
            <span><kbd className="font-mono">p</kbd> Pin</span>
            <span><kbd className="font-mono">e</kbd> Expand</span>
            <span><kbd className="font-mono">s</kbd> Search</span>
            <span><kbd className="font-mono">esc</kbd> Close</span>
          </>
        ) : (
          <>
            <span><kbd className="font-mono">esc</kbd> Back</span>
            <span><kbd className="font-mono">⏎</kbd> Paste</span>
            <span><kbd className="font-mono">↑↓</kbd> Navigate</span>
          </>
        )}
      </div>
    </Command>
  );
}
