import { useCallback, useState } from "react";
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

interface ClipboardPanelProps {
  items: ClipItemType[];
  onPaste: (item: ClipItemType) => void;
  onDelete: (id: string) => void;
  onClearAll: () => Promise<void>;
  onPin: (id: string, pinned: boolean) => Promise<void>;
}

export function ClipboardPanel({
  items,
  onPaste,
  onDelete,
  onClearAll,
  onPin,
}: ClipboardPanelProps): React.ReactElement {
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

  const pinnedItems = items.filter((item) => item.pinned);
  const recentItems = items.filter((item) => !item.pinned);

  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

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

  return (
    <Command
      className="flex h-full flex-col bg-transparent"
      loop
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

      <CommandInput placeholder="Search clipboard..." autoFocus />

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
    </Command>
  );
}
