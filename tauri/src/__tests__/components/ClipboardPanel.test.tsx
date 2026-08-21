import { useState, type ComponentProps, type ReactElement } from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ClipboardPanel } from "@/components/ClipboardPanel";
import type { ClipItem } from "@/types/clipboard";
import type { UseSettingsReturn } from "@/hooks/useSettings";
import { PANEL_DRAG_REGION_HEIGHT_PX } from "@/constants";
import { DEFAULT_SETTINGS } from "@/types/settings";

function makeSettingsApi(): UseSettingsReturn {
  return {
    settings: DEFAULT_SETTINGS,
    isLoading: false,
    updateGlobalShortcut: vi.fn().mockResolvedValue(undefined),
    updateMaxHistory: vi.fn().mockResolvedValue(undefined),
    updateAutoPaste: vi.fn().mockResolvedValue(undefined),
  };
}

const items: ClipItem[] = [
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
  {
    id: "clip-3",
    clipType: "text",
    content: "third item",
    preview: "third item",
    timestamp: 1700000002000,
  },
];

function getCommandRoot(container: HTMLElement): HTMLElement {
  const root = container.querySelector("[cmdk-root]");
  if (!(root instanceof HTMLElement)) {
    throw new Error("Command root not found");
  }
  return root;
}

function getSelectedItem(container: HTMLElement): HTMLElement {
  const item = container.querySelector('[cmdk-item][aria-selected="true"]');
  if (!(item instanceof HTMLElement)) {
    throw new Error("Selected item not found");
  }
  return item;
}

function renderPanel(overrides: Partial<ComponentProps<typeof ClipboardPanel>> = {}) {
  const onPaste = vi.fn().mockResolvedValue(true);
  const onDelete = vi.fn().mockResolvedValue(true);
  const onClearAll = vi.fn().mockResolvedValue(true);
  const onPin = vi.fn().mockResolvedValue(true);
  const onHide = vi.fn();

  const onClearUnpinned = vi.fn().mockResolvedValue(true);
  const onUndo = vi.fn().mockResolvedValue(true);

  const result = render(
    <ClipboardPanel
      items={items}
      onPaste={onPaste}
      onDelete={onDelete}
      onClearAll={onClearAll}
      onClearUnpinned={onClearUnpinned}
      onUndo={onUndo}
      canUndo={false}
      onPin={onPin}
      onHide={onHide}
      isBusy={false}
      settingsApi={makeSettingsApi()}
      {...overrides}
    />,
  );

  return { ...result, onPaste, onDelete, onClearAll, onPin, onHide };
}

