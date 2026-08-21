import { memo, useCallback, useMemo } from "react";
import { CommandItem } from "@/components/ui/command";
import type { ClipItem as ClipItemType } from "@/types/clipboard";
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
import { canExpandItem } from "@/lib/clip";
import { detectContentTag, extractColorValue } from "@/lib/contentDetection";
import { formatRelativeTime } from "@/lib/time";
import { renderHighlightedText } from "@/lib/highlight";
import type { DragSection, DropPosition } from "@/hooks/useDragReorder";

interface ClipItemProps {
  item: ClipItemType;
  index: number;
  onSelect: (item: ClipItemType) => void;
  onDelete: (id: string) => void;
  onPin: (id: string, pinned: boolean) => Promise<boolean>;
  isExpanded: boolean;
  onToggleExpand: (id: string) => void;
  /** Search query — when non-empty, matched characters are highlighted in preview. */
  searchQuery?: string;
  /** Drag-and-drop wiring (optional). */
  section?: DragSection;
  isDragging?: boolean;
  isAnyDragging?: boolean;
  dropPosition?: DropPosition | null;
  onItemDragStart?: (e: React.DragEvent, item: ClipItemType, fromSection: DragSection) => void;
  onItemDragOver?: (e: React.DragEvent, item: ClipItemType, section: DragSection) => void;
  onItemDragLeave?: (e: React.DragEvent) => void;
  onItemDrop?: (e: React.DragEvent) => void;
  onItemDragEnd?: () => void;
}

