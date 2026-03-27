import { renderHook, act } from "@testing-library/react";
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
      await result.current.pasteItem(mockItem);
    });

    expect(mockHide).toHaveBeenCalledOnce();
    expect(invoke).toHaveBeenCalledWith("paste_item", { id: "abc-123" });
  });

  it("invokes delete_item and calls onHistoryChanged on deleteItem", async () => {
    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    await act(async () => {
      await result.current.deleteItem("abc-123");
    });

    expect(invoke).toHaveBeenCalledWith("delete_item", { id: "abc-123" });
    expect(onHistoryChanged).toHaveBeenCalledOnce();
  });

  it("invokes clear_history and calls onHistoryChanged on clearAll", async () => {
    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    await act(async () => {
      await result.current.clearAll();
    });

    expect(invoke).toHaveBeenCalledWith("clear_history");
    expect(onHistoryChanged).toHaveBeenCalledOnce();
  });

  it("does not throw when invoke fails on pasteItem", async () => {
    vi.mocked(invoke).mockRejectedValueOnce(new Error("paste error"));

    const { result } = renderHook(() => useClipboardActions(onHistoryChanged));

    await expect(
      act(async () => {
        await result.current.pasteItem(mockItem);
      }),
    ).resolves.not.toThrow();
  });
});
