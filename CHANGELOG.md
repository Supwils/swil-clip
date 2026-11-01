# Changelog

## v2.1.0 — unreleased

### Collections

**Prompts was never a second tab. It was the first collection.** The panel's
hard-coded Clipboard/Prompts pair is now Clipboard plus an ordered list of
user-managed collections, all equal to each other
([design](docs/design-collections.md)).

- **User-defined tabs.** Up to five collections beside Clipboard, each with a
  name, a glyph and a position. Create, rename, re-icon, reorder and delete them
  in Settings → Collections. The migration seeds `Prompts` and `Personal`, and
  then forgets it did: there is no built-in flag, so those two obey exactly the
  same rules as one you make tomorrow.
- **`⇧⇥` walks back through the tabs**, and `⇥` now wraps. `←`/`→` on the top bar
  still spend themselves on the tabs before reaching `＋` and `⚙`, and they
  deliberately do *not* wrap — they have somewhere else to go.
- **`⇧S` saves into the first collection**, whichever that is. No preference key
  behind it: the order is drawn across the top bar, so to change the target you
  move that collection to the front. The footer names the destination.
- **The editor gained a collection picker**, which doubles as the only "move
  between collections" affordance — and `⇥` now cycles Title → Body → Collection,
  so the editor is no longer the one place in the app that needed the mouse.
- **The top bar degrades instead of clipping.** Icon + name + count while it
  fits; then inactive counts go, then inactive names. The active tab never
  degrades.
- **Deleting a collection asks rather than guesses**, offering "move its entries"
  before "delete them too", and the whole operation is one undo step.

### Inline editing

- **`⇧E` edits a row where it stands.** The expansion turns into a text box —
  clipboard text, or a collection entry's body — with `⌘⏎` to save and `⎋` to
  discard; the expanded row also grows an "Edit" link for the mouse. Images
  and unreadable rows decline.
- **An edit is not a copy.** A clip keeps its id and its place in the history,
  and `u` puts the previous text back exactly.
- **The draft is modal and durable.** While it is open no key or click can move
  the selection, and closing the panel mid-edit keeps the draft for next time.

### Backups

- **The app backs itself up.** Once a day at launch, and on demand from
  Settings → Backups: `VACUUM INTO` a consistent snapshot plus the image
  sidecars, newest seven kept, in `SwilClipSwift/Backups/`. Copying the folder
  by hand could capture a database that never existed, because WAL keeps the
  newest writes in a separate file.
- Snapshots are encrypted exactly like the live data, so they open only on a
  Mac holding the same Keychain key. Folders you put there yourself are never
  rotated away.

### Reading long entries

- **`⇧↑` / `⇧↓` scroll an expanded row** three lines at a time. With nothing
  expanded they are plain arrows, so holding `⇧` never freezes the list.

### Internal

- **The app shell is testable.** `SwilClipUI` is now a library target and
  `SwilClip` is `main.swift` alone, so `@testable import` reaches the 4,600 lines
  that previously had no tests (roadmap 2.1.1). `AppModel` no longer imports
  AppKit: the frontmost-app lookup is injected.
- Undo entries are pushed *after* the write succeeds, so a failed delete or pin
  no longer spends the user's `u` on a no-op (roadmap 2.1.3).
- **The shell's callbacks are a tested manifest** (roadmap 2.1.2). `Wiring`
  finds every `on…` callback by reflection, so one added without being wired
  fails `ShellWiringTests` — nobody has to remember to enrol it.
- Every preference round-trips through a fresh `Settings` (roadmap 2.1.4).
- Bundles carry the commit they were built from: `CFBundleVersion` is the
  commit count, and the Settings footer shows the short hash.
- The `AppModel` test fixture keeps its scratch preferences inside its temp
  directory. A bare suite name left one `swilclip-tests-*.plist` in
  `~/Library/Preferences` per test, written by cfprefsd after teardown.
- Schema v3 adds the `collection` table and `prompt.collection_id`, seeded inside
  the same transaction as the DDL.


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
through v0.1.3, and [`docs/v1/code-review.md`](docs/v1/code-review.md) for the review
register that drove its last few fixes.
