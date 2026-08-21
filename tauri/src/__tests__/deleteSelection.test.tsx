import { fireEvent, render, waitFor } from "@testing-library/react";
import { invoke } from "@tauri-apps/api/core";
import { App } from "@/App";
import type { ClipItem } from "@/types/clipboard";

/**
 * Selection-after-delete, exercised through the REAL stack: App → hooks →
 * ClipboardPanel → cmdk, with only the Tauri IPC boundary mocked.
 *
 * The mocked `invoke` deliberately resolves across a `setTimeout`, i.e. a real
 * task boundary, because that is the only thing that makes this class of bug
 * observable. cmdk keeps its own copy of the selected value and, when the
 * currently-selected item unmounts, resets it to the first row in the DOM
 * (`selectFirstItem`). ClipboardPanel defuses that by moving the selection off
 * the doomed row (flushSync) *before* the delete is dispatched. If a future
 * change ever moves that migration to after the await, the list commits — and
 * the row unmounts — in its own task, cmdk grabs row 0, and because <Command>
 * is controlled but `props.value` never changed, nothing ever syncs it back.
 *
 * An IPC mock that resolves in a microtask collapses every continuation into
 * one checkpoint and hides all of it: the panel-level tests pass either way.
 * Do not "simplify" the delay out of this file.
 *
 * Second test is the one that actually costs users data: once the highlight
 * and React state disagree, `d` deletes the row React thinks is selected while
 * the user is looking at a different one.
 */

const invokeMock = vi.mocked(invoke);
const IPC_LATENCY_MS = 5;

function makeItems(n: number): ClipItem[] {
  return Array.from({ length: n }, (_, i) => ({
    id: `id-${i + 1}`,
    clipType: "text" as const,
    content: `item ${i + 1}`,
    preview: `item ${i + 1}`,
    timestamp: 1700000000000 + i,
  }));
}

function selectedPreview(container: HTMLElement): string | null {
  const row = container.querySelector('[cmdk-item][aria-selected="true"]');
  return row?.querySelector(".clip-preview")?.textContent?.trim() ?? null;
}

describe("selection after delete", () => {
  let store: ClipItem[];

  beforeEach(() => {
    store = makeItems(6);
    invokeMock.mockReset();
    invokeMock.mockImplementation(async (cmd: string, args?: unknown) => {
      await new Promise((resolve) => setTimeout(resolve, IPC_LATENCY_MS));
      const payload = (args ?? {}) as Record<string, unknown>;
      switch (cmd) {
        case "get_history":
          return store.map((item) => ({ ...item })) as never;
        case "delete_item":
          store = store.filter((item) => item.id !== payload.id);
          return undefined as never;
        case "get_settings":
          return {
            globalShortcut: "cmd+shift+v",
            maxHistory: 50,
            autoPaste: false,
          } as never;
        default:
          return undefined as never;
      }
    });
  });

  async function renderAtThirdRow() {
    const result = render(<App />);
    const root = result.container.querySelector("[cmdk-root]");
    if (!(root instanceof HTMLElement)) throw new Error("Command root not found");

    await waitFor(() => expect(selectedPreview(result.container)).toBe("item 1"));
    fireEvent.keyDown(root, { key: "ArrowDown" });
    fireEvent.keyDown(root, { key: "ArrowDown" });
    await waitFor(() => expect(selectedPreview(result.container)).toBe("item 3"));

    return { ...result, root };
  }

  it("keeps the cursor in place when d deletes across an async IPC round-trip", async () => {
    const { container, root } = await renderAtThirdRow();

    fireEvent.keyDown(root, { key: "d" });

    await waitFor(() => expect(container.textContent).not.toContain("item 3"));
    // The highlight must be on the successor, never back at the top.
    await waitFor(() => expect(selectedPreview(container)).toBe("item 4"));
  });

  it("lands every d press when they arrive faster than the backend", async () => {
    // The gesture that used to fail: hold `d` to clear a run of entries. Each
    // press previously landed inside the previous delete's round-trip, where
    // the isBusy gate and the actions hook's reject-if-busy both discarded it.
    const { container, root } = await renderAtThirdRow();

    for (let i = 0; i < 4; i++) {
      fireEvent.keyDown(root, { key: "d" });
    }

    await waitFor(() => expect(store.map((item) => item.id)).toEqual(["id-1", "id-2"]), {
      timeout: 2000,
    });
    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === "delete_item")).toHaveLength(4);
    // Cursor ends on the row after the last one deleted; nothing is left below
    // it, so it clamps to the end of the list.
    expect(selectedPreview(container)).toBe("item 2");
  });

  it("keeps d targeting the highlighted row after a previous delete", async () => {
    const { container, root } = await renderAtThirdRow();

    // The Undo button re-enables only once the mutation lock clears, so this
    // is the observable "the previous delete has fully landed" signal.
    const settled = () =>
      waitFor(() =>
        expect(container.querySelector('button[aria-label="Undo last deletion"]')).not.toBeDisabled(),
      );

    fireEvent.keyDown(root, { key: "d" });
    await waitFor(() => expect(container.textContent).not.toContain("item 3"));
    await settled();
    expect(selectedPreview(container)).toBe("item 4");

    fireEvent.keyDown(root, { key: "d" });
    await waitFor(() => expect(container.textContent).not.toContain("item 4"));
    await settled();

    // id-1 must still be there: if React state and the rendered highlight had
    // drifted apart, the second `d` would have deleted the top row instead.
    expect(store.map((item) => item.id)).toEqual(["id-1", "id-2", "id-5", "id-6"]);
    expect(selectedPreview(container)).toBe("item 5");
  });
});
