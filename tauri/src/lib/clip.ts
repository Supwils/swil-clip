import type { ClipItem } from "@/types/clipboard";

/**
 * Whether the expanded view has anything more to show than the preview row.
 * Single source for both the chevron button (ClipItem) and the `e` shortcut
 * (ClipboardPanel), so keyboard and mouse can never disagree.
 */
export function canExpandItem(item: ClipItem): boolean {
  return item.clipType !== "image" && item.content.length > item.preview.length;
}
