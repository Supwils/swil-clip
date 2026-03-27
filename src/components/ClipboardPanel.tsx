import { useCallback } from "react";
import {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
} from "@/components/ui/command";
import { ClipItem } from "@/components/ClipItem";
import type { ClipItem as ClipItemType } from "@/types/clipboard";

interface ClipboardPanelProps {
  items: ClipItemType[];
  onPaste: (item: ClipItemType) => void;
  onDelete: (id: string) => void;
}

export function ClipboardPanel({
  items,
  onPaste,
  onDelete,
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

  return (
    <Command
      className="flex h-full flex-col bg-transparent"
      loop
    >
      <CommandInput placeholder="Search clipboard..." autoFocus />

      <CommandList className="max-h-none flex-1 overflow-y-auto py-1">
        <CommandEmpty className="flex flex-col items-center justify-center gap-2 py-12 text-foreground-subtle">
          <span className="text-2xl opacity-40">📋</span>
          <span className="text-xs">No clipboard history</span>
        </CommandEmpty>

        <CommandGroup>
          {items.map((item, index) => (
            <ClipItem
              key={item.id}
              item={item}
              index={index}
              onSelect={handleSelect}
              onDelete={handleDelete}
            />
          ))}
        </CommandGroup>
      </CommandList>
    </Command>
  );
}
