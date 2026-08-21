/**
 * Browser-only UI preview harness.
 *
 * Loaded by main.tsx in dev when the page is opened with `?mockui`
 * (e.g. `pnpm dev` → http://localhost:5173/?mockui). Mocks the Tauri IPC
 * layer with in-memory sample data so the panel renders and mutates outside
 * the native shell — for visual/design review only. Never bundled in
 * production (dead dynamic import behind import.meta.env.DEV).
 */
import { mockIPC, mockWindows } from "@tauri-apps/api/mocks";
import type { ClipItem } from "@/types/clipboard";
import type { AppSettings } from "@/types/settings";

// 8×8 orange PNG — just enough for the image-chip layout.
const SAMPLE_PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGP8z8DwnwEPYMInOXQUAADm+QH5Ynu9swAAAABJRU5ErkJggg==";

const now = Date.now();

// Stress cases: truncation, trailing whitespace, multiline, URL, email,
// JSON, color, code, image, pinned rows, enough items to force scrolling.
let items: ClipItem[] = [
  {
    id: "mock-pin-1",
    clipType: "text",
    content: "https://tauri.app/v2/guides/distribution/sign-macos/",
    preview: "https://tauri.app/v2/guides/distribution/sign-macos/",
    timestamp: now - 1000 * 60 * 60 * 26,
    pinned: true,
  },
  {
    id: "mock-pin-2",
    clipType: "text",
    content: "#FF8C42",
    preview: "#FF8C42",
    timestamp: now - 1000 * 60 * 60 * 50,
    pinned: true,
  },
  {
    id: "mock-1",
    clipType: "text",
    content:
      "A very long single-line preview that absolutely will not fit into three hundred and forty pixels of window width and must truncate gracefully without pushing the right-hand cluster around",
    preview:
      "A very long single-line preview that absolutely will not fit into three hundred and forty pixels of window width and must truncate gracefully without pushing the right-hand cluster around",
    timestamp: now - 1000 * 30,
  },
  {
    id: "mock-2",
    clipType: "text",
    content:
      "Multiline content:\nline two with some detail\nline three\nline four goes on and on beyond the preview cut so the row is expandable",
    preview: "Multiline content:\nline two with some detail\nline three\nline ",
    timestamp: now - 1000 * 60 * 2,
  },
  {
    id: "mock-3",
    clipType: "image",
    content: SAMPLE_PNG,
    preview: "Image (png)",
    timestamp: now - 1000 * 60 * 8,
    imageWidth: 1280,
    imageHeight: 830,
    imageFormat: "png",
  },
  {
    id: "mock-4",
    clipType: "text",
    content: '{"name":"swil-clip","version":"0.1.2","private":true,"scripts":{"dev":"vite"}}',
    preview: '{"name":"swil-clip","version":"0.1.2","private":true,"scripts":{"dev":"vite"}}',
    timestamp: now - 1000 * 60 * 25,
  },
  {
    id: "mock-5",
    clipType: "text",
    content: "supwilsoft@example.com",
    preview: "supwilsoft@example.com",
    timestamp: now - 1000 * 60 * 90,
  },
  {
    id: "mock-6",
    clipType: "text",
    content: "const total = items.reduce((sum, i) => sum + i.value, 0);",
    preview: "const total = items.reduce((sum, i) => sum + i.value, 0);",
    timestamp: now - 1000 * 60 * 60 * 3,
  },
  ...Array.from({ length: 8 }, (_, i) => ({
    id: `mock-filler-${i}`,
    clipType: "text" as const,
    content: `Filler clipboard entry number ${i + 1} to force the list to scroll`,
    preview: `Filler clipboard entry number ${i + 1} to force the list to scroll`,
    timestamp: now - 1000 * 60 * 60 * (5 + i),
  })),
];

let settings: AppSettings = {
  globalShortcut: "cmd+shift+v",
  maxHistory: 50,
  autoPaste: false,
};

function sorted(): ClipItem[] {
  return [...items].sort((a, b) => Number(b.pinned ?? false) - Number(a.pinned ?? false));
}

mockWindows("main");

const params = new URLSearchParams(window.location.search);

// `?mockui&mockerr` renders the history-unavailable error state.
const simulateError = params.has("mockerr");

// `?mockui&mocklatency=25` delays every IPC reply by N ms.
//
// Not cosmetic: resolving instantly makes every post-mutation continuation
// (delete → refresh → re-render) land in one microtask checkpoint, which
// hides an entire class of ordering bug that only appears once the reply
// crosses a real task boundary — most notably the selection-after-delete
// race, where the deleted row must be unselected in the DOM *before* the
// list re-renders. Always reproduce selection/focus bugs with latency on.
const latency = Number(params.get("mocklatency") ?? 0);
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

mockIPC(
  async (cmd, payload) => {
    if (latency > 0) await sleep(latency);
    const args = (payload ?? {}) as Record<string, unknown>;
    switch (cmd) {
      case "get_history":
        if (simulateError) {
          throw "Keychain read failed (errSecAuthFailed); refusing to touch the existing history key";
        }
        return sorted();
      case "get_settings":
        return settings;
      case "delete_item":
        items = items.filter((i) => i.id !== args.id);
        return null;
      case "pin_item":
        items = items.map((i) =>
          i.id === args.id ? { ...i, pinned: args.pinned as boolean } : i,
        );
        return null;
      case "clear_history":
      case "reset_history":
        items = [];
        return null;
      case "clear_unpinned": {
        const removed = items.filter((i) => !i.pinned);
        items = items.filter((i) => i.pinned);
        return removed;
      }
      case "restore_items":
        items = [...(args.items as ClipItem[]), ...items];
        return null;
      case "reorder_items": {
        const order = args.orderedIds as string[];
        const pinnedIds = new Set((args.pinnedIds as string[] | null) ?? []);
        const byId = new Map(items.map((i) => [i.id, i]));
        items = order
          .map((id) => byId.get(id))
          .filter((i): i is ClipItem => Boolean(i))
          .map((i) => ({ ...i, pinned: pinnedIds.has(i.id) }));
        return null;
      }
      case "update_auto_paste":
        settings = { ...settings, autoPaste: args.value as boolean };
        return settings.autoPaste;
      case "update_max_history":
        settings = { ...settings, maxHistory: args.value as number };
        return settings.maxHistory;
      case "update_global_shortcut":
        settings = { ...settings, globalShortcut: args.shortcutStr as string };
        return null;
      case "paste_item":
      case "restore_previous_focus":
        return null;
      default:
        // Window/event plugin calls (hide, listen, …) — succeed silently.
        return null;
    }
  },
  { shouldMockEvents: true },
);

console.info("[devMock] Tauri IPC mocked — UI preview mode");
