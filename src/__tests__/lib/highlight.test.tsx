import { render } from "@testing-library/react";
import { renderHighlightedText } from "@/lib/highlight";

describe("renderHighlightedText", () => {
  it("returns raw text when query is empty", () => {
    const { container } = render(<>{renderHighlightedText("hello world", "")}</>);
    expect(container.querySelector("mark")).toBeNull();
    expect(container.textContent).toBe("hello world");
  });

  it("returns raw text when query is undefined", () => {
    const { container } = render(<>{renderHighlightedText("hello", undefined)}</>);
    expect(container.querySelector("mark")).toBeNull();
  });

  it("highlights a contiguous substring match", () => {
    const { container } = render(<>{renderHighlightedText("hello world", "wor")}</>);
    const marks = container.querySelectorAll("mark");
    expect(marks).toHaveLength(1);
    expect(marks[0]!.textContent).toBe("wor");
  });

  it("highlights gapped fuzzy matches", () => {
    const { container } = render(<>{renderHighlightedText("hello world", "hwd")}</>);
    const marks = container.querySelectorAll("mark");
    // h..w..d → three separate marks
    expect(marks.length).toBeGreaterThanOrEqual(3);
    expect(Array.from(marks).map((m) => m.textContent).join("")).toBe("hwd");
  });

  it("is case-insensitive", () => {
    const { container } = render(<>{renderHighlightedText("Hello World", "HEL")}</>);
    const mark = container.querySelector("mark");
    expect(mark?.textContent).toBe("Hel");
  });

  it("returns raw text when no character matches", () => {
    const { container } = render(<>{renderHighlightedText("abc", "xyz")}</>);
    expect(container.querySelector("mark")).toBeNull();
    expect(container.textContent).toBe("abc");
  });

  it("ignores whitespace in query", () => {
    const { container } = render(<>{renderHighlightedText("hello world", "h w")}</>);
    const marks = container.querySelectorAll("mark");
    // "h w" → "hw" — both should match
    expect(Array.from(marks).map((m) => m.textContent).join("")).toBe("hw");
  });
});
