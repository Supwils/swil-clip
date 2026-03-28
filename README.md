# SwilClip

A minimal, keyboard-first clipboard manager for macOS. Built with Tauri 2.0 + React + TypeScript.

340px-wide frosted glass panel. Up to 50 entries. Zero dock footprint.

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
| Search | Just type in the search box (auto-focused) |
| Move up / down | Arrow keys `↑` `↓` |
| Paste selected item | `Enter` |
| Quick-paste item 1-9 | `Cmd+1` through `Cmd+9` |
| Dismiss panel | `Esc` or click outside |

When you press `Enter` or use a quick-paste shortcut, SwilClip:
1. Writes the selected content back to the system clipboard
2. Hides the panel
3. Simulates `Cmd+V` to paste into your active app

### System Tray

SwilClip lives in the macOS menu bar. Right-click the tray icon for:
- **Show SwilClip** -- bring up the panel
- **Quit** -- exit the app

### What Gets Captured

SwilClip silently monitors your clipboard in the background (polling every 500ms):
- **Text** -- plain text, code snippets, URLs
- **Images** -- screenshots and copied images (stored as base64, shown as thumbnails)

Duplicate consecutive copies are ignored. History is capped at **50 entries** (oldest evicted first).

## Project Structure

```
src/                    React frontend (components, hooks, types)
src-tauri/              Rust backend (clipboard, store, tray, simulate)
docs/                   Product documentation
```

See [docs/init-doc.md](docs/init-doc.md) for full architecture and feature specs.

## Scripts

| Script | Description |
|--------|-------------|
| `pnpm dev` | Vite dev server only (no Tauri) |
| `pnpm tauri dev` | Full dev mode with Tauri window |
| `pnpm tauri build` | Production build (.app + .dmg) |
| `pnpm typecheck` | TypeScript strict check |
| `pnpm build` | Frontend-only production build |

## Permissions

SwilClip requires **Accessibility** permission on macOS to simulate `Cmd+V` keystrokes. On first paste, macOS will prompt you to grant access in **System Settings > Privacy & Security > Accessibility**.

## Tech Stack

Tauri 2.0 (Rust) / React 19 / Vite 6 / TypeScript (strict) / Tailwind CSS 4 / shadcn/ui (cmdk) / tauri-plugin-store / tauri-plugin-global-shortcut

## Usage

This build has not been notarized by Apple; consequently, it may be blocked upon its initial launch.
If you encounter a "damaged" warning, you can resolve it by executing the following command in the Terminal:

### xattr -cr /Applications/SwilClip.app     check the path

Then, attempt to open the application again.
Note: If you build and install the application yourself directly from the source code using `pnpm tauri build`, you typically will not encounter the "downloaded from the Internet" quarantine issues (though permissions related to Accessibility and similar features may still be required).

本构建未经过 Apple 公证，首次运行可能被拦截。
若提示「已损坏」，可在终端执行：
xattr -cr /Applications/SwilClip.app
请检查路径是否正确, 然后再打开。
或说明：从源码自行 pnpm tauri build 安装通常不会有「从网上下载」的隔离问题（仍可能涉及辅助功能等权限）。

## License

MIT
