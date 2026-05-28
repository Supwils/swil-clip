import { useCallback, useRef, useState } from "react";
import type { ClipItem } from "@/types/clipboard";
import { MAX_UNDO_OPERATIONS } from "@/constants";

/** Strip heavy base64 content from image items to avoid ballooning memory. */
function stripImageContent(items: ClipItem[]): ClipItem[] {
  return items.filter((item) => item.clipType !== "image");
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
    const safe = stripImageContent(items);
    if (safe.length === 0) return;
    stackRef.current = [safe, ...stackRef.current].slice(0, MAX_UNDO_OPERATIONS);
    setCanUndo(true);
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
