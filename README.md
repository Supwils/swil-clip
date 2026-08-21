# SwilClip

A minimal, keyboard-first clipboard manager for macOS — with a prompt library
for the instructions you reuse every day.

340 pt frosted panel at your cursor. Menu-bar only: no Dock icon, no ⌘Tab entry.
History encrypted at rest; password-manager clipboards are never recorded.

## Two trees, one product

```
swift/    the app. Swift 6, AppKit + SwiftUI, zero dependencies.
tauri/    v0.1.3, frozen. Kept as the record of a technology choice.
```

`tauri/` was the original implementation (Tauri 2 + React + Rust). It is frozen,
not deleted — the reasoning is in
[ADR-0001](docs/adr/0001-freeze-tauri-adopt-swift.md), and `.githooks/pre-push`
still builds and tests it so the archive cannot rot.

Everything below describes the Swift app.

## Build

| Tool | Version |
|------|---------|
| Xcode | 26+ (Swift 6.0+) |
| macOS | 14.0+ to run, 26+ to build |

```bash
cd swift
swift test                        # 220 tests, headless, ~0.15s
bash scripts/bundle.sh            # debug .app → swift/build/SwilClip.app
bash scripts/bundle.sh --release  # universal, Developer ID signed
bash scripts/release.sh           # …plus notarized, stapled, packaged as a .dmg
```

`bundle.sh --release` produces an app that runs here. `release.sh` produces one
that runs on **someone else's** Mac: Gatekeeper refuses an unseen Developer ID
binary unless Apple has notarized it. Both the app and the disk image are
notarized and stapled — the ticket travels with whatever it is attached to, so
the app stays verifiable after it is dragged out of the image on a machine that
happens to be offline.

There is no `.xcodeproj`, on purpose: the build is fully scriptable and
reproducible from a clean checkout, with no IDE state in the repository.

## Usage

Press **⌘⇧V** anywhere. The panel opens at your cursor.

| Key | Clipboard tab | Prompts tab |
|-----|---------------|-------------|
| `↑` `↓` `Home` `End` | navigate | navigate |
| `⌘↑` `⌘↓` | first / last row | first / last row |
| `s` or any letter | search | search (title + body) |
| `⏎` | copy — or paste, with Auto Paste on | same |
| `d` / `p` | delete / pin | delete / pin |
| `e` | expand | preview |
| `u` | undo delete | undo delete |
| `n` | — | new prompt |
| `⇧S` | **save as prompt** | — |
| `⇥` | switch tab (rebindable) | switch tab |
| `esc` | collapse → leave search → close | same |

### You never have to remember a letter

Every action is also reachable with the arrow keys alone.

`←` `→` step through the selected row's buttons — pin, save as prompt, expand,
delete — and `⏎` runs the one you land on. The focused button carries a ring,
and the trash carries a **red** one; while a button is armed the footer stops
showing hints and shows what `⏎` will actually do (`⏎ delete`). Arrow keys are
only safe on a destructive button if the panel says so before you press Return.

`↑` from the first row reaches the bar above the list, which is a band with
stops, not just two tabs:

```
[ Clipboard | Prompts ]  …  +  ⚙
```

`←` `→` walk along it and `⏎` activates the stop. The arrows spend themselves on
switching tabs first, so flipping between the two lists stays one key — and you
cannot land on `+` while looking at the clipboard, where a plus would mean
nothing. `+` and `⚙` are how "new prompt" and "settings" became keyboard-
reachable at all: the first was `n`-only with no button anywhere, the second was
mouse-only.

Reaching an action by arrowing onto its button is not a second implementation of
that action — `⏎` on the trash routes back through the same reducer transition
`d` does, including the part that picks the next selection *before* the row goes
away. `PanelFocusTests` asserts the two paths produce identical state.

### The manual is in the app

Settings has a **Shortcuts** pane listing all 25 ways to drive the panel,
grouped by when you would want them. It is generated from `ShortcutReference`
rather than written out by hand, and `KeyCommand.documentedAction` is an
exhaustive switch — a new key cannot ship undocumented, because the project will
not compile until it has somewhere in that list to live. The two rebindable keys
are substituted from your live settings, so a printed keycap cannot disagree
with the key that works.

