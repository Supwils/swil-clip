import { useCallback, useMemo, useRef, useState } from "react";
import type { ClipItem } from "@/types/clipboard";

export type DragSection = "pinned" | "recent";
export type DropPosition = "before" | "after";

interface DragState {
  itemId: string;
  fromSection: DragSection;
  overItemId: string | null;
  overSection: DragSection | null;
  position: DropPosition;
}

interface DragHandlers {
  onDragStart: (e: React.DragEvent, item: ClipItem, fromSection: DragSection) => void;
  onItemDragOver: (e: React.DragEvent, overItem: ClipItem, overSection: DragSection) => void;
  onItemDragLeave: (e: React.DragEvent) => void;
  onItemDrop: (e: React.DragEvent) => void;
  onDragEnd: () => void;
}

interface UseDragReorderReturn extends DragHandlers {
  drag: DragState | null;
  /** True while any drag is in flight — useful for dimming non-target rows. */
  isDragging: boolean;
}

interface UseDragReorderParams {
  pinned: ClipItem[];
  recent: ClipItem[];
  onCommit: (orderedIds: string[], pinnedIds: string[]) => Promise<boolean>;
}

const DRAG_MIME = "application/x-swilclip-id";

/**
 * Compute the new ordered + pinned arrays produced by dropping `draggedId` at
 * `(overItemId, position)` inside `(overSection)`. Returns null if the drop
 * would be a no-op (drop onto self, or position unchanged).
 *
 * Cross-section drops auto-toggle the pinned flag: drop into Pinned → pinned,
 * drop into Recent → unpinned. Within-section drops only reorder.
 */
export function computeReorder(
  pinned: ClipItem[],
  recent: ClipItem[],
  draggedId: string,
  overItemId: string | null,
  overSection: DragSection,
  position: DropPosition,
): { orderedIds: string[]; pinnedIds: string[] } | null {
  // Drop onto self → always a no-op. Avoids the strip-and-reinsert path
  // landing the item at the tail because the anchor is gone post-strip.
  if (overItemId === draggedId) return null;

  // Strip the dragged item from both lists; we'll splice it back into the
  // target section at the computed index.
  const stripped = (items: ClipItem[]) => items.filter((i) => i.id !== draggedId);

  let nextPinned = stripped(pinned).map((i) => i.id);
  let nextRecent = stripped(recent).map((i) => i.id);
  const targetList = overSection === "pinned" ? nextPinned : nextRecent;

  // Find insertion index relative to overItemId (or list-end if null).
  let insertAt: number;
  if (overItemId === null) {
    insertAt = targetList.length;
  } else {
    const idx = targetList.indexOf(overItemId);
    if (idx === -1) {
      // overItem belongs to the *other* section (or was the dragged item),
      // fall back to the section's tail.
      insertAt = targetList.length;
    } else {
      insertAt = position === "before" ? idx : idx + 1;
    }
  }

  if (overSection === "pinned") {
    nextPinned = [...nextPinned.slice(0, insertAt), draggedId, ...nextPinned.slice(insertAt)];
  } else {
    nextRecent = [...nextRecent.slice(0, insertAt), draggedId, ...nextRecent.slice(insertAt)];
  }

  const orderedIds = [...nextPinned, ...nextRecent];
  const pinnedIds = nextPinned.slice();

  // No-op detection: if the resulting order equals the original AND the pin
  // set is unchanged, don't bother round-tripping to the backend.
  const originalOrder = [...pinned.map((i) => i.id), ...recent.map((i) => i.id)];
  const originalPinned = pinned.map((i) => i.id);
  const orderSame =
    orderedIds.length === originalOrder.length &&
    orderedIds.every((id, i) => id === originalOrder[i]);
  const pinsSame =
    pinnedIds.length === originalPinned.length &&
    pinnedIds.every((id, i) => id === originalPinned[i]);
  if (orderSame && pinsSame) return null;

  return { orderedIds, pinnedIds };
}

export function useDragReorder({
  pinned,
  recent,
  onCommit,
}: UseDragReorderParams): UseDragReorderReturn {
  const [drag, setDrag] = useState<DragState | null>(null);
  // Use refs for the latest snapshots so the handlers can read fresh data
  // without forcing the handler identities to change every render.
  const pinnedRef = useRef(pinned);
  const recentRef = useRef(recent);
  pinnedRef.current = pinned;
  recentRef.current = recent;
  const dragRef = useRef<DragState | null>(null);
  dragRef.current = drag;

  const onDragStart = useCallback(
    (e: React.DragEvent, item: ClipItem, fromSection: DragSection) => {
      e.dataTransfer.effectAllowed = "move";
      // setData is required on Firefox to actually start the drag.
      try {
        e.dataTransfer.setData(DRAG_MIME, item.id);
      } catch {
        /* Safari is fine without it */
      }
      setDrag({
        itemId: item.id,
        fromSection,
        overItemId: null,
        overSection: null,
        position: "before",
      });
    },
    [],
  );

  const onItemDragOver = useCallback(
    (e: React.DragEvent, overItem: ClipItem, overSection: DragSection) => {
      if (!dragRef.current) return;
      // preventDefault is REQUIRED on dragover for the drop event to fire.
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";

      const rect = e.currentTarget.getBoundingClientRect();
      const isAbove = e.clientY < rect.top + rect.height / 2;
      const nextPosition: DropPosition = isAbove ? "before" : "after";

      const current = dragRef.current;
      if (
        current.overItemId === overItem.id &&
        current.overSection === overSection &&
        current.position === nextPosition
      ) {
        return; // unchanged — avoid re-rendering on every mousemove
      }

      setDrag({
        ...current,
        overItemId: overItem.id,
        overSection,
        position: nextPosition,
      });
    },
    [],
  );

  const onItemDragLeave = useCallback((_e: React.DragEvent) => {
    // No-op: we let the next onItemDragOver replace the target. Clearing here
    // causes flicker because every nested element fires dragleave during entry.
  }, []);

  const onItemDrop = useCallback(
    (e: React.DragEvent) => {
      if (!dragRef.current) return;
      e.preventDefault();

      const current = dragRef.current;
      const result = computeReorder(
        pinnedRef.current,
        recentRef.current,
        current.itemId,
        current.overItemId,
        current.overSection ?? current.fromSection,
        current.position,
      );

      setDrag(null);
      if (result) {
        void onCommit(result.orderedIds, result.pinnedIds);
      }
    },
    [onCommit],
  );

  const onDragEnd = useCallback(() => {
    setDrag(null);
  }, []);

  const isDragging = drag !== null;

  return useMemo(
    () => ({
      drag,
      isDragging,
      onDragStart,
      onItemDragOver,
      onItemDragLeave,
      onItemDrop,
      onDragEnd,
    }),
    [drag, isDragging, onDragStart, onItemDragOver, onItemDragLeave, onItemDrop, onDragEnd],
  );
}
