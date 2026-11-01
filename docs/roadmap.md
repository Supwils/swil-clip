# Roadmap — after v2.0.0

The v1 roadmap is archived at [`v1/version-roadmap.md`](./v1/version-roadmap.md).
This file plans the Swift tree only.

Every item below was put through the project's two questions
([ADR-0002](./adr/0002-reopen-prompt-library.md)): **would I actually use it?**
and **is this code worth someone reading?** Items that fail both are in
Non-Goals with the reason, not left implicit.

---

## Where v2.0.0 leaves things

| | lines | tested |
|---|---|---|
| `SwilClipCore` — pure Swift, no AppKit | 3,685 | 219 tests, headless, 0.15s |
| `SwilClip` — the app shell | 4,618 | **nothing** |
| `SwilClipCoreTests` | 2,993 | — |

**Updated 2026-08-21:** 2.1.1 landed, so the shell is now `SwilClipUI` (a library)
plus a seven-line `main.swift`, and `SwilClipUITests` exists. The suite is at 270.

The audit register ([`code-review-swift.md`](./code-review-swift.md)) put
**ten of fourteen findings in the shell** and none in the core. That is not a
coincidence to be noted and moved past — it is the shape of the codebase. The
larger half of the code is the untested half, and it is the half that has
already shipped four user-visible defects (SW-01, SW-02, SW-06, SW-12).

The current mitigation is `CLAUDE.md` §9: a hand-written list of the wiring that
has broken once, and a note to walk any `on*Change` callback by hand. It is
prose where a test belongs. **Closing that gap is this phase.**

---

## Phase 2.1 — put the shell under test

**Why first:** correctness and silent data loss outrank features
(`CLAUDE.md` §0). Everything in this phase is a defect class that has already
occurred at least once.

### 2.1.1 — split the app target · **done** (2026-08-21)

`Sources/SwilClip/main.swift` is top-level code, which is why the shell has no
test target: SPM cannot reliably `@testable import` an executable. The fix is
mechanical:

```
SwilClipUI      (library)     ← everything except main.swift
SwilClip        (executable)  ← main.swift only, depends on SwilClipUI
SwilClipUITests (test target) ← @testable import SwilClipUI
```

`@testable` reaches `internal`, so **no declaration needs to become `public`.**
The only real work is one AppKit seam: `AppModel` imports AppKit for exactly two
calls, both `NSWorkspace.shared.frontmostApplication?.localizedName`. Behind a
`var sourceApp: () -> String?` those disappear and `AppModel` becomes
constructible in a test with a temp store.

Cost: an afternoon, almost all of it moving files. Payoff: the 4,618-line half of
the codebase stops being unreachable.

### 2.1.2 — the wiring manifest test · **done** (2026-11-01)

Landed as `Wiring` (`SwilClipUI/App/Wiring.swift`) and `ShellWiringTests`. The
manifest is found by reflection rather than listed, so a seventh callback is
covered without anyone enrolling it; a mutation run (deleting one wire) fails
the suite. `AppDelegate`'s settings wiring moved into `Wiring.connect` so the
test exercises the same code launch does.

The four shipped wiring bugs share one shape: **a callback nobody set, or set to
the wrong thing.** They compile and type-check. `AppDelegate` and
`PanelController` are the only places that wire, and the set of callbacks is
small and enumerable:

- `Settings.onHotkeyChange` · `onPanelSizeChange` · `onAppearanceChange`
- `AppModel.onDismiss` · `onEditItem` · `onOpenSettings`

Make the manifest a value the tests can assert on, so that adding a seventh
callback without wiring it fails a test rather than shipping. This is the same
trick `ShortcutReference` already plays for the keyboard: the exhaustive `switch`
in `KeyCommand.documentedAction` makes an undocumented key a *compile* error.
The wiring version can't be a compile error, but it can be a test.

Then assert the routing itself: `.newItem` reaches `onEditItem(nil, _)`,
`.openSettings` reaches `onOpenSettings`, `.confirm` reaches `onDismiss`. Three
of the four shipped bugs die here.