### The two tiers

**Clipboard history** is short-term memory: passive, capped, evicted oldest-first.
**Prompts** are the curated tier — manually saved, never evicted, searched by
title and body.

`⇧S` moves an entry from the first to the second. Write a good instruction in a
chat window and it is already in your history; `⌘⇧V`, `⇧S`, and it is in the
library permanently with a title taken from its first line. That action is the
reason both live in one panel.

### Start at login

A clipboard manager that is not running is not failing loudly — it is silently
not recording, and you find out at the next `⌘⇧V`. The toggle is in Settings.

There is no stored preference behind it: `SMAppService.mainApp.status` *is* the
state, read live. A cached `Bool` would drift the moment the login item is
switched off in **System Settings › General › Login Items**, leaving the app
showing "on" and never launching.

### Pinning

Pinned entries sit in a group at the top, above a `RECENT` divider, and never
count toward the history limit.

Unpinning moves the entry to the **top of the unpinned group** rather than back
to its chronological place. Two reasons, and the second is the important one:

1. you unpinned it because you were looking at it, so it should still be under
   your eye afterwards — not several hundred rows down;
2. dropping it back to its real age lands it among the *oldest* unpinned rows,
   where the next few captures evict it. Before this change, unpinning an old
   entry was effectively a **delayed delete**.

If an entry is ever lost, `swift run swilclip-recover --list-missing-pinned`
finds it: the v1 history file is read-only and permanent, so it stays a complete
record of everything captured before the migration.

### Language

中文 / English, switchable in Settings, applied instantly everywhere. Defaults to
following macOS.

Deliberately **not** `.lproj` catalogues: that route follows the *system*
language, and an in-app switch would mean hand-loading a bundle — a known hack
that silently leaks the key onto the screen when a translation is missing. Every
string instead lives on one line as `pick(english, chinese)` in
`SwilClipCore/Localization/Strings.swift`, so a missing translation is a compile
error rather than a blank label.

### Appearance and accent

**Light / dark / system**, applied through `NSApp.appearance` so the panel, both
sheets and the vibrancy material all switch at once with nothing to observe. The
light palette is not an inversion of the dark one — flipping lightness around 50
gives muddy greys and blue-tinted glass, so each value was rewritten for its role
on a light ground.

**The accent is a hue.** Eight presets and a spectrum slider, but only the hue
moves: saturation and brightness stay locked at the ratified values, so any
choice still reads as "this row is selected" rather than as decoration. The
label colour on top of it is derived from WCAG relative luminance rather than
hard-coded white — at one fixed brightness the hue alone swings the accent from
navy to highlighter, and white on lime is unreadable.

**Panel opacity** — sheer / standard / solid — decides how much of the app behind
shows through. macOS exposes no "blur harder" control; `NSVisualEffectView` picks
a *material*, not a radius. What actually keeps text readable over a bright
window is the panel's own tint, and that tint has to sit **on top of** the glass:
underneath it, a `.behindWindow` effect paints its own blurred backdrop and hides
it completely.

### Panel size

Three presets in Settings — Small (340×480, default), Medium (425×600), Large
(510×720). Each scales the **whole** design system, text and spacing together,
not just the window: 340 points is comfortable on a laptop and cramped on a 5K
display. Fonts are scaled by point size rather than `scaleEffect`, so glyphs stay
sharp instead of being resampled.

### Scrolling

The list holds still while the cursor moves inside it, and scrolls only when the
selection comes within two rows of an edge — then by the minimum that restores
that margin. Keyboard scrolling is never animated.

The obvious alternative, re-centring the selected row on every change, means the
whole list slides under a cursor that never moves; every keypress becomes a jolt
and holding a key becomes a smear. See `ScrollAnchoring` in `SwilClipCore`.

### Paste behaviour

**By default `⏎` only copies.** SwilClip writes the pasteboard, hides, and
restores focus to whatever app you came from — then stops. You press `⌘V`
yourself, wherever you actually want it. This needs no Accessibility permission
and can never paste into the wrong field.

