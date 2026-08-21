import { renderHook, waitFor, act } from "@testing-library/react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useClipboardHistory } from "@/hooks/useClipboardHistory";
import type { ClipItem } from "@/types/clipboard";

const mockTextItem: ClipItem = {
  id: "test-id-1",
  clipType: "text",
  content: "hello world",
  preview: "hello world",
  timestamp: 1700000000000,
};

const mockTextItem2: ClipItem = {
  id: "test-id-2",
  clipType: "text",
  content: "second item",
  preview: "second item",
  timestamp: 1700000001000,
};

describe("useClipboardHistory", () => {
  beforeEach(() => {
    vi.mocked(invoke).mockResolvedValue([]);
    vi.mocked(listen).mockResolvedValue(() => {});
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("starts in loading state", () => {
    const { result } = renderHook(() => useClipboardHistory());
    expect(result.current.isLoading).toBe(true);
  });

  it("fetches history on mount and exits loading", async () => {
    vi.mocked(invoke).mockResolvedValueOnce([mockTextItem]);
    const { result } = renderHook(() => useClipboardHistory());

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(invoke).toHaveBeenCalledWith("get_history");
    expect(result.current.items).toEqual([mockTextItem]);
    expect(result.current.error).toBeNull();
  });

  it("returns empty items when history is empty", async () => {
    vi.mocked(invoke).mockResolvedValueOnce([]);
    const { result } = renderHook(() => useClipboardHistory());

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(result.current.items).toHaveLength(0);
  });

  it("registers clipboard-changed event listener on mount", async () => {
    const { result } = renderHook(() => useClipboardHistory());
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    expect(listen).toHaveBeenCalledWith("clipboard-changed", expect.any(Function));
  });

  it("refetches the authoritative list on clipboard-changed", async () => {
    let capturedCallback: (() => void) | undefined;

    vi.mocked(listen).mockImplementationOnce((_, callback) => {
      capturedCallback = callback as () => void;
      return Promise.resolve(() => {});
    });

    // Initial load: one item. After the event, the backend has merged the
    // new copy in and returns the updated list.
    vi.mocked(invoke)
      .mockResolvedValueOnce([mockTextItem])
      .mockResolvedValueOnce([mockTextItem2, mockTextItem]);

    const { result } = renderHook(() => useClipboardHistory());
    await waitFor(() => expect(result.current.items).toHaveLength(1));

    act(() => {
      capturedCallback?.();
    });

    await waitFor(() => expect(result.current.items).toHaveLength(2));
    expect(result.current.items[0]).toEqual(mockTextItem2);
    expect(invoke).toHaveBeenCalledTimes(2);
    expect(invoke).toHaveBeenNthCalledWith(2, "get_history");
  });

  it("exposes the failure reason and clears it on a successful refresh", async () => {
    vi.mocked(invoke).mockRejectedValueOnce("Keychain read failed");
    const { result } = renderHook(() => useClipboardHistory());

    await waitFor(() => expect(result.current.isLoading).toBe(false));
    expect(result.current.error).toBe("Keychain read failed");
    expect(result.current.items).toHaveLength(0);

    vi.mocked(invoke).mockResolvedValueOnce([mockTextItem]);
    await act(async () => {
      await result.current.refresh();
    });

    expect(result.current.error).toBeNull();
    expect(result.current.items).toEqual([mockTextItem]);
  });
});
