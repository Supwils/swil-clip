import { render, screen } from "@testing-library/react";
import { Command } from "@/components/ui/command";
import { ClipItem } from "@/components/ClipItem";
import type { ClipItem as ClipItemType } from "@/types/clipboard";

// ClipItem uses CommandItem which requires a Command context
function Wrapper({ children }: { children: React.ReactNode }): React.ReactElement {
  return <Command>{children}</Command>;
}

const textItem: ClipItemType = {
  id: "t1",
  clipType: "text",
  content: "Hello clipboard",
  preview: "Hello clipboard",
  timestamp: 1700000000000,
};

const imageItem: ClipItemType = {
  id: "i1",
  clipType: "image",
  content: "base64datahere",
  preview: "Image (png)",
  timestamp: 1700000000000,
  imageWidth: 800,
  imageHeight: 600,
  imageFormat: "png",
};

describe("ClipItem", () => {
  const onSelect = vi.fn();
  const onDelete = vi.fn();
  const onPin = vi.fn();
  const onToggleExpand = vi.fn();

  beforeEach(() => {
    onSelect.mockClear();
    onDelete.mockClear();
    onPin.mockClear();
    onToggleExpand.mockClear();
  });

  it("renders text item preview", () => {
    render(
      <Wrapper>
        <ClipItem item={textItem} index={0} onSelect={onSelect} onDelete={onDelete} onPin={onPin} isExpanded={false} onToggleExpand={onToggleExpand} />
      </Wrapper>,
    );
    expect(screen.getByText("Hello clipboard")).toBeInTheDocument();
  });

  // The ⌥N badge was removed: on macOS, holding Option rewrites
  // KeyboardEvent.key to the layout's alternate character (⌥1 → "¡"), so the
  // App-level `parseInt(event.key)` handler it advertised almost certainly
  // never fired. A row must not name a keystroke it can't deliver.
  it("does not advertise an ⌥ shortcut on any row", () => {
    for (const index of [0, 8, 9]) {
      const { unmount } = render(
        <Wrapper>
          <ClipItem item={textItem} index={index} onSelect={onSelect} onDelete={onDelete} onPin={onPin} isExpanded={false} onToggleExpand={onToggleExpand} />
        </Wrapper>,
      );
      expect(screen.queryByText("⌥")).not.toBeInTheDocument();
      unmount();
    }
  });

  it("renders image item with img element", () => {
    render(
      <Wrapper>
        <ClipItem item={imageItem} index={0} onSelect={onSelect} onDelete={onDelete} onPin={onPin} isExpanded={false} onToggleExpand={onToggleExpand} />
      </Wrapper>,
    );
    const img = screen.getByAltText("clipboard image");
    expect(img).toBeInTheDocument();
    expect(img).toHaveAttribute(
      "src",
      "data:image/png;base64,base64datahere",
    );
  });

  it("shows image dimensions for image type", () => {
    render(
      <Wrapper>
        <ClipItem item={imageItem} index={0} onSelect={onSelect} onDelete={onDelete} onPin={onPin} isExpanded={false} onToggleExpand={onToggleExpand} />
      </Wrapper>,
    );
    expect(screen.getByText("800×600 PNG")).toBeInTheDocument();
  });

  it("renders delete button", () => {
    render(
      <Wrapper>
        <ClipItem item={textItem} index={0} onSelect={onSelect} onDelete={onDelete} onPin={onPin} isExpanded={false} onToggleExpand={onToggleExpand} />
      </Wrapper>,
    );
    expect(screen.getByRole("button", { name: "Delete item" })).toBeInTheDocument();
  });
});
