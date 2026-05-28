import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { App } from "@/App";
import type { ClipItem } from "@/types/clipboard";

const appMocks = vi.hoisted(() => ({
  items: [
    {
      id: "clip-1",
      clipType: "text",
      content: "hello",
      preview: "hello",
      timestamp: 1700000000000,
    },
    {
      id: "clip-2",
      clipType: "text",
      content: "world",
      preview: "world",
      timestamp: 1700000001000,
    },
  ] satisfies ClipItem[],
  refresh: vi.fn(),
  pasteItem: vi.fn().mockResolvedValue(true),
  deleteItem: vi.fn().mockResolvedValue(true),
  clearAll: vi.fn().mockResolvedValue(true),
  pinItem: vi.fn().mockResolvedValue(true),
  state: {
    isBusy: false,
  },
}));

vi.mock("@/hooks/useClipboardHistory", () => ({
  useClipboardHistory: () => ({
    items: appMocks.items,
    refresh: appMocks.refresh,
  }),
}));

vi.mock("@/hooks/useClipboardActions", () => ({
  useClipboardActions: () => ({
    isBusy: appMocks.state.isBusy,
    pasteItem: appMocks.pasteItem,
    deleteItem: appMocks.deleteItem,
    clearAll: appMocks.clearAll,
    pinItem: appMocks.pinItem,
  }),
}));

vi.mock("@/hooks/useSettings", () => ({
  useSettings: () => ({
    settings: { globalShortcut: "cmd+shift+v" },
    isLoading: false,
    updateGlobalShortcut: vi.fn().mockResolvedValue(undefined),
  }),
}));

describe("App", () => {
  beforeEach(() => {
    appMocks.state.isBusy = false;
    appMocks.refresh.mockClear();
    appMocks.pasteItem.mockClear();
    appMocks.deleteItem.mockClear();
    appMocks.clearAll.mockClear();
    appMocks.pinItem.mockClear();
  });

  it("keeps quick paste enabled in navigate mode", async () => {
    render(<App />);

    fireEvent.keyDown(document, { key: "1", altKey: true });

    await waitFor(() => {
      expect(appMocks.pasteItem).toHaveBeenCalledWith(appMocks.items[0]);
    });
  });

  it("disables quick paste while the search input is focused", async () => {
    const { container } = render(<App />);
    const root = container.querySelector("[cmdk-root]");

    if (!(root instanceof HTMLElement)) {
      throw new Error("Command root not found");
    }

    fireEvent.keyDown(root, { key: "s" });

    const input = screen.getByPlaceholderText("Search clipboard...");
    await waitFor(() => {
      expect(input).toHaveFocus();
    });

    fireEvent.keyDown(input, { key: "1", altKey: true });

    expect(appMocks.pasteItem).not.toHaveBeenCalled();
  });
});
