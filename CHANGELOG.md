# Changelog

## v2.0.0 — 2026-08-21

A complete rewrite in Swift. The Tauri implementation is frozen at v0.1.3 and
kept in `tauri/` as the record of a technology choice
([ADR-0001](docs/adr/0001-freeze-tauri-adopt-swift.md)).

macOS 14+ · universal (arm64 + x86_64) · signed, notarized and stapled.

### The two things that made this a rewrite rather than a refactor

**Selection has exactly one home.** v1's worst shipped bug deleted the wrong row,
because `cmdk` kept a private copy of the selection and rewrote it outside
React's knowledge. `SelectionReducer` is a pure function over a single value;
views read it and emit commands, never write it. The successor to a deleted row
is computed *before* the removal, from the list as rendered.

**Encryption is per row, not per history.** v1 re-encrypted the entire history
blob on every change, which is why it carried a 50-entry cap, a 10 MB per-item
cap and a 32 MB total cap. Those existed only to make an O(n) write survivable.
A write is now O(1) and all three caps are gone.

### Added

- **Prompt library.** A second tab for the instructions you reuse. `⇧S` promotes
  a clipboard entry into it, titled from its first line. Prompts are never
  evicted and are searched by title and body.
- **Arrow-key navigation for everything.** `←` `→` step through a row's buttons
  and `⏎` runs the focused one; `↑` from the first row reaches the top bar, which
  is a band with stops — tabs, `+`, `⚙`. This is what finally gave "new prompt"
  and "settings" a keyboard route. Activating a button routes through the same
  reducer transition its letter shortcut does.
- **中文 / English**, switchable in-app, applied instantly. A missing translation
  is a compile error.
- **Light / dark / system**, plus a **hue-only accent** (eight presets and a
  spectrum slider) and a three-step **panel opacity**.
- **Shortcuts pane in Settings** — all 25 interactions, generated from
  `ShortcutReference` so a new key cannot ship undocumented.
- **Image thumbnails**, stored as an encrypted column so cleanup is a property of
  the schema rather than something a delete path has to remember.
- **Start at login**, reading `SMAppService` live rather than caching a `Bool`.
- **Undo for pin/unpin**, restoring both the flag and the original sort timestamp.
- **Three panel sizes** (340×480 / 425×600 / 510×720), scaling the whole design
  system rather than just the window.
- **`swilclip-recover`** — a rescue tool that reads the permanent, read-only v1
  history file.

### Fixed

- **Unpinning was a delayed delete.** It kept the entry's original timestamp,
  which dropped it among the oldest unpinned rows where the next few captures
  evicted it. It now moves to the top of the unpinned group.
- **Undo lost images.** `delete` removes the sidecar file, and `restore` put back
  only the row — so the entry returned with a `blob_path` pointing at nothing.
  This was v1's SC-05 reappearing by a different mechanism. `restore` now writes
  the sealed sidecar back, and refuses rather than restoring a row that lies
  about having a picture.
- **Changing the summon shortcut did not re-register it**, so the settings field
  showed a new keycap while the old combination kept firing. A shortcut another
  app already owns is now reported under the field instead of only to the console.
- **The menu bar's "Settings…" opened the clipboard panel.**
- **The schema version was stamped outside its migration's transaction.** A crash
  in that gap left a database carrying the new column while claiming the old
  version, and the non-idempotent `ALTER TABLE` then refused to re-run.
- Scroll no longer re-centres the list on pin/unpin; every scroll path is now a
  minimum scroll.
- A row whose ciphertext will not open now says so instead of rendering blank.
- Duplicate detection scans as deep as the configured history rather than a fixed
  200 rows.
- A failed undo returns its entry to the stack instead of consuming it.
- The panel's tint sat *behind* the vibrancy view, where it was invisible — which
  is why a bright window behind the panel bled through it.

### Changed

- Menu-bar only: no Dock icon, no ⌘Tab entry.
- Zero third-party dependencies; no `.xcodeproj` — the build is a shell script.
- The product name lives in exactly one place (`PRODUCT_NAME` in
  `scripts/bundle.sh`), read back at runtime. The bundle identifier and data
  directory are deliberately frozen, because the Keychain ACL is keyed to them.

### Migration

First launch imports the v1 history automatically — entries, timestamps, pins and
your hotkey. The v1 file is read, never written or deleted, and remains your
fallback. If the import fails it aborts without marking itself done and retries
next launch. macOS asks once for permission to read the v1 encryption key,
because this binary's signature differs from v1's.

---

## v0.1.3 and earlier

The Tauri implementation. See the
[GitHub releases](https://github.com/Supwils/swil-clip/releases) for v0.1.0
through v0.1.3, and [`docs/code-review.md`](docs/code-review.md) for the review
register that drove its last few fixes.
