import { render, screen } from "@testing-library/react";
import { ClipboardPanel } from "@/components/ClipboardPanel";
import type { ClipItem } from "@/types/clipboard";
import { PANEL_DRAG_REGION_HEIGHT_PX } from "@/constants";

const items: ClipItem[] = [
  {
    id: "clip-1",
    clipType: "text",
    content: "hello",
    preview: "hello",
    timestamp: 1700000000000,
  },
];

describe("ClipboardPanel", () => {
  it("renders the drag region with data-tauri-drag-region attribute", () => {
    render(
      <ClipboardPanel
        items={items}
        onPaste={vi.fn()}
        onDelete={vi.fn()}
      />,
    );

    const dragRegion = screen.getByLabelText("Drag to move window");
    expect(dragRegion).toBeInTheDocument();
    expect(dragRegion).toHaveAttribute("data-tauri-drag-region");
  });

  it("renders the drag region with the correct height", () => {
    render(
      <ClipboardPanel
        items={items}
        onPaste={vi.fn()}
        onDelete={vi.fn()}
      />,
    );

    const dragRegion = screen.getByLabelText("Drag to move window");
    expect(dragRegion).toHaveStyle({ height: `${PANEL_DRAG_REGION_HEIGHT_PX}px` });
  });
});
