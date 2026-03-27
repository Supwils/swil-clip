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

  beforeEach(() => {
    onSelect.mockClear();
    onDelete.mockClear();
  });

  it("renders text item preview", () => {
    render(
      <Wrapper>
        <ClipItem item={textItem} index={0} onSelect={onSelect} onDelete={onDelete} />
      </Wrapper>,
    );
    expect(screen.getByText("Hello clipboard")).toBeInTheDocument();
  });

  it("shows ⌥1 shortcut badge for index 0", () => {
    render(
      <Wrapper>
        <ClipItem item={textItem} index={0} onSelect={onSelect} onDelete={onDelete} />
      </Wrapper>,
    );
    expect(screen.getByText("⌥")).toBeInTheDocument();
    expect(screen.getByText("1")).toBeInTheDocument();
  });

  it("shows ⌥9 shortcut badge for index 8 (last shortcut)", () => {
    render(
      <Wrapper>
        <ClipItem item={textItem} index={8} onSelect={onSelect} onDelete={onDelete} />
      </Wrapper>,
    );
    expect(screen.getByText("9")).toBeInTheDocument();
  });

  it("does not show shortcut badge for index 9 (beyond QUICK_PASTE_LIMIT)", () => {
    render(
      <Wrapper>
        <ClipItem item={textItem} index={9} onSelect={onSelect} onDelete={onDelete} />
      </Wrapper>,
    );
    // index 9 → shortcutIndex 10, beyond limit of 9
    expect(screen.queryByText("10")).not.toBeInTheDocument();
    expect(screen.queryByText("⌥")).not.toBeInTheDocument();
  });

  it("renders image item with img element", () => {
    render(
      <Wrapper>
        <ClipItem item={imageItem} index={0} onSelect={onSelect} onDelete={onDelete} />
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
        <ClipItem item={imageItem} index={0} onSelect={onSelect} onDelete={onDelete} />
      </Wrapper>,
    );
    expect(screen.getByText("800x600 PNG")).toBeInTheDocument();
  });

  it("renders delete button", () => {
    render(
      <Wrapper>
        <ClipItem item={textItem} index={0} onSelect={onSelect} onDelete={onDelete} />
      </Wrapper>,
    );
    expect(screen.getByRole("button", { name: "Delete item" })).toBeInTheDocument();
  });
});