describe("ClipboardPanel", () => {
  it("renders the drag region with data-tauri-drag-region attribute", () => {
    renderPanel();

    const dragRegion = screen.getByLabelText("Drag to move window");
    expect(dragRegion).toBeInTheDocument();
    expect(dragRegion).toHaveAttribute("data-tauri-drag-region");
  });

  it("renders the drag region with the correct height", () => {
    renderPanel();

    const dragRegion = screen.getByLabelText("Drag to move window");
    expect(dragRegion).toHaveStyle({ height: `${PANEL_DRAG_REGION_HEIGHT_PX}px` });
  });

  it("focuses the command root on mount", async () => {
    const { container } = renderPanel();
    const root = getCommandRoot(container);

    await waitFor(() => {
      expect(root).toHaveFocus();
    });
  });

  it("enters search mode on s and restores focus on Escape", async () => {
    const user = userEvent.setup();
    const { container } = renderPanel();
    const root = getCommandRoot(container);

    await waitFor(() => {
      expect(root).toHaveFocus();
    });

    fireEvent.keyDown(root, { key: "s" });

    const input = screen.getByPlaceholderText("Search clipboard...");
    await waitFor(() => {
      expect(input).toHaveFocus();
    });

    await user.type(input, "wo");
    expect(input).toHaveValue("wo");

    fireEvent.keyDown(input, { key: "Escape" });

    await waitFor(() => {
      expect(root).toHaveFocus();
    });
    expect(input).toHaveValue("");
  });

  it("pastes the selected item on Enter", async () => {
    const { container, onPaste } = renderPanel();
    const root = getCommandRoot(container);

    await waitFor(() => {
      expect(getSelectedItem(container)).toHaveTextContent("hello");
    });

    fireEvent.keyDown(root, { key: "Enter" });

    await waitFor(() => {
      expect(onPaste).toHaveBeenCalledWith(items[0]);
    });
  });

  it("moves selection after deleting the selected item once the list updates", async () => {
    function Harness(): ReactElement {
      const [currentItems, setCurrentItems] = useState(items);

      return (
        <ClipboardPanel
          items={currentItems}
          onPaste={vi.fn().mockResolvedValue(true)}
          onDelete={vi.fn(async (id: string) => {
            setCurrentItems((prev) => prev.filter((item) => item.id !== id));
            return true;
          })}
          onClearAll={vi.fn().mockResolvedValue(true)}
          onClearUnpinned={vi.fn().mockResolvedValue(true)}
          onUndo={vi.fn().mockResolvedValue(true)}
          canUndo={false}
          onPin={vi.fn().mockResolvedValue(true)}
          onHide={vi.fn()}
          isBusy={false}
          settingsApi={makeSettingsApi()}
        />
      );
    }

    const { container } = render(<Harness />);
    const root = getCommandRoot(container);

    await waitFor(() => {
      expect(getSelectedItem(container)).toHaveTextContent("hello");
    });

    fireEvent.keyDown(root, { key: "d" });

    await waitFor(() => {
      expect(screen.queryByText("hello")).not.toBeInTheDocument();
      expect(getSelectedItem(container)).toHaveTextContent("world");
    });
  });

  // Regression guard: cmdk trims item values before writing them to the
  // `data-value` DOM attribute. If the React side stored the untrimmed form,
  // `d` would silently no-op and the selection would jump to the top after
  // delete, because every "is this the selected item?" comparison reads from
  // the DOM. Items whose preview ends in whitespace (`text.chars().take(200)`
  // routinely truncates at a space — exactly the case for expandable items)
  // would be the ones to break.
  it("deletes via d and advances selection when preview has trailing whitespace", async () => {
    const whitespaceItems: ClipItem[] = [
      {
        id: "ws-1",
        clipType: "text",
        content: "long content that exceeds the preview ",
        preview: "long content that exceeds the preview ",
        timestamp: 1700000000000,
      },
      {
        id: "ws-2",
        clipType: "text",
        content: "second\n",
        preview: "second\n",
        timestamp: 1700000001000,
      },
    ];

    function Harness(): ReactElement {
      const [currentItems, setCurrentItems] = useState(whitespaceItems);

      return (
        <ClipboardPanel
          items={currentItems}
          onPaste={vi.fn().mockResolvedValue(true)}
          onDelete={vi.fn(async (id: string) => {
            setCurrentItems((prev) => prev.filter((item) => item.id !== id));
            return true;
          })}
          onClearAll={vi.fn().mockResolvedValue(true)}
          onClearUnpinned={vi.fn().mockResolvedValue(true)}
          onUndo={vi.fn().mockResolvedValue(true)}
          canUndo={false}
          onPin={vi.fn().mockResolvedValue(true)}
          onHide={vi.fn()}
          isBusy={false}
          settingsApi={makeSettingsApi()}
        />
      );
    }

    const { container } = render(<Harness />);
    const root = getCommandRoot(container);

    await waitFor(() => {
      expect(getSelectedItem(container)).toHaveTextContent(
        "long content that exceeds the preview",
      );
    });

    fireEvent.keyDown(root, { key: "d" });

    await waitFor(() => {
      expect(
        screen.queryByText("long content that exceeds the preview"),
      ).not.toBeInTheDocument();
      expect(getSelectedItem(container)).toHaveTextContent("second");
    });
  });

  it("moves selection to the previous item when deleting the last item", async () => {
    function Harness(): ReactElement {
      const [currentItems, setCurrentItems] = useState(items);

      return (
        <ClipboardPanel
          items={currentItems}
          onPaste={vi.fn().mockResolvedValue(true)}
          onDelete={vi.fn(async (id: string) => {
            setCurrentItems((prev) => prev.filter((item) => item.id !== id));
            return true;
          })}
          onClearAll={vi.fn().mockResolvedValue(true)}
          onClearUnpinned={vi.fn().mockResolvedValue(true)}
          onUndo={vi.fn().mockResolvedValue(true)}
          canUndo={false}
          onPin={vi.fn().mockResolvedValue(true)}
          onHide={vi.fn()}
          isBusy={false}
          settingsApi={makeSettingsApi()}
        />
      );
    }

    const { container } = render(<Harness />);
    const root = getCommandRoot(container);

    await waitFor(() => {
      expect(getSelectedItem(container)).toHaveTextContent("hello");
    });

    fireEvent.keyDown(root, { key: "ArrowDown" });
    fireEvent.keyDown(root, { key: "ArrowDown" });

    await waitFor(() => {
      expect(getSelectedItem(container)).toHaveTextContent("third item");
    });

    fireEvent.keyDown(root, { key: "d" });

    await waitFor(() => {
      expect(screen.queryByText("third item")).not.toBeInTheDocument();
      expect(getSelectedItem(container)).toHaveTextContent("world");
    });
  });

  // Regression guard: with a search active, the delete successor must be
  // picked from the FILTERED list — picking by index from the full items
  // array could select a hidden row, leaving the visible highlight on the
  // first item and keyboard actions targeting an invisible one.
  it("keeps selection among visible matches when deleting during a search", async () => {
    const searchItems: ClipItem[] = [
      { id: "s-1", clipType: "text", content: "apple pie", preview: "apple pie", timestamp: 1 },
      { id: "s-2", clipType: "text", content: "banana", preview: "banana", timestamp: 2 },
      { id: "s-3", clipType: "text", content: "apple tart", preview: "apple tart", timestamp: 3 },
      { id: "s-4", clipType: "text", content: "cherry", preview: "cherry", timestamp: 4 },
    ];

    function Harness(): ReactElement {
      const [currentItems, setCurrentItems] = useState(searchItems);

      return (
        <ClipboardPanel
          items={currentItems}
          onPaste={vi.fn().mockResolvedValue(true)}
          onDelete={vi.fn(async (id: string) => {
            setCurrentItems((prev) => prev.filter((item) => item.id !== id));
            return true;
          })}
          onClearAll={vi.fn().mockResolvedValue(true)}
          onClearUnpinned={vi.fn().mockResolvedValue(true)}
          onUndo={vi.fn().mockResolvedValue(true)}
          canUndo={false}
          onPin={vi.fn().mockResolvedValue(true)}
          onHide={vi.fn()}
          isBusy={false}
          settingsApi={makeSettingsApi()}
        />
      );
    }

    const user = userEvent.setup();
    const { container } = render(<Harness />);
    const root = getCommandRoot(container);

    await waitFor(() => {
      expect(getSelectedItem(container)).toHaveTextContent("apple pie");
    });

    fireEvent.keyDown(root, { key: "s" });
    const input = screen.getByPlaceholderText("Search clipboard...");
    await waitFor(() => expect(input).toHaveFocus());
    await user.type(input, "apple");

    // Only the two apple items are rendered; selection stays on the first.
    await waitFor(() => {
      expect(screen.queryByText("banana")).not.toBeInTheDocument();
      expect(getSelectedItem(container)).toHaveTextContent("apple pie");
    });

    // In search mode `d` types into the input, so delete via the selected
    // row's delete button (same handleDelete path as the shortcut).
    const deleteButton = getSelectedItem(container).querySelector(
      'button[aria-label="Delete item"]',
    );
    expect(deleteButton).not.toBeNull();
    fireEvent.click(deleteButton!);

    // Successor is the next VISIBLE match (apple tart), not the hidden banana.
    await waitFor(() => {
      expect(screen.queryByText("apple pie")).not.toBeInTheDocument();
      expect(getSelectedItem(container)).toHaveTextContent("apple tart");
    });
  });
});
