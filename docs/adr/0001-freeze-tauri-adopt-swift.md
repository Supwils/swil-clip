# ADR-0001 — Freeze the Tauri implementation, rewrite in Swift

**Date:** 2026-08-20 · **Status:** Accepted

## Context

SwilClip v0.1.3 is a Tauri 2 + React + Rust menu-bar clipboard manager. On the
same day, the project's goal was re-scoped away from "a product" to two things:
a tool the author uses daily, and a work sample. See ADR-0002 for that decision's
own reasoning.

Under the old goal, Tauri was defensible: fast to build in, cross-platform
optionality. Under the new goal both justifications collapse.

- The cross-platform option was **never exercised** — the product direction locked
  to macOS-only in May 2026. We paid a WebView's memory and scroll-latency cost
  for an option we had already decided never to take.
- As a work sample, a Rust+WebView clipboard manager competes with Maccy, which
  is native Swift. The comparison is not flattering and the reviewer will make it.
- `docs/code-review.md` records SC-07: every mutation re-encrypts the entire
  history blob. Three separate caps (50 entries, 10 MB per clip, 32 MB total)
  exist solely to make that O(n) tolerable. This is an architectural defect that
  cannot be fixed incrementally — only by changing the storage model.

## Decision

`tauri/` is **frozen at v0.1.3**. `swift/` becomes the only tree that evolves.

- SC-05 (Undo silently discarded images) was fixed *before* the freeze. Freezing
  means "stops evolving", not "sealed with a known data-loss bug".
- The remaining open findings — SC-06, SC-07, SC-08, SC-10, SC-11, SC-12, SC-14,
  SC-17, SC-18 — will **not** be fixed in `tauri/`. Several are resolved
  structurally by the Swift rewrite; the rest are not worth spending on a tree
  nobody will run.
- `tauri/` stays in the repository and stays gated by `.githooks/pre-push`, so
  the archive cannot rot into a state that does not compile.

## Consequences

**Good.** Maintenance bandwidth stays ×1 — the single-maintainer weakness most
likely to kill this project is not amplified. The rewrite is the only opportunity
to fix SC-07 at the root, and it takes SC-17 and SC-18 with it. Keeping `tauri/`
visible is evidence of two technology choices and an articulated reason to
change, which serves the work-sample goal better than deleting it would.

**Bad.** Encryption, notarization, focus restoration and the window-placement
geometry all get reimplemented. Mitigated by porting the *designs* — they were
correct; only the language changes.

**Risk.** A rewrite that stalls half-finished leaves the author on a frozen app.
Mitigated by the M1/M2 split in the spec: the Swift build must fully replace the
Tauri build for clipboard use *before* prompt work begins.