// Memoized: the panel re-renders on every arrow key and search keystroke,
// and without this every row re-ran content detection (regexes + JSON.parse
// over the full content) and rebuilt image data-URLs each time.
export const ClipItem = memo(function ClipItem({
  item,
  index,
  onSelect,
  onDelete,
  onPin,
  isExpanded,
  onToggleExpand,
  searchQuery,
  section,
  isDragging = false,
  isAnyDragging = false,
  dropPosition = null,
  onItemDragStart,
  onItemDragOver,
  onItemDragLeave,
  onItemDrop,
  onItemDragEnd,
}: ClipItemProps): React.ReactElement {
  const isImage = item.clipType === "image";
  const contentTag = useMemo(
    () => (isImage ? null : detectContentTag(item.content)),
    [isImage, item.content],
  );
  const imageSrc = useMemo(
    () =>
      isImage && item.content
        ? `data:image/${item.imageFormat ?? "png"};base64,${item.content}`
        : null,
    [isImage, item.content, item.imageFormat],
  );
  const relativeTime = formatRelativeTime(item.timestamp);

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

  const canExpand = canExpandItem(item);

  const dragEnabled = section !== undefined && onItemDragStart !== undefined;

  const handleDragStart = useCallback(
    (e: React.DragEvent) => {
      if (!dragEnabled || !section) return;
      onItemDragStart?.(e, item, section);
    },
    [dragEnabled, item, onItemDragStart, section],
  );

  const handleDragOver = useCallback(
    (e: React.DragEvent) => {
      if (!dragEnabled || !section) return;
      onItemDragOver?.(e, item, section);
    },
    [dragEnabled, item, onItemDragOver, section],
  );

  return (
    <CommandItem
      // Selection identity is the stable, whitespace-free id — never derived
      // from content, so cmdk's value normalization can't desync it from
      // React state. Search filtering happens in the panel, not in cmdk.
      value={item.id}
      onSelect={() => onSelect(item)}
      // items-stretch overrides cmdk's default items-center so children fill full width.
      // [&>svg:last-child]:hidden hides the CheckIcon auto-appended by CommandItem.
      //
      // Whole-row drag: HTML5 DnD only fires dragstart on actual mouse
      // movement past the OS-level drag threshold, so a regular click still
      // triggers onClick (cmdk's onSelect → paste). No invisible 10px handle
      // needed — discoverable + reliable.
      data-drag-over={dropPosition ?? undefined}
      data-drag-self={isDragging || undefined}
      data-drag-active={isAnyDragging || undefined}
      draggable={dragEnabled || undefined}
      onDragStart={dragEnabled ? handleDragStart : undefined}
      onDragOver={dragEnabled ? handleDragOver : undefined}
      onDragLeave={dragEnabled ? onItemDragLeave : undefined}
      onDrop={dragEnabled ? onItemDrop : undefined}
      onDragEnd={dragEnabled ? onItemDragEnd : undefined}
      className="clip-item group/clip relative flex flex-col items-stretch rounded-md [&>svg:last-child]:hidden"
      style={{
        paddingLeft: "var(--px-row)",
        paddingRight: "var(--px-row)",
        paddingTop: "4px",
        paddingBottom: "4px",
        animation: "swilclip-item-in 160ms var(--ease-spring) both",
        animationDelay: `${Math.min(index, 8) * 14}ms`,
      }}
    >
      <div className="selected-bar" />

      {/* Main row */}
      <div className="flex w-full items-center gap-2">
        {/* Type chip — compact, ~20px to keep rows dense */}
        {isImage ? (
          <div className="clip-icon relative flex h-5 w-5 shrink-0 items-center justify-center overflow-hidden rounded-[5px] bg-surface-soft ring-[0.5px] ring-inset ring-border-subtle">
            {imageSrc ? (
              <img
                src={imageSrc}
                alt="clipboard image"
                className="h-full w-full object-cover"
                draggable={false}
              />
            ) : (
              <ImageIcon className="size-3 text-foreground-muted" />
            )}
          </div>
        ) : contentTag === "color" ? (
          <div className="clip-icon flex h-5 w-5 shrink-0 items-center justify-center rounded-[5px] bg-surface-soft transition-colors duration-100">
            <span
              className="block h-3 w-3 rounded-[2px] shadow-[inset_0_0_0_0.5px_rgba(255,255,255,0.18)]"
              style={{ backgroundColor: extractColorValue(item.content) }}
              aria-label={`Color ${item.content.trim()}`}
            />
          </div>
        ) : (
          <div className="clip-icon flex h-5 w-5 shrink-0 items-center justify-center rounded-[5px] bg-surface-soft text-foreground-muted transition-colors duration-100">
            {contentTag === "url" && <LinkIcon className="size-3" />}
            {contentTag === "email" && <MailIcon className="size-3" />}
            {contentTag === "json" && <BracketsIcon className="size-3" />}
            {contentTag === "code" && <CodeIcon className="size-3" />}
            {contentTag === "multiline" && <AlignLeftIcon className="size-3" />}
            {contentTag === "text" && <FileTextIcon className="size-3" />}
          </div>
        )}

        {/* Text — min-w-0 required for truncate to work inside flex */}
        <div className="flex min-w-0 flex-1 flex-col">
          <span className="clip-preview truncate text-[11.5px] leading-[1.3] text-foreground/85 transition-colors duration-100">
            {searchQuery ? renderHighlightedText(item.preview, searchQuery) : item.preview}
          </span>
          {isImage && item.imageWidth && item.imageHeight && (
            <span className="text-[9px] leading-tight text-foreground-subtle tabular-nums">
              {item.imageWidth}×{item.imageHeight} {item.imageFormat?.toUpperCase()}
            </span>
          )}
        </div>

        {/* Right cluster: action buttons (hover/selected) OR meta (rest state).
         *
         * min-width is sized for the WIDER of the two states — the action
         * overlay (3 × 20px buttons + gaps). The static meta is now narrower
         * than that, so the reserve is what keeps the timestamp from shifting
         * horizontally when a row is selected. */}
        <div className="relative flex shrink-0 items-center justify-end" style={{ minWidth: "66px" }}>
          {/* Static meta — timestamp + pin badge. Fades out on hover/select */}
          <div className="clip-meta-static flex items-center gap-1 transition-opacity duration-100">
            {item.pinned && (
              <PinIcon
                className="size-2.5 fill-accent text-accent"
                aria-label="Pinned"
              />
            )}
            <span className="clip-meta text-[9.5px] tabular-nums text-foreground-faint">
              {relativeTime}
            </span>
          </div>

          {/* Action buttons — overlay; visible only on hover or when selected */}
          <div className="clip-actions absolute inset-y-0 right-0 flex items-center gap-px opacity-0 transition-opacity duration-100">
            <button
              type="button"
              onClick={handlePin}
              onMouseDown={(e) => e.preventDefault()}
              draggable={false}
              onDragStart={(e) => e.preventDefault()}
              className={[
                "flex h-5 w-5 items-center justify-center rounded-[5px] transition-colors hover:bg-surface-hover",
                item.pinned ? "text-accent" : "text-foreground-muted hover:text-foreground",
              ].join(" ")}
              aria-label={item.pinned ? "Unpin item" : "Pin item"}
              title={item.pinned ? "Unpin" : "Pin"}
            >
              <PinIcon className={["size-2.5", item.pinned ? "fill-accent" : ""].join(" ")} />
            </button>

            {canExpand && (
              <button
                type="button"
                onClick={handleToggleExpand}
                onMouseDown={(e) => e.preventDefault()}
              draggable={false}
              onDragStart={(e) => e.preventDefault()}
                className="flex h-5 w-5 items-center justify-center rounded-[5px] text-foreground-muted transition-colors hover:bg-surface-hover hover:text-foreground"
                aria-label={isExpanded ? "Collapse preview" : "Expand preview"}
                title={isExpanded ? "Collapse" : "Expand"}
              >
                {isExpanded ? (
                  <ChevronUpIcon className="size-2.5" />
                ) : (
                  <ChevronDownIcon className="size-2.5" />
                )}
              </button>
            )}

            <button
              type="button"
              onClick={handleDelete}
              onMouseDown={(e) => e.preventDefault()}
              draggable={false}
              onDragStart={(e) => e.preventDefault()}
              className="flex h-5 w-5 items-center justify-center rounded-[5px] text-foreground-muted transition-colors hover:bg-destructive/15 hover:text-destructive"
              aria-label="Delete item"
              title="Delete"
            >
              <XIcon className="size-2.5" />
            </button>
          </div>
        </div>
      </div>

      {isExpanded && canExpand && (
        <pre className="mt-1.5 max-h-[140px] overflow-y-auto whitespace-pre-wrap break-all rounded-md bg-surface-sunk px-2 py-1.5 font-mono text-[10.5px] leading-snug text-foreground-muted ring-[0.5px] ring-inset ring-border-subtle">
          {item.content}
        </pre>
      )}
    </CommandItem>
  );
});
