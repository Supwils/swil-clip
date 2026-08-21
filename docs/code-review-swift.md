# Swift audit register

Scoped to `swift/`. The Tauri tree has its own register in
[`code-review.md`](./code-review.md) and is frozen.

Format matches the v1 register: each finding gets an ID, a verdict, and — once
closed — the test that keeps it closed. A finding is only closed when something
would fail if it came back.

---

## 2026-08-21 — external review

An independent agent reviewed the tree and reported twelve findings. Every one
was checked against source before anything was changed; the verdicts below are
that check, not the report.

**Eleven were accurate as described. One was half right.** Two further problems
turned up while tracing them.

| ID | Finding | Verdict | Status |
|----|---------|---------|--------|
| SW-01 | Changing the summon shortcut never re-registers it with Carbon | confirmed | fixed |
| SW-02 | Menu bar "Settings…" opens the panel, not settings | confirmed | fixed |
| SW-03 | Image undo restores the row but not its sidecar — SC-05 recurrence | confirmed | fixed |
| SW-04 | Re-order scroll uses the forbidden `anchor: .center` | confirmed | fixed |
| SW-05 | `PRAGMA user_version` committed outside the migration transaction | confirmed | fixed |
| SW-06 | Undo across tabs bypasses the tab handover | confirmed | fixed |
| SW-07 | Selection can dangle after the query re-filters the list | confirmed | fixed |
| SW-08 | Thumbnail seal failure writes an empty blob, blocking backfill | confirmed | fixed |
| SW-09 | A row that fails to decrypt renders blank | confirmed | fixed |
| SW-10 | Hard-coded `cornerRadius: 5` in `PromptRowView` | confirmed | fixed |
| SW-11 | Duplicate detection scans a fixed 200 rows | confirmed | fixed |
| SW-12 | Panel size needs a close/reopen to take effect | **half right** | fixed |
| SW-13 | `AppModel.clearUnpinned` is unreachable | found while checking | removed |
| SW-14 | A failed undo consumes its stack entry | found while checking | fixed |

---

### SW-03 — image undo restores the row but not its sidecar

**The one that mattered.** v1 shipped SC-05: undo reported success while
permanently discarding images. v2 re-created it by a different mechanism.

`delete(id:)` calls `removeBlob` before deleting the row, so the sidecar file is
gone. `restore(_:contents:)` re-inserted the row with its `blob_path` intact and
stopped there. The thumbnail came back — it is a column — so the row *looked*
whole; `imageData` then checked `fileExists` and returned `nil`. Expanding or
pasting produced nothing.

The doc comment on `restore` claimed the opposite: *"the bytes were never deleted
from disk until the row was, so a restore either brings everything back or fails
loudly."* Neither half was true.

**Fixed:** `restore` writes the sealed sidecar back before the transaction, puts
the preview label in the `content` column rather than the image (matching
`recordImage`), and throws `RestoreFailure.missingImageData` rather than
restoring a row that lies about having a picture.

**Closed by** `ImageRestoreTests` — bytes come back, what lands on disk is
ciphertext, the `content` column stays small, and a missing payload throws before
the row is re-inserted.

### SW-12 — the half-right one

The claim was that changing the panel size needs a close and reopen. `show()`
already reconciles the window frame on every presentation, with a comment saying
so, which covers a change made while the panel is closed.

But the size control lives in a sheet attached to the *open* panel, so the common
case is changing it while it is up — and there the content redrew at the new
scale inside the old window. Real, narrower than reported, fixed via
`Settings.onPanelSizeChange`.

---

## What this round says about the codebase

The findings cluster. Ten of fourteen are in the app shell — `AppModel`,
`PanelController`, `main.swift`, the views — and none are in the pure layer that
carries the tests.

That is the predictable shape of a project whose testing strategy is "put
everything decidable without a window into `SwilClipCore`". It works: the
selection reducer, the keyboard model, the crypto and the store were all clean.
What it does not cover is **wiring** — a callback nobody sets, a menu item
pointing at the wrong method, a preference written but never announced. Those
compile, type-check, and do the wrong thing.

Two of them (SW-01, SW-02) had been shipping in a state where the settings screen
told the user something untrue.

The mitigation added to `CLAUDE.md` §9 is a list of the wiring that has already
broken once, and a note to walk any `on*Change` callback by hand after touching
it. That is weaker than a test, and it is honest about being weaker.
