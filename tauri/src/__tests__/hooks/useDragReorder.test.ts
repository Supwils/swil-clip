import { computeReorder } from "@/hooks/useDragReorder";
import type { ClipItem } from "@/types/clipboard";

function item(id: string, pinned = false): ClipItem {
  return {
    id,
    clipType: "text",
    content: id,
    preview: id,
    timestamp: 0,
    pinned,
  };
}

describe("computeReorder", () => {
  it("reorders within Recent section: drag last → before first", () => {
    const pinned = [item("p1", true)];
    const recent = [item("r1"), item("r2"), item("r3")];

    const result = computeReorder(pinned, recent, "r3", "r1", "recent", "before");

    expect(result).not.toBeNull();
    expect(result!.orderedIds).toEqual(["p1", "r3", "r1", "r2"]);
    expect(result!.pinnedIds).toEqual(["p1"]);
  });

  it("reorders within Pinned section", () => {
    const pinned = [item("p1", true), item("p2", true), item("p3", true)];
    const recent: ClipItem[] = [];

    const result = computeReorder(pinned, recent, "p3", "p1", "pinned", "before");

    expect(result).not.toBeNull();
    expect(result!.orderedIds).toEqual(["p3", "p1", "p2"]);
    expect(result!.pinnedIds).toEqual(["p3", "p1", "p2"]);
  });

  it("drag Recent → Pinned auto-pins the item", () => {
    const pinned = [item("p1", true)];
    const recent = [item("r1"), item("r2")];

    const result = computeReorder(pinned, recent, "r1", "p1", "pinned", "after");

    expect(result).not.toBeNull();
    expect(result!.orderedIds).toEqual(["p1", "r1", "r2"]);
    expect(result!.pinnedIds).toEqual(["p1", "r1"]);
  });

  it("drag Pinned → Recent auto-unpins the item", () => {
    const pinned = [item("p1", true), item("p2", true)];
    const recent = [item("r1")];

    const result = computeReorder(pinned, recent, "p2", "r1", "recent", "before");

    expect(result).not.toBeNull();
    expect(result!.orderedIds).toEqual(["p1", "p2", "r1"]);
    expect(result!.pinnedIds).toEqual(["p1"]);
  });

  it("detects no-op drops (same position) and returns null", () => {
    const pinned: ClipItem[] = [];
    const recent = [item("r1"), item("r2"), item("r3")];

    // Dropping r2 "before r2" stays at the same position.
    const result = computeReorder(pinned, recent, "r2", "r2", "recent", "before");

    expect(result).toBeNull();
  });

  it("handles drop at tail of target section (overItemId null)", () => {
    const pinned: ClipItem[] = [];
    const recent = [item("r1"), item("r2"), item("r3")];

    const result = computeReorder(pinned, recent, "r1", null, "recent", "before");

    expect(result).not.toBeNull();
    expect(result!.orderedIds).toEqual(["r2", "r3", "r1"]);
  });

  it("drag last Recent → first Pinned slot pins & places at top", () => {
    const pinned = [item("p1", true)];
    const recent = [item("r1"), item("r2")];

    const result = computeReorder(pinned, recent, "r2", "p1", "pinned", "before");

    expect(result).not.toBeNull();
    expect(result!.orderedIds).toEqual(["r2", "p1", "r1"]);
    expect(result!.pinnedIds).toEqual(["r2", "p1"]);
  });
});
