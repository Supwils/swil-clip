import { useCallback } from "react";
import { CommandItem, CommandShortcut } from "@/components/ui/command";
import type { ClipItem as ClipItemType } from "@/types/clipboard";
import { QUICK_PASTE_LIMIT } from "@/constants";
import { FileTextIcon, ImageIcon, XIcon } from "lucide-react";

interface ClipItemProps {
  item: ClipItemType;
  index: number;
  onSelect: (item: ClipItemType) => void;
  onDelete: (id: string) => void;
}

export function ClipItem({
  item,
  index,
  onSelect,
  onDelete,
}: ClipItemProps): React.ReactElement {
  const shortcutIndex = index + 1;
  const hasShortcut = shortcutIndex <= QUICK_PASTE_LIMIT;
  const isImage = item.clipType === "image";

  const handleDelete = useCallback(
    (event: React.MouseEvent) => {
      event.stopPropagation();
      event.preventDefault();
      onDelete(item.id);
    },
    [item.id, onDelete],
  );

  return (
    <CommandItem
      value={`${item.id}-${item.preview}`}
      onSelect={() => onSelect(item)}
      className="clip-item group/clip relative flex items-center gap-2.5 rounded-lg px-2.5 py-2 transition-all duration-100"
    >
      <div className="selected-bar absolute left-0 top-1/2 h-[60%] w-[3px] -translate-y-1/2 rounded-r-full bg-accent opacity-0 transition-opacity duration-100" />

      {isImage ? (
        <div className="relative flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-md bg-muted/50">
          {item.content ? (
            <img
              src={`data:image/${item.imageFormat ?? "png"};base64,${item.content}`}
              alt="clipboard image"
              className="h-full w-full object-cover"
            />
          ) : (
            <ImageIcon className="size-3.5 text-foreground-muted" />
          )}
        </div>
      ) : (
        <div className="clip-icon flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-muted/40 transition-colors duration-100">
          <FileTextIcon className="size-3 text-foreground-muted" />
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        <span className="truncate text-[13px] leading-tight text-foreground/80 transition-colors duration-100">
          {item.preview}
        </span>
        {isImage && item.imageWidth && item.imageHeight && (
          <span className="text-[10px] leading-tight text-foreground-subtle">
            {item.imageWidth}x{item.imageHeight} {item.imageFormat?.toUpperCase()}
          </span>
        )}
      </div>

      <button
        type="button"
        onClick={handleDelete}
        onMouseDown={(e) => e.preventDefault()}
        className="delete-btn flex h-5 w-5 shrink-0 items-center justify-center rounded-md opacity-0 transition-all duration-100 hover:bg-destructive/20 hover:text-destructive"
        aria-label="Delete item"
      >
        <XIcon className="size-3" />
      </button>

      {hasShortcut && (
        <CommandShortcut className="shortcut-badge flex items-center gap-0.5 text-[10px] font-medium tracking-wider text-foreground-subtle/50 transition-all duration-100">
          <kbd className="font-sans">⌥</kbd>
          <kbd className="font-mono">{shortcutIndex}</kbd>
        </CommandShortcut>
      )}
    </CommandItem>
  );
}
