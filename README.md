# SwilClip

A minimal, keyboard-first clipboard manager for macOS. Built with Tauri 2.0 + React + TypeScript.

340px-wide frosted glass panel. Menu-bar only — no Dock icon, no ⌘Tab entry.
Encrypted history at rest; password-manager clipboards are never recorded.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 22+ | [nvm](https://github.com/nvm-sh/nvm) |
| pnpm | 10+ | `npm i -g pnpm` |
| Rust | 1.77+ | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Xcode CLT | latest | `xcode-select --install` |

## Quick Start

```bash
# Install dependencies
pnpm install

# Run in development mode (launches Tauri window + Vite HMR)
pnpm tauri dev

# Production build
pnpm tauri build
```

## Usage

### Summon the Panel

Press **Cmd + Shift + V** anywhere on your Mac. The panel appears near your cursor.

### Navigate & Paste

| Action | Shortcut |
|--------|----------|
| Search | Press `s` then type (or click the input) |
| Move up / down | Arrow keys `↑` `↓` (also `Home` / `End`, `Cmd+↑/↓`) |
| Copy / paste selected item | `Enter` (behavior depends on Auto Paste setting — see below) |
| Delete / Pin / Expand | `d` / `p` / `e` |
| Undo last delete | `u` |
| Dismiss panel | `Esc` or click outside |

**Default — `Enter` only copies, doesn't paste.** When you press `Enter`, SwilClip:
1. Writes the selected content to the system clipboard.
2. Hides the panel and **restores focus to whatever app was frontmost when you summoned SwilClip** (e.g. your Terminal input keeps its caret).
3. Stops there — *you* press `⌘V` yourself, wherever you want.

This is the default because it needs no Accessibility permission and never surprises you by pasting into the wrong field.

**Optional — Auto Paste mode.** Open the settings panel (gear icon, top-right) and toggle **Auto Paste** on. With Auto Paste enabled, `Enter` additionally simulates `Cmd+V` after the focus is restored, so the chosen item lands in your original input field in one keystroke.

### System Tray

SwilClip lives in the macOS menu bar. Right-click the tray icon for:
- **Show SwilClip** -- bring up the panel
- **Quit** -- exit the app

### What Gets Captured

SwilClip silently monitors your clipboard in the background (polling every 500ms):
- **Text** -- plain text, code snippets, URLs
- **Images** -- screenshots and copied images (stored as base64, shown as thumbnails)

**Not captured:** pasteboards a password manager marks as concealed. 1Password, Keychain Access
and anything else following the `org.nspasteboard.ConcealedType` convention are skipped outright,
so copied passwords never enter the history.

Duplicate consecutive copies are ignored. History is capped at **50 unpinned entries** by default
(oldest evicted first) — configurable to 100 / 200 / 500 in Settings. **Pinned items never count
toward the cap and are never evicted.**

## Project Structure

```
src/                    React frontend (components, hooks, types)
src-tauri/              Rust backend (clipboard, store, tray, simulate)
docs/                   Product documentation
```

See [docs/init-doc.md](docs/init-doc.md) for full architecture and feature specs, and
[docs/code-review.md](docs/code-review.md) for the open findings register — read its
"standing hazard" section before touching selection, deletion or keyboard navigation.

## Scripts

| Script | Description |
|--------|-------------|
| `pnpm dev` | Vite dev server only (no Tauri) |
| `pnpm tauri dev` | Full dev mode with Tauri window |
| `pnpm tauri build` | Production build (.app + .dmg) |
| `pnpm typecheck` | TypeScript strict check |
| `pnpm build` | Frontend-only production build |

## Permissions

The default (Copy-only) mode needs **no special permission** — SwilClip never sends synthetic keystrokes.

**Accessibility** permission is only required if you enable **Auto Paste** in settings, because Auto Paste simulates `Cmd+V` via `CGEvent`. macOS will prompt you to grant access in **System Settings → Privacy & Security → Accessibility** the first time Auto Paste fires.

## Tech Stack

Tauri 2.0 (Rust) / React 19 / Vite 6 / TypeScript (strict) / Tailwind CSS 4 / shadcn/ui (cmdk) / tauri-plugin-store / tauri-plugin-global-shortcut

## Install

Download the latest `SwilClip_<version>_universal.dmg` from the
[Releases](../../releases) page, open it, and drag **SwilClip** into
**Applications**. The build is signed with a Developer ID and notarized by
Apple, so it opens normally — no Gatekeeper warning, no `xattr` workaround.

On first launch you only need to grant **Accessibility** permission if you turn
on *Auto Paste* (see [Permissions](#permissions) above).

## Releasing (maintainers)

Building the signed & notarized Universal DMG is documented in
[docs/releasing.md](docs/releasing.md). In short, once credentials are in
`.env.release`:

```bash
pnpm release:mac
```

## License

MIT
