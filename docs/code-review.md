# Code review register

> ### ⚠️ 适用范围：`tauri/`（已冻结于 v0.1.3）
>
> **2026-08-20 起**，本登记册仅描述冻结的 Tauri 实现。见
> [ADR-0001](./adr/0001-freeze-tauri-adopt-swift.md)。
>
> - **SC-05 已修复**（冻结前的最后一次改动）——静默丢数据不能被封存进存档。
> - **其余 open findings 不再修复。** SC-07 / SC-17 / SC-18 由 Swift 重写的
>   存储模型从结构上消解（逐行加密、图片旁挂文件、`source_app` 真填）；
>   SC-06 在 v2 中由 `AXIsProcessTrusted()` 前置校验关闭。
> - 下面的 **Standing hazard 一节仍需通读**：它记录的是 v1 被咬过的那个
>   selection bug，v2 用 `SelectionReducer` 纯函数把它钉死，但**教训本身是承重的**。

**Last full pass:** 2026-08-12, against `18a497c` (v0.1.2) plus the working tree on top of it.
**Scope:** frontend, Rust backend, build and release config.

A living document. When you close a finding, move it to [Closed](#closed) with a one-line note on
what was actually done — the note is the point, not the checkbox. When you decide *not* to fix
something, say so explicitly and why; a deliberate gap and an unnoticed one look identical six
months later.

IDs are stable handles (`SC-nn`) so they can be referenced in commits and issues. They are not a
priority order.

---

## Standing hazard: cmdk keeps its own copy of the selection

Read this before touching selection, deletion or keyboard navigation in `ClipboardPanel`. It is the
root cause of the worst bug found in this pass, and the shape of it invites well-meaning
"simplifications" that bring the bug straight back.

`<Command>` is used in **controlled** mode (`value={selectedId}`). That does not make React the
single source of truth. cmdk 1.1.1 maintains its own `value` in an internal store, and:

- **The highlight renders from cmdk's copy.** `d`, `p` and `e` act on React's copy. Nothing forces
  them to agree.
- **cmdk rewrites its own copy without being asked.** `selectFirstItem()` fires whenever the
  currently-selected `Item` unmounts, jumping the value to row 0. Clicking a row does the same.
- **In controlled mode those writes fire `onValueChange` and return.** They do not round-trip
  through React.
- **cmdk's value-sync effect only re-runs when `props.value` changes.** If React's `selectedId` did
  not change, nothing ever repairs the divergence. It is permanent, not transient.

Shipped 0.1.2 hit all four at once: it migrated the selection *after* awaiting the delete, so across
a real IPC round-trip the list committed — and the row unmounted, still `aria-selected` — before the
migration ran. cmdk took row 0. React still pointed at the successor. The visible symptom was the
cursor snapping to the top; the expensive symptom was that the **next `d` deleted the row React
believed was selected while the user was looking at a different one.**

Three things hold the line now. Removing any one of them reopens the bug:

1. **`handleDelete` migrates the selection with `flushSync` *before* dispatching the delete**, so
   the doomed row is already unselected in the DOM when it unmounts and `selectFirstItem()` never
   triggers. The `flushSync` is load-bearing — plain `setState` lets React batch the migration into
   the same commit as the list update when the backend resolves quickly.
2. **`onValueChange` is wired up.** If cmdk ever moves its own cursor again, React follows, so the
   highlighted row and the keystroke target cannot drift apart. Losing the cursor position is
   recoverable; deleting an unseen row is not.
3. **Selection is keyed by `item.id`**, never by content. cmdk trims item values before writing them
   to `data-value`; an id is whitespace-free, so React state, cmdk's store and the DOM agree by
   construction. (v0.1.1 keyed on `${id}-${preview}` and broke on any preview ending in whitespace,
   which `text.chars().take(200)` produces constantly.)

### Why the test suite could not see it

An IPC mock that resolves in a microtask collapses delete → refresh → re-render into a single commit
and the bug disappears. Every panel-level test passed against the broken code, as did a real-browser
run with the un-delayed mock.

Two pieces of harness exist specifically to stop that from recurring:

- `src/__tests__/deleteSelection.test.tsx` drives the real App → hooks → panel → cmdk stack with an
  `invoke` mock that resolves across a `setTimeout`. Verified red on 0.1.2's logic, green on
  current. **Do not "simplify" the delay out of it.**
- `src/devMock.ts` honours `?mockui&mocklatency=25`, so ordering bugs of this class are reproducible
  by hand in the browser instead of invisible.

---

## Open findings

| ID | Finding | Area |
|----|---------|------|
| [SC-05](#sc-05) | Undo after "Clear" silently loses every image | Data |
| [SC-06](#sc-06) | Auto-paste does nothing without Accessibility permission, and says nothing | UX |
| [SC-07](#sc-07) | Every clipboard change rewrites and re-encrypts the whole history | Performance |
| [SC-08](#sc-08) | Pasting an entry re-records it under a new id | Logic |
| [SC-10](#sc-10) | A corrupt settings value silently resets the global shortcut | Logic |
| [SC-11](#sc-11) | Tray "Show" ignores the saved window position | UX |
| [SC-12](#sc-12) | Content Security Policy is disabled | Hardening |
| [SC-14](#sc-14) | Keyboard navigation is silent to VoiceOver — *deprioritised* | Accessibility |
| [SC-17](#sc-17) | Image dimensions are dead UI — the field is never populated | Dead code |
| [SC-18](#sc-18) | `appName` is carried everywhere and set nowhere | Dead code |

### SC-05
**Undo after "Clear" silently loses every image.**
`useUndoStack.stripImageContent` filters images out of the undo batch to save memory. For a mixed
batch — the normal case for "Clear unpinned" — Undo restores the text entries, reports success, and
drops the images permanently, with no way for the user to know.

*Fix:* keep image entries (bounded by the existing `MAX_UNDO_OPERATIONS` cap), or state the omission
in the Undo affordance. Restoring some of what you deleted while claiming to restore all of it is
the failure mode to avoid.

### SC-06
**Auto-paste does nothing without Accessibility permission, and says nothing.**
`simulate::simulate_cmd_v` posts a synthetic ⌘V, which requires Accessibility access. `CGEvent::post`
returns nothing, so when permission is missing the keystroke is dropped, the command still returns
`Ok`, the panel hides, and nothing is pasted. No permission check, prompt or error exists anywhere.

*Fix:* probe `AXIsProcessTrustedWithOptions` when auto-paste is switched on; if untrusted, keep the
toggle off and point at System Settings → Privacy & Security → Accessibility.

### SC-07
**Every clipboard change rewrites and re-encrypts the whole history.** — *partially addressed; the
architecture is unchanged.*
`store::save_history` serialises the entire item vector, AES-encrypts it and writes the whole blob,
inside the IPC handler, so the frontend waits on it. Cost is O(entire history) on every single
mutation.

**Measured** (`src-tauri/src/persist_cost.rs`, release build, Apple Silicon):

| History | ms per save | blob |
|---|---|---|
| 50 text entries (the default) | **0.7 ms** | 0.05 MB |
| 50 entries, 5 × 2 MB screenshots | **59 ms** | 13 MB |
| 500 cap, 20 × 4 MB screenshots — before the byte budget | **479 ms** | 107 MB |
| the same history, after the byte budget | **167 ms** | 38 MB |

Time is ~90 % encryption; the disk write is ~2 ms and irrelevant. So the shape of the problem is
total *bytes*, not synchronicity — which is why `enforce_byte_budget` (SC-16) bought more than a
background writer would have, at none of the durability risk.

> **Measure this in `--release` or not at all.** A debug build runs AES roughly 30× slower and
> reports 2 s / 16 s for the rows above. Those numbers are an artefact of the profile, not something
> any user experiences, and they will send you rebuilding the persistence layer for no reason.

*Remaining, if the numbers ever justify it:* mutate the cache, return, and let a debounced background
writer coalesce saves — the pattern already used for window-position saves in `lib.rs`. It would
weaken durability from "confirmed before the command returns" to "eventually, plus a flush on exit",
so it needs a flush-on-quit path and a story for surfacing write failures. At 0.7 ms for the default
configuration, that trade is not currently worth making.

### SC-08
**Pasting an entry re-records it under a new id.**
`simulate::write_to_clipboard` does not mark its own writes, so the 500 ms poller sees them as fresh
copies. Dedup removes the original and inserts a clone with a new UUID and timestamp. Moving a
pasted item to the top is reasonable; losing its identity and original age is not, and it re-encodes
the full base64 payload for images.

*Fix:* record the pasteboard `changeCount` at write time and skip that generation in the poller;
promote the existing entry in place instead of re-inserting it.

### SC-10
**A corrupt settings value silently resets the global shortcut.**
`settings::get_settings` does `.and_then(|v| serde_json::from_value(v).ok()).unwrap_or_default()`,
turning any parse failure into defaults. The next save writes those defaults back, so one malformed
field permanently discards the user's shortcut and window position. This is exactly the
overwrite-a-good-value hazard `load_history_from_disk` was carefully written to avoid; the settings
loader did not get the same treatment.

*Fix:* propagate the parse error the way the history loader does, or field-wise merge onto defaults
so one bad key cannot take the rest with it.

### SC-11
**Tray "Show" ignores the saved window position.**
The hotkey path calls `show_window()` first, restoring the saved position or placing the panel at
the cursor. `tray::show_panel` calls `show()` and `set_focus()` directly, so the same app opens in
two different places depending on how it was summoned. Clicking the tray icon while the panel is
open also does not toggle it closed, unlike the hotkey.

*Fix:* route both entry points through one helper that captures the frontmost app, positions, shows
and focuses — and give it the hotkey's toggle behaviour.

### SC-12
**Content Security Policy is disabled.**
`app.security.csp` is `null` in `tauri.conf.json`, switching off Tauri's injected policy entirely.
Nothing in the current UI renders clipboard content as markup, so there is no live exploit — but
this is a webview that ingests arbitrary attacker-influenced text, and the CSP is the layer that
keeps a future rendering mistake from becoming code execution.

*Fix:* `default-src 'self'`, `img-src 'self' data:` for the base64 thumbnails, `style-src 'self'
'unsafe-inline'` for Tailwind's injected styles.

### SC-14
**Keyboard navigation is silent to VoiceOver.** — *Deprioritised by product decision.*
Measured in a real browser: `aria-activedescendant` on the list is `null` at every point — on open,
after four ArrowDowns, after End. The panel deliberately owns navigation rather than delegating to
cmdk, so cmdk's `selectedItemId` (the only thing it feeds that attribute from) is never populated.
The element that actually holds focus, `[cmdk-root]`, carries no `role` at all, so even a correct
value would not be announced.

The bar agreed for this product is that arrow keys, Enter, delete and pin work; screen-reader
announcement is not on the list. Recorded because the roadmap's "零鼠标也能完整使用" pillar reads as
a broader promise than that, so the gap should be a known choice rather than a surprise.

*Fix, if it is ever picked up:* own the ARIA the way the panel already owns navigation — `role="listbox"`,
an `aria-label`, and `aria-activedescendant` pointing at the selected row's DOM id, all on the
focused root, with a stable id on each `ClipItem`.

### SC-17
**Image dimensions are dead UI — the field is never populated.**
`ClipItem.tsx` renders `1280×830 PNG` under the preview when `imageWidth && imageHeight` are set, and
`clipboard/monitor.rs` hardcodes both to `None` for every image, always. The line cannot appear in
the real app. `devMock.ts` supplies fake dimensions, which is why it looks correct in every design
review.

*Fix:* decide whether the metadata earns its place. If yes, read the dimensions off the PNG/TIFF
header at capture. If no, delete the render branch and the two schema fields — they currently cost
bytes in every encrypted write.

### SC-18
**`appName` is carried everywhere and set nowhere.**
The field exists in the Rust struct, the TypeScript type, the serde round-trip test and every
encrypted blob on disk. It is assigned `None` at both capture sites and read by nothing.

*Fix:* the machinery to fill it already exists — `focus_target::frontmost_pid()` knows which app was
frontmost. Either wire it up and show the source app in the row, or drop the field. Carrying a
permanently-empty column through an encrypted store is the worst of both.


---

## Closed

| ID | Finding | What was done |
|----|---------|---------------|
| SC-00 | Delete reset the cursor to the top, and the next `d` deleted the wrong row | Selection keyed by `item.id`; migrated with `flushSync` before dispatch; `onValueChange` wired up. See [the standing hazard](#standing-hazard-cmdk-keeps-its-own-copy-of-the-selection). Guarded by `deleteSelection.test.tsx`. |
| SC-01 | Password-manager clipboard was captured and persisted | The poller collects declared pasteboard types and bails before reading any payload on `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType`. Pure predicate in `clipboard/types.rs`, 6 tests — including one asserting `org.nspasteboard.source` (provenance metadata, not an opt-out) does *not* suppress a clip. |
| SC-02 | Shipped as a regular app — Dock icon and ⌘Tab entry | `set_activation_policy(Accessory)` in `setup`. Confirmed at runtime: `lsappinfo` reports `ApplicationType = UIElement`. Makes the README's "Zero dock footprint" claim true. |
| SC-03 | Panel could open off-screen and become unreachable | Geometry extracted to `window_placement.rs` (pure, 10 tests). Saved positions clamp in physical pixels — the space they were captured in — and the cursor path in logical points, each converting with its own monitor's scale factor. Also fixed CoreGraphics points being fed to `PhysicalPosition`, which doubled every offset on Retina. |
| SC-09 | Pinned items could be evicted by the history cap | The cap now counts *unpinned* entries only; pins are exempt, matching what the Settings copy always promised. `enforce_max_history` retains on the pinned flag instead of truncating blind. 3 tests. Settings copy tightened to "how many unpinned items to keep". |
| SC-13 | Lint failure was blocking `git push` | Agent scratch directories added to ESLint's ignore list (nested `.gitignore` files are invisible to flat config), and the `^_` unused-argument convention the codebase already wrote by hand is now configured. |
| SC-04 | Repeated `d` presses were silently dropped | `useClipboardActions` now QUEUES mutations instead of rejecting re-entrant ones, and `d`/`p` are off the `isBusy` gate. `handleDelete` also tracks in-flight deletes so the successor search never parks the cursor on a row that is already doomed. Browser-verified at 25/40/120 ms latency: 8/8, 6/6 and 12/12 presses land, cursor holds its index. Was 2 of 8. |
| SC-16 | No size cap on captured clips | Per-clip cap (`MAX_CLIP_BYTES`, 10 MB) rejects a clip before it is base64-encoded, so a 79 MB uncompressed-TIFF paste is never allocated. Whole-history budget (`MAX_TOTAL_CONTENT_BYTES`, 32 MB) evicts the oldest unpinned entries, which is what bounds SC-07's worst case. Pinned entries are exempt from eviction but their bytes still count. |
| SC-19 | The push gate did not run the Rust tests | `pnpm prepush` now chains `test:rust` (`cargo test`). Warm, it costs close to nothing; the heavy Tauri/Rust *build* stays excluded on purpose — tests and builds are different cost classes. |
| SC-15 | Every row advertised `⌥N`, which almost certainly did nothing | Badge removed. On macOS, holding Option rewrites `KeyboardEvent.key` to the layout's alternate character (⌥1 → `¡`), so `App.tsx`'s `parseInt(event.key)` handler yielded `NaN` and never fired. Quick paste is not a product priority; a row naming a keystroke it cannot deliver is the part that had to go. **The listener in `App.tsx` still exists and is still unverified** — remove it or move it to `event.code` when convenient. |

---

## Verifying a change in this area

```bash
pnpm prepush                                    # typecheck + lint + vitest
cargo test --manifest-path src-tauri/Cargo.toml # 31 tests
```

For anything touching selection, focus or ordering, that is not sufficient on its own. Drive the
real thing:

```bash
pnpm dev
# then open http://localhost:5199/?mockui&mocklatency=40
```

The latency parameter is the whole point — see [Why the test suite could not see
it](#why-the-test-suite-could-not-see-it). Scenarios worth re-running after any selection change:
delete at the bottom of a scrolled list; delete both pinned rows until the group unmounts; 8 rapid
`d` presses; delete under an active search; clear-then-undo; pin a non-selected row; pin the
selected row. In every final state exactly one row must carry `aria-selected="true"`.