**Auto Paste** (Settings) makes `⏎` also synthesise `⌘V`. It requires
Accessibility, and refuses to switch on until the permission is granted rather
than failing silently.

### What gets captured

Text and images, polled every 500 ms. Images are re-encoded to PNG and stored as
encrypted sidecar files rather than inline, so the list never holds payloads it
is not showing.

Each image also gets a **thumbnail** — a few kilobytes, made once at capture and
kept in the row, so a list row can show the picture without loading the picture.
It is a column rather than a second sidecar file, which makes cleanup a property
of the schema: delete or evict the row and the thumbnail goes with it.

**Never captured:** pasteboards marked with the
[nspasteboard.org](http://nspasteboard.org) conventions — `ConcealedType`,
`TransientType`, `AutoGeneratedType`. 1Password, Bitwarden, Apple Passwords and
Keychain Access all set the first, so copied passwords never enter the history.
Encryption at rest is not a reason to record them.

## Security

History and prompts are encrypted **per row** with AES-256-GCM (CryptoKit), each
value under its own nonce. The key is 256 random bits in your login Keychain,
`ThisDeviceOnly`, never synced.

Per-row rather than one blob is the substantive change from v1: a write is O(1)
instead of O(entire history), which is why v2 has none of v1's 50-entry, 10 MB
and 32 MB caps — those existed only to make an O(n) write survivable.

The Keychain read distinguishes "no key yet" from every other failure. A locked
keychain or a denied prompt raises an error; only `errSecItemNotFound` creates a
key. Getting that wrong would orphan the entire history behind a fresh key.

## Migrating from v1

First launch imports `~/Library/Application Support/com.supwilsoft.swilclip/clipboard_history.json`
automatically — entries, timestamps, pins, and your hotkey preference.

The v1 file is **read, never written or deleted**, and stays as your fallback.
v2 uses its own data directory (`SwilClipSwift/`), so the frozen v1 app and this
one cannot touch each other's bytes. If the import fails it aborts without
marking itself done, and retries on the next launch.

macOS will ask once for permission to read the v1 encryption key, because this
binary's signature differs from v1's. Choose **Always Allow**.

## Architecture

```
swift/Sources/
├── SwilClipCore/     pure Swift, no AppKit — the whole test suite runs headless
│   ├── Models/       ClipItem · PromptItem · ContentKind
│   ├── Crypto/       FieldCipher · KeychainKeyStore
│   ├── Database/     SQLite wrapper · Schema · LocalStore
│   ├── Search/       Matcher
│   ├── Selection/    SelectionReducer · PanelFocus · KeyMapping · ShortcutReference
│   ├── Localization/ Strings · AppLanguage · Appearance · AccentPalette
│   └── Migration/    LegacyImporter
└── SwilClip/         AppKit windowing + SwiftUI views
```

Anything decidable without a window lives in `SwilClipCore`. That includes the
entire keyboard model: `NSEvent` is unwrapped in the app target, but *which
command a keypress is* — and what that command does to the selection — are pure
functions with tests.

**Selection has exactly one home.** v1's worst shipped bug deleted the wrong row,
because `cmdk` kept a private copy of the selection and rewrote it outside
React's knowledge. `SelectionReducer` is the answer: views read state and emit
commands, and never write selection themselves.

## Documentation

- [v2 design spec](docs/superpowers/specs/2026-08-20-swift-rewrite-prompt-library-design.md)
- [ADR-0001 — freeze Tauri, adopt Swift](docs/adr/0001-freeze-tauri-adopt-swift.md)
- [ADR-0002 — reopen the prompt library](docs/adr/0002-reopen-prompt-library.md)
- [UI design system](docs/ui-design.md) — "Brushed Quartz", canonical
- [Code review register](docs/code-review.md) — scoped to the frozen `tauri/` tree
- [Swift audit](docs/code-review-swift.md) — an external review of `swift/`, and what came of it
- [Changelog](CHANGELOG.md)
- [Releasing](docs/releasing.md) — signing, notarization, packaging

## License

[MIT](./LICENSE) — © 2026 SUPWILSOFT LLC.