### 2.1.3 — the undo stack · **done** (2026-11-01)

Push-after-success landed 2026-08-21. Model-level round trips now cover
collection delete/move, pin, and the inline edit of a clip and of an entry.

`AppModel.undoStack` is the largest untested data-loss surface left. The store
half is covered (`ImageRestoreTests`, the pin round-trip); the stack that decides
*what* to hand it is not, and SW-14 lived there.

Two things to do:

- Test the round trip at the model level for all three operations —
  `deletedClips` (text and image), `deletedEntries`, `deletedCollection`,
  `pinChanged` — including
  the cross-tab handover, which is the path SW-06 broke.
- **Push the undo entry only after the operation succeeds.** Today `delete` and
  `togglePin` push first and act second. `INSERT OR REPLACE` keeps this from
  corrupting anything, so it is not a live bug — but it means a failed delete
  leaves an entry whose undo is a silent no-op, spending the user's `u` on
  nothing. Cheap to fix, and the fix is obviously right.

### 2.1.4 — `Settings` persistence round trip · **done** (2026-11-01)

`SettingsPersistenceTests`: every preference written, then read by a fresh
instance; plus the empty-domain defaults.

Every preference is a `UserDefaults` key written by hand. A typo in a key name is
invisible until a restart loses the setting. One table-driven test against a
scratch suite covers all of them, and it costs about thirty lines.

**Done when:** the shell has a test target, the six callbacks are asserted, the
undo stack round-trips in tests, and `CLAUDE.md` §9 can be shortened from a
warning to a pointer at the tests that enforce it.

---

## Phase 2.2 — daily-use wear

Things that fail question ② (nobody reads a codebase to admire these) but pass
question ① hard, because they are friction I hit every day.

| Item | Note |
|---|---|
| ~~Arrow-scroll inside an expanded row~~ | **Done 2026-11-01.** `⇧↑` / `⇧↓` scroll the open row three lines at a time and fall back to plain arrows when nothing is open. Plain arrows were rejected: making them scroll first would put scroll offset — view state — into the reducer. |
| ~~`⇥` between Title and Prompt in the editor~~ | **Done 2026-08-21.** The collection picker made a third field, and a control the keyboard cannot reach is a control that does not exist. |
| ~~`e` opens the editor on the Prompts tab~~ | **Closed 2026-11-01, not by changing `e`.** `⇧E` edits any text row in place, on both tabs, so the shipped key keeps its meaning. |
| ~~Built-in backups~~ | **Done 2026-11-01.** Five hand-made `SwilClipSwift.backup-*` folders said the need was real. `VACUUM INTO` plus the sidecars, daily at launch, newest seven kept, and a button in Settings. |

---

## Phase 2.3 — the rename

Infrastructure is done: the user-visible name lives in exactly one place
(`PRODUCT_NAME` in `swift/scripts/bundle.sh`) and the bundle identifier and data
directory are frozen independently of it (`CLAUDE.md` §7). Renaming is one line
plus a rebuild.

Deliberately not scheduled — it is a decision, not work, and it is not blocking
anything. **Attic** is the current front-runner.

---

## Non-Goals (v2)

Carried forward from v1 and still closed: `{{variables}}`, tags, folders, sync,
cross-platform, AI features.

Newly recorded:

- **A Dock icon toggle.** Asked about after v2.0.0 shipped menu-bar-only.
  `.regular` activation policy makes the app a real foreground app, which breaks
  the focus restoration the whole paste flow depends on — `FocusTarget` restores
  the previously frontmost app, and with a Dock icon the panel *is* the
  frontmost app. Menu-bar-only isn't a default, it's the design.
- **Anything in `tauri/`.** Frozen at v0.1.3 ([ADR-0001](./adr/0001-freeze-tauri-adopt-swift.md)).
  It stays in the repo as the record of two technology choices, not as code.

---

## Order, and why

1. **2.1** — the only phase that is about the codebase being wrong rather than
   incomplete. Everything after it is safer for having happened.
2. **2.2** — real daily friction, but none of it loses data or lies to the user.
3. **2.3** — a decision, unblocked and unblocking.
