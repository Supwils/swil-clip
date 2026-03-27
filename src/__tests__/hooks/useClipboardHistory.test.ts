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

  it("adds new item from clipboard-changed event", async () => {
    let capturedCallback: ((event: { payload: ClipItem }) => void) | undefined;

    vi.mocked(listen).mockImplementationOnce((_, callback) => {
      capturedCallback = callback as (event: { payload: ClipItem }) => void;
      return Promise.resolve(() => {});
    });

    const { result } = renderHook(() => useClipboardHistory());
    await waitFor(() => expect(result.current.isLoading).toBe(false));

    act(() => {
      capturedCallback?.({ payload: mockTextItem });
    });

    expect(result.current.items).toHaveLength(1);
    expect(result.current.items[0]).toEqual(mockTextItem);
  });

  it("prepends new item to existing history from event", async () => {
    vi.mocked(invoke).mockResolvedValueOnce([mockTextItem]);
    let capturedCallback: ((event: { payload: ClipItem }) => void) | undefined;

    vi.mocked(listen).mockImplementationOnce((_, callback) => {
      capturedCallback = callback as (event: { payload: ClipItem }) => void;
      return Promise.resolve(() => {});
    });

    const { result } = renderHook(() => useClipboardHistory());
    await waitFor(() => expect(result.current.items).toHaveLength(1));

    act(() => {
      capturedCallback?.({ payload: mockTextItem2 });
    });

    expect(result.current.items).toHaveLength(2);
    expect(result.current.items[0]).toEqual(mockTextItem2);
  });

  it("deduplicates: same content+type event replaces old entry", async () => {
    vi.mocked(invoke).mockResolvedValueOnce([mockTextItem, mockTextItem2]);
    let capturedCallback: ((event: { payload: ClipItem }) => void) | undefined;

    vi.mocked(listen).mockImplementationOnce((_, callback) => {
      capturedCallback = callback as (event: { payload: ClipItem }) => void;
      return Promise.resolve(() => {});
    });

    const { result } = renderHook(() => useClipboardHistory());
    await waitFor(() => expect(result.current.items).toHaveLength(2));

    // New item with same content as mockTextItem but different id
    const duplicate: ClipItem = { ...mockTextItem, id: "new-id" };
    act(() => {
      capturedCallback?.({ payload: duplicate });
    });

    // Length stays at 2 (replaced, not appended)
    expect(result.current.items).toHaveLength(2);
    expect(result.current.items[0]?.id).toBe("new-id");
  });
});
