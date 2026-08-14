import { act, renderHook } from "@testing-library/react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useClipboardActions } from "@/hooks/useClipboardActions";
import type { ClipItem } from "@/types/clipboard";

const mockItem: ClipItem = {
  id: "abc-123",
  clipType: "text",
  content: "test content",
  preview: "test content",
  timestamp: 1700000000000,
};

describe("useClipboardActions", () => {
  const onHistoryChanged = vi.fn().mockResolvedValue(undefined);

  beforeEach(() => {
    vi.mocked(invoke).mockResolvedValue(undefined);
    onHistoryChanged.mockClear();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("hides window then invokes paste_item on pasteItem", async () => {
    const mockHide = vi.fn().mockResolvedValue(undefined);
    vi.mocked(getCurrentWindow).mockReturnValueOnce({
      hide: mockHide,
      show: vi.fn(),
      setFocus: vi.fn(),
      onFocusChanged: vi.fn(() => Promise.resolve(() => {})),
      isVisible: vi.fn(() => Promise.resolve(false)),
    } as unknown as ReturnType<typeof getCurrentWindow>);

    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    await act(async () => {
      await expect(result.current.pasteItem(mockItem)).resolves.toBe(true);
    });

    expect(mockHide).toHaveBeenCalledOnce();
    expect(invoke).toHaveBeenCalledWith("paste_item", { id: "abc-123" });
  });

  it("invokes delete_item and calls onHistoryChanged on deleteItem", async () => {
    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    await act(async () => {
      await expect(result.current.deleteItem("abc-123")).resolves.toBe(true);
    });

    expect(invoke).toHaveBeenCalledWith("delete_item", { id: "abc-123" });
    expect(onHistoryChanged).toHaveBeenCalledOnce();
  });

  it("invokes clear_history and calls onHistoryChanged on clearAll", async () => {
    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    await act(async () => {
      await expect(result.current.clearAll()).resolves.toBe(true);
    });

    expect(invoke).toHaveBeenCalledWith("clear_history");
    expect(onHistoryChanged).toHaveBeenCalledOnce();
  });

  it("returns false when invoke fails on pasteItem", async () => {
    vi.mocked(invoke).mockRejectedValueOnce(new Error("paste error"));

    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    await act(async () => {
      await expect(result.current.pasteItem(mockItem)).resolves.toBe(false);
    });
  });

  // Contract change: overlapping mutations QUEUE. They used to be rejected,
  // which silently ate keystrokes — holding `d` to clear a run of entries
  // landed roughly one press in four (SC-04 in docs/code-review.md).
  // Serialisation is still required, because the backend mutation path is a
  // read-modify-write over one blob; what changed is that waiting your turn no
  // longer means being dropped.
  it("queues an overlapping action instead of dropping it", async () => {
    let resolveDelete: (() => void) | undefined;
    vi.mocked(invoke).mockImplementationOnce(
      () =>
        new Promise<void>((resolve) => {
          resolveDelete = resolve;
        }),
    );

    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    let deletePromise: Promise<boolean> | undefined;
    let pinPromise: Promise<boolean> | undefined;

    act(() => {
      deletePromise = result.current.deleteItem("abc-123");
      pinPromise = result.current.pinItem("abc-123", true);
    });

    expect(result.current.isBusy).toBe(true);

    // Work is picked up off the queue on a microtask, so nothing has reached
    // the backend synchronously — let the first link start.
    await act(async () => {});

    // The pin is waiting its turn, not rejected: it must not have reached the
    // backend while the delete is still in flight.
    expect(invoke).toHaveBeenCalledTimes(1);
    expect(invoke).toHaveBeenCalledWith("delete_item", { id: "abc-123" });

    await act(async () => {
      resolveDelete?.();
      await expect(deletePromise).resolves.toBe(true);
      await expect(pinPromise).resolves.toBe(true);
    });

    // Both landed, and in the order they were requested.
    expect(vi.mocked(invoke).mock.calls.map(([cmd]) => cmd)).toEqual([
      "delete_item",
      "pin_item",
    ]);
    expect(onHistoryChanged).toHaveBeenCalledTimes(2);
    expect(result.current.isBusy).toBe(false);
  });

  it("keeps the queue alive after a failing operation", async () => {
    vi.mocked(invoke)
      .mockRejectedValueOnce(new Error("delete exploded"))
      .mockResolvedValue(undefined);

    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    let failed: Promise<boolean> | undefined;
    let after: Promise<boolean> | undefined;

    act(() => {
      failed = result.current.deleteItem("abc-123");
      after = result.current.pinItem("abc-123", true);
    });

    await act(async () => {
      await expect(failed).resolves.toBe(false);
      // A rejected link must not wedge everything queued behind it.
      await expect(after).resolves.toBe(true);
    });

    expect(result.current.isBusy).toBe(false);
  });
});
