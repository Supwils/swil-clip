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

  it("rejects overlapping actions while one mutation is still running", async () => {
    let resolveDelete: (() => void) | undefined;
    vi.mocked(invoke).mockImplementationOnce(
      () =>
        new Promise<void>((resolve) => {
          resolveDelete = resolve;
        }),
    );

    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    let firstDeletePromise: Promise<boolean> | undefined;

    act(() => {
      firstDeletePromise = result.current.deleteItem("abc-123");
    });

    expect(result.current.isBusy).toBe(true);

    await act(async () => {
      await expect(result.current.pinItem("abc-123", true)).resolves.toBe(false);
    });

    expect(invoke).toHaveBeenCalledTimes(1);
    expect(onHistoryChanged).not.toHaveBeenCalled();

    resolveDelete?.();

    await act(async () => {
      await expect(firstDeletePromise).resolves.toBe(true);
    });

    expect(result.current.isBusy).toBe(false);
    expect(onHistoryChanged).toHaveBeenCalledOnce();
  });
});
