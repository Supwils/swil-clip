import { useCallback, useRef, useState } from "react";
import type { ClipItem } from "@/types/clipboard";
import { MAX_UNDO_BYTES, MAX_UNDO_OPERATIONS } from "@/constants";

/**
 * Approximate in-memory cost of a batch. Content dominates every other field
 * by orders of magnitude (base64 images), so it is the only term that matters.
 */
function batchBytes(items: ClipItem[]): number {
  let total = 0;
  for (const item of items) total += item.content.length;
  return total;
}

/**
 * Drop the oldest batches until the stack fits the budget. A single batch that
 * exceeds the budget on its own is still kept: undo is the user's only recovery
 * path, and silently discarding the newest deletion is the failure mode this
 * whole hook exists to prevent.
 */
function trimToBudget(stack: ClipItem[][]): ClipItem[][] {
  const trimmed = stack.slice(0, MAX_UNDO_OPERATIONS);
  let total = trimmed.reduce((sum, batch) => sum + batchBytes(batch), 0);
  while (trimmed.length > 1 && total > MAX_UNDO_BYTES) {
    const evicted = trimmed.pop();
    if (!evicted) break;
    total -= batchBytes(evicted);
  }
  return trimmed;
}

interface UseUndoStackReturn {
  canUndo: boolean;
  pushUndo: (items: ClipItem[]) => void;
  popUndo: () => ClipItem[] | undefined;
}

export function useUndoStack(): UseUndoStackReturn {
  const stackRef = useRef<ClipItem[][]>([]);
  const [canUndo, setCanUndo] = useState(false);

  const pushUndo = useCallback((items: ClipItem[]) => {
    if (items.length === 0) return;
    stackRef.current = trimToBudget([items, ...stackRef.current]);
    setCanUndo(stackRef.current.length > 0);
  }, []);

  const popUndo = useCallback((): ClipItem[] | undefined => {
    const [top, ...rest] = stackRef.current;
    if (!top) return undefined;
    stackRef.current = rest;
    setCanUndo(rest.length > 0);
    return top;
  }, []);

  return { canUndo, pushUndo, popUndo };
}
