import { describe, expect, it } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { useUndoStack } from "@/hooks/useUndoStack";
import { MAX_UNDO_BYTES, MAX_UNDO_OPERATIONS } from "@/constants";
import type { ClipItem } from "@/types/clipboard";

function textItem(id: string, bytes = 8): ClipItem {
  const content = "t".repeat(bytes);
  return {
    id,
    clipType: "text",
    content,
    preview: content.slice(0, 4),
    timestamp: 1_700_000_000_000,
  };
}

function imageItem(id: string, bytes = 8): ClipItem {
  const content = "i".repeat(bytes);
  return {
    id,
    clipType: "image",
    content,
    preview: "",
    timestamp: 1_700_000_000_000,
    imageFormat: "png",
  };
}

describe("useUndoStack", () => {
  it("restores image entries in a mixed batch (SC-05)", () => {
    // The bug: images were filtered out of the undo batch to save memory, so
    // "Clear unpinned" followed by Undo silently dropped every image while
    // still reporting success. Undo must return exactly what was pushed.
    const { result } = renderHook(() => useUndoStack());
    const batch = [textItem("a"), imageItem("b"), textItem("c")];

    act(() => result.current.pushUndo(batch));

    expect(result.current.canUndo).toBe(true);
    let popped: ClipItem[] | undefined;
    act(() => {
      popped = result.current.popUndo();
    });
    expect(popped).toEqual(batch);
  });

  it("restores an image-only batch instead of discarding it", () => {
    // Previously an all-image batch stripped down to zero entries and was
    // dropped outright, leaving canUndo false with no indication.
    const { result } = renderHook(() => useUndoStack());
    const batch = [imageItem("only")];

    act(() => result.current.pushUndo(batch));

    expect(result.current.canUndo).toBe(true);
    let popped: ClipItem[] | undefined;
    act(() => {
      popped = result.current.popUndo();
    });
    expect(popped).toEqual(batch);
  });

  it("ignores an empty batch", () => {
    const { result } = renderHook(() => useUndoStack());

    act(() => result.current.pushUndo([]));

    expect(result.current.canUndo).toBe(false);
    expect(result.current.popUndo()).toBeUndefined();
  });

  it("pops batches most-recent-first", () => {
    const { result } = renderHook(() => useUndoStack());

    act(() => result.current.pushUndo([textItem("first")]));
    act(() => result.current.pushUndo([textItem("second")]));

    let popped: ClipItem[] | undefined;
    act(() => {
      popped = result.current.popUndo();
    });
    expect(popped?.[0]?.id).toBe("second");

    act(() => {
      popped = result.current.popUndo();
    });
    expect(popped?.[0]?.id).toBe("first");
    expect(result.current.canUndo).toBe(false);
  });

  it("caps the stack at MAX_UNDO_OPERATIONS, evicting the oldest", () => {
    const { result } = renderHook(() => useUndoStack());

    for (let i = 0; i < MAX_UNDO_OPERATIONS + 5; i += 1) {
      act(() => result.current.pushUndo([textItem(`op-${i}`)]));
    }

    const seen: string[] = [];
    for (;;) {
      let popped: ClipItem[] | undefined;
      act(() => {
        popped = result.current.popUndo();
      });
      if (!popped) break;
      seen.push(popped[0]!.id);
    }

    expect(seen).toHaveLength(MAX_UNDO_OPERATIONS);
    // The newest survives, the oldest was evicted.
    expect(seen[0]).toBe(`op-${MAX_UNDO_OPERATIONS + 4}`);
    expect(seen).not.toContain("op-0");
  });

  it("evicts the oldest batches once the byte budget is exceeded", () => {
    // Images are kept now, so memory is bounded by total bytes rather than by
    // dropping entries. This mirrors enforce_byte_budget on the Rust side.
    const { result } = renderHook(() => useUndoStack());
    const half = Math.floor(MAX_UNDO_BYTES / 2);

    act(() => result.current.pushUndo([imageItem("old", half)]));
    act(() => result.current.pushUndo([imageItem("mid", half)]));
    // Third batch pushes the total past the budget; "old" must go first.
    act(() => result.current.pushUndo([imageItem("new", half)]));

    const seen: string[] = [];
    for (;;) {
      let popped: ClipItem[] | undefined;
      act(() => {
        popped = result.current.popUndo();
      });
      if (!popped) break;
      seen.push(popped[0]!.id);
    }

    expect(seen).toEqual(["new", "mid"]);
  });

  it("keeps a single oversized batch rather than silently dropping it", () => {
    // Undo is the user's only recovery path. A batch bigger than the whole
    // budget still has to come back — it just evicts everything else.
    const { result } = renderHook(() => useUndoStack());

    act(() => result.current.pushUndo([textItem("small")]));
    act(() => result.current.pushUndo([imageItem("huge", MAX_UNDO_BYTES + 1)]));

    let popped: ClipItem[] | undefined;
    act(() => {
      popped = result.current.popUndo();
    });
    expect(popped?.[0]?.id).toBe("huge");
    expect(result.current.canUndo).toBe(false);
  });
});
