import "@testing-library/jest-dom";

class ResizeObserverMock {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}

vi.stubGlobal("ResizeObserver", ResizeObserverMock);
Element.prototype.scrollIntoView = vi.fn();

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

vi.mock("@tauri-apps/api/event", () => ({
  listen: vi.fn(() => Promise.resolve(() => {})),
}));

vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: vi.fn(() => ({
    hide: vi.fn(),
    show: vi.fn(),
    setFocus: vi.fn(),
    startDragging: vi.fn(() => Promise.resolve()),
    onFocusChanged: vi.fn(() => Promise.resolve(() => {})),
    isVisible: vi.fn(() => Promise.resolve(false)),
  })),
}));
