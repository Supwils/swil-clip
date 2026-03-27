import "@testing-library/jest-dom";

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
    onFocusChanged: vi.fn(() => Promise.resolve(() => {})),
    isVisible: vi.fn(() => Promise.resolve(false)),
  })),
}));
