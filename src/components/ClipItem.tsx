import { useCallback } from "react";
import { CommandItem, CommandShortcut } from "@/components/ui/command";
import type { ClipItem as ClipItemType } from "@/types/clipboard";
import { QUICK_PASTE_LIMIT } from "@/constants";
import {
  FileTextIcon,
  ImageIcon,
  XIcon,
  LinkIcon,
  MailIcon,
  CodeIcon,
  AlignLeftIcon,
  BracketsIcon,
  ChevronDownIcon,
  ChevronUpIcon,
  PinIcon,
} from "lucide-react";
import { detectContentTag, extractColorValue } from "@/lib/contentDetection";

interface ClipItemProps {
  item: ClipItemType;
  index: number;
  onSelect: (item: ClipItemType) => void;
  onDelete: (id: string) => void;
  onPin: (id: string, pinned: boolean) => Promise<void>;
  isExpanded: boolean;
  onToggleExpand: (id: string) => void;
}

export function ClipItem({
  item,
  index,
  onSelect,
  onDelete,
  onPin,
  isExpanded,
  onToggleExpand,
}: ClipItemProps): React.ReactElement {
  const shortcutIndex = index + 1;
  const hasShortcut = shortcutIndex <= QUICK_PASTE_LIMIT;
  const isImage = item.clipType === "image";
  const contentTag = isImage ? null : detectContentTag(item.content);

  const handleDelete = useCallback(
    (event: React.MouseEvent) => {
      event.stopPropagation();
      event.preventDefault();
      onDelete(item.id);
    },
    [item.id, onDelete],
  );

  const handleToggleExpand = useCallback(
    (event: React.MouseEvent) => {
      event.stopPropagation();
      event.preventDefault();
      onToggleExpand(item.id);
    },
    [item.id, onToggleExpand],
  );

  const handlePin = useCallback(
    (event: React.MouseEvent) => {
      event.stopPropagation();
      event.preventDefault();
      void onPin(item.id, !item.pinned);
    },
    [item.id, item.pinned, onPin],
  );

  const canExpand =
    !isImage && item.content.length > item.preview.length;

  return (
    <CommandItem
      value={`${item.id}-${item.preview}`}
      onSelect={() => onSelect(item)}
      // items-stretch overrides cmdk's default items-center so children fill full width.
      // [&>svg:last-child]:hidden hides the CheckIcon auto-appended by CommandItem.
      className="clip-item group/clip relative flex flex-col items-stretch rounded-lg px-2.5 py-1.5 transition-all duration-100 [&>svg:last-child]:hidden"
      style={{
        animation: "swilclip-item-in 150ms ease-out both",
        animationDelay: `${Math.min(index, 8) * 15}ms`,
      }}
    >
      <div className="selected-bar absolute left-0 top-1/2 h-[60%] w-[3px] -translate-y-1/2 rounded-r-full bg-accent opacity-0 transition-opacity duration-100" />

      {/* Main row — w-full so truncation works correctly */}
      <div className="flex w-full items-center gap-2">
        {isImage ? (
          <div className="relative flex h-7 w-7 shrink-0 items-center justify-center overflow-hidden rounded-md bg-muted/50">
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
        ) : contentTag === "color" ? (
          <div className="clip-icon flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-muted/40 transition-colors duration-100">
            <span
              className="block h-3 w-3 rounded-sm border border-white/10"
              style={{ backgroundColor: extractColorValue(item.content) }}
            />
          </div>
        ) : (
          <div className="clip-icon flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-muted/40 transition-colors duration-100">
            {contentTag === "url" && <LinkIcon className="size-3 text-accent" />}
            {contentTag === "email" && <MailIcon className="size-3 text-foreground-muted" />}
            {contentTag === "json" && <BracketsIcon className="size-3 text-foreground-muted" />}
            {contentTag === "code" && <CodeIcon className="size-3 text-foreground-muted" />}
            {contentTag === "multiline" && <AlignLeftIcon className="size-3 text-foreground-muted" />}
            {contentTag === "text" && <FileTextIcon className="size-3 text-foreground-muted" />}
          </div>
        )}

        {/* Text — min-w-0 required for truncate to work inside flex */}
        <div className="flex min-w-0 flex-1 flex-col">
          <span className="truncate text-[13px] leading-tight text-foreground/80 transition-colors duration-100">
            {item.preview}
          </span>
          {isImage && item.imageWidth && item.imageHeight && (
            <span className="text-[10px] leading-tight text-foreground-subtle">
              {item.imageWidth}×{item.imageHeight} {item.imageFormat?.toUpperCase()}
            </span>
          )}
        </div>

        {/* Action buttons — only visible on hover, grouped tightly */}
        <div className="delete-btn flex shrink-0 items-center gap-0.5 opacity-0 transition-all duration-100">
          {/* Pin — always visible when pinned so user can see the state */}
          <button
            type="button"
            onClick={handlePin}
            onMouseDown={(e) => e.preventDefault()}
            className={[
              "flex h-5 w-5 items-center justify-center rounded transition-colors hover:bg-muted/60",
              item.pinned ? "text-accent" : "text-foreground-muted",
            ].join(" ")}
            aria-label={item.pinned ? "Unpin item" : "Pin item"}
          >
            <PinIcon className={["size-3", item.pinned ? "fill-accent" : ""].join(" ")} />
          </button>

          {canExpand && (
            <button
              type="button"
              onClick={handleToggleExpand}
              onMouseDown={(e) => e.preventDefault()}
              className="flex h-5 w-5 items-center justify-center rounded text-foreground-muted transition-colors hover:bg-muted/60"
              aria-label={isExpanded ? "Collapse preview" : "Expand preview"}
            >
              {isExpanded
                ? <ChevronUpIcon className="size-3" />
                : <ChevronDownIcon className="size-3" />
              }
            </button>
          )}

          <button
            type="button"
            onClick={handleDelete}
            onMouseDown={(e) => e.preventDefault()}
            className="flex h-5 w-5 items-center justify-center rounded text-foreground-muted transition-colors hover:bg-destructive/20 hover:text-destructive"
            aria-label="Delete item"
          >
            <XIcon className="size-3" />
          </button>
        </div>

        {/* Shortcut badge — hidden when action buttons are shown on hover */}
        {hasShortcut && (
          <CommandShortcut className="shortcut-badge flex shrink-0 items-center gap-0.5 text-[10px] font-medium tracking-wider text-foreground-subtle/50 transition-all duration-100">
            <kbd className="font-sans">⌥</kbd>
            <kbd className="font-mono">{shortcutIndex}</kbd>
          </CommandShortcut>
        )}
      </div>

      {isExpanded && canExpand && (
        <pre className="mt-1.5 max-h-[120px] overflow-y-auto whitespace-pre-wrap break-all rounded-md bg-surface/60 p-2 font-mono text-[11px] leading-relaxed text-foreground-muted">
          {item.content}
        </pre>
      )}
    </CommandItem>
  );
}
