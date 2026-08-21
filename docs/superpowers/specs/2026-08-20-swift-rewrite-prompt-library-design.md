# SwilClip v2 — Swift rewrite + Prompt library

**Status:** Approved 2026-08-20. Supersedes the Tauri implementation, which is
frozen at v0.1.3.
**Decisions recorded in:** [ADR-0001](../../adr/0001-freeze-tauri-adopt-swift.md),
[ADR-0002](../../adr/0002-reopen-prompt-library.md)

---

## 1. Why this exists

SwilClip's goal was re-scoped on 2026-08-20 to two things, and only two:

- **(a) a tool the author uses every day**, tuned entirely to their own hand;
- **(b) a work sample** that demonstrates end-to-end delivery.

Product-market ambitions are explicitly out. The category is settled — Maccy has
21k stars and six years of goodwill, and a direct paid competitor (CleanClip)
grossed $3,775 over nine months. Nothing in this document is an attempt to
compete; every decision below optimises for (a) and (b).

Two consequences follow, and they drive the whole design:

1. **Code quality is the deliverable**, not feature count. A defect a reviewer
   would catch outranks a feature a user might like.
2. **The old "would users leave for Maccy?" filter is dead.** The replacement is
   two questions: *would I actually use this?* and *is this code worth reading?*

## 2. What changes

| | v1 (frozen) | v2 |
|---|---|---|
| Stack | Tauri 2 + React 19 + TS + Rust | Swift 6, AppKit + SwiftUI, zero dependencies |
| Storage | one JSON blob, AES-GCM re-encrypted whole on every mutation | SQLite, per-row AES-GCM |
| Write cost | O(entire history) — 167 ms at 500 entries w/ images | O(1) |
| Caps | 50 entries · 10 MB/clip · 32 MB total | none needed (see §5.3) |
| Images | base64 inside the blob | encrypted sidecar files, path in DB |
| Content | clipboard history | clipboard history **+ prompt library** |
| Selection | cmdk's, plus a second copy in React | one pure reducer, single source of truth |

## 3. Repository layout

```
swil-clip/
├── swift/                    the active app
│   ├── Package.swift
│   ├── Sources/
│   │   ├── SwilClipCore/     pure Swift — no AppKit, fully testable headless
│   │   └── SwilClip/         app target — AppKit windowing + SwiftUI views
│   ├── Tests/SwilClipCoreTests/
│   └── scripts/              bundle assembly, sign, notarize
├── tauri/                    frozen at v0.1.3, still gated by pre-push
├── docs/
└── .githooks/pre-push        gates both trees
```

`tauri/` stays in the repository on purpose. It is evidence of two technology
choices and an articulated reason for changing — which serves (b) better than a
deleted directory would.

## 4. Swift architecture

### 4.1 Toolchain and targets

| Concern | Choice | Reason |
|---|---|---|
| Language | Swift 6.3, **Swift 6 language mode** | Full strict-concurrency checking; data races become compile errors |
| Deployment target | **macOS 14.0** | Not 26.0: (b) requires a reviewer to be able to run it. 14.0 still has `@Observable`, `MenuBarExtra`, `onKeyPress` |
| Build system | **SPM only, no `.xcodeproj`** | The build is fully scriptable and reproducible from a clean checkout; no IDE state in the repo. The `.app` bundle is assembled by `scripts/bundle.sh` |
| Third-party deps | **none** | See §4.2 |
| Font | **system (SF Pro)** | See §4.3 |

### 4.2 Zero dependencies — a deliberate reversal

The approved design named GRDB.swift and `sindresorhus/KeyboardShortcuts`. Both
were dropped during spec-writing. The reasoning, recorded because it contradicts
the approved design:

- **SQLite:** the schema is two tables and roughly ten queries. A typed wrapper
  over the system `libsqlite3` is ~250 lines, lets us hold prepared statements
  for the hot paths ourselves, and removes a dependency-resolution step from
  every clean build.
- **Global hotkey:** `KeyboardShortcuts` is a wrapper over Carbon's
  `RegisterEventHotKey`, which remains the only mechanism Apple offers. Calling
  it directly is ~90 lines and avoids taking a dependency to skip them.

The trade is real: we own the bugs GRDB would have owned. It is accepted because
the surface is small, it is unit-tested, and for (b) a persistence layer that was
written and tested reads better than one that was imported.

### 4.3 Typography — a justified deviation from the design system

`docs/ui-design.md` §5.7 specifies Geist. The v2 app uses **SF Pro, the system
font**, because:

- Geist was a web-era workaround: the WebView had no ergonomic access to SF at
  variable weights. A native app does.
- The design system's own stated reference points are **Spotlight and Raycast**,
  both of which use SF Pro. Using it moves *toward* the intent, not away.
- It satisfies §5.7's actual purpose (no CDN fetches, works offline) with
  *fewer* fonts and no bundled asset or font-registration code.

Every other token in `docs/ui-design.md` — the six-step luminance scale, the
12/10/2 pt spatial system, the ratified 11.5 pt row text and 66 pt action
reservation in §7 — ports verbatim into `Design/Tokens.swift`.

### 4.4 Module boundaries

```
SwilClipCore                      pure Swift · no AppKit · headless-testable
├── Models/       ClipItem, PromptItem, ContentKind
├── Crypto/       FieldCipher (AES-GCM), KeychainKeyStore
├── Database/     SQLite (thin typed wrapper), Schema, ClipStore, PromptStore
├── Search/       Matcher                       (pure)
├── Selection/    SelectionReducer, KeyCommand  (pure)
└── Migration/    LegacyImporter

SwilClip                          app target
├── Panel/        FloatingPanel (NSPanel), PanelController, WindowPlacement
├── Hotkey/       GlobalHotkey (Carbon)
├── Clipboard/    PasteboardMonitor, PasteSimulator
├── Focus/        FocusTarget
├── Design/       Tokens, Components
├── Views/        PanelRoot, ClipboardTab, PromptTab, rows, editor, settings
├── State/        AppModel (@Observable), Settings
└── StatusItem/   StatusItemController
```

The split is the point: **everything decidable without a window lives in
`SwilClipCore`** and is tested without launching an app. The app target holds
only the parts that genuinely need AppKit.

### 4.5 The selection reducer

v1's worst shipped bug — pressing `d` deleted the wrong row — happened because
cmdk kept a private copy of the selection and rewrote it on unmount, outside
React. `CLAUDE.md` still carries a standing hazard note about it.

v2 has no cmdk, so that specific mechanism is gone. But *"the framework won't do
it to us any more"* is luck, not architecture. So:

- Selection lives in exactly one place: `SelectionReducer.State`.
- Every keystroke becomes a `KeyCommand` and goes through
  `SelectionReducer.reduce(state:command:items:) -> State`. A pure function.
- Mutations (delete, filter change) resolve the next selection **inside the
  reducer**, so "what is selected after this delete" is a unit test, not a
  runtime race.
- Views read state and emit commands. They never write selection.

This is the single most important structural decision in the rewrite, and the
one §7's tests protect hardest.

## 5. Data layer

### 5.1 Schema

```sql
CREATE TABLE clip (
  id          TEXT PRIMARY KEY,
  kind        TEXT    NOT NULL,          -- 'text' | 'image'
  content     BLOB    NOT NULL,          -- AES-GCM sealed; per-row nonce
  preview     BLOB    NOT NULL,          -- sealed, first ~200 chars
  blob_path   TEXT,                      -- images: sidecar file, not base64
  width       INTEGER,
  height      INTEGER,
  source_app  TEXT,
  is_pinned   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);
CREATE INDEX idx_clip_created ON clip(is_pinned DESC, created_at DESC);

CREATE TABLE prompt (
  id          TEXT PRIMARY KEY,
  title       BLOB    NOT NULL,          -- sealed
  body        BLOB    NOT NULL,          -- sealed
  is_pinned   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
```

### 5.2 Encryption

Per-row `AES.GCM` via CryptoKit, one fresh nonce per sealed value. The key is a
256-bit random value in the login Keychain, read once per process and cached —
carrying over v1's `crypto.rs` design, which was correct.

v1's rekey-on-error hazard is carried over too: **the only read outcome that
means "no key exists" is `errSecItemNotFound`.** Every other error (locked
keychain, denied prompt, ACL mismatch) must propagate, never generate a new key.
Generating one on a transient failure orphans the entire history.

### 5.3 What this deletes

Per-row encryption makes a write O(1) instead of O(entire history). The three
limits that existed only to make O(n) tolerable are removed:

- the 50/100/200/500 entry cap becomes a user preference, not a safety valve;
- the 10 MB single-clip rejection is gone;
- the 32 MB total-content eviction is gone.

`preview` is stored as its own sealed column so drawing a row never decrypts a
2 MB image payload. **List rendering cost is decoupled from blob size** — the
second lesson from SC-07.

Images become sidecar files under `blobs/<id>`, sealed with the same key. This
also resolves SC-17 honestly: writing the file requires reading the image header,
so `width`/`height` finally hold real values instead of being permanently null.
`source_app` is populated from `FocusTarget` (SC-18) — a column that is always
null does not get to exist.

### 5.4 Migration from v1

On first launch, if `~/Library/Application Support/com.supwilsoft.swilclip/clipboard_history.json`
exists and the v2 database is empty:

1. read the **same** Keychain entry (`com.supwilsoft.swilclip` /
   `history-encryption-key-v1`);
2. base64-decode the `history_enc` key and open it. v1's Rust blob layout is
   `nonce‖ciphertext‖tag`, which is byte-identical to CryptoKit's `combined`
   representation, so no re-framing is needed;
3. decode the item array (`clipType`, `content`, `preview`, `timestamp`,
   `pinned`, `appName`, `image*` — camelCase, per serde);
4. insert row by row into the v2 database, re-sealing per row;
5. carry the `settings` key across too, so the user's hotkey survives;
6. record a `migrated_at` marker so it never runs twice.

**The v1 file is read, never written or deleted.** It stays as the fallback.

> **Data-directory separation is mandatory.** v2 uses
> `~/Library/Application Support/SwilClipSwift/`. The frozen v1 app and v2 will
> be installed side by side during the transition, and v1 dev builds already
> share a directory with v1 release builds — a known property of this project.
> Sharing a third way would let a frozen app corrupt live data.

## 6. Interaction model

Tab-switched dual panel. Each tab owns an independent selection and search state.

| Key | Clipboard tab | Prompt tab |
|---|---|---|
| `↑` `↓` `Home` `End` | navigate | navigate |
| `s` | enter search | enter search (title + body) |
| `⏎` | copy — or paste, if Auto Paste is on | same |
| `d` / `p` | delete / pin | delete / pin |
| `e` | expand | open editor |
| `u` | undo delete | undo delete |
| `n` | — | new prompt |
| `⇧S` | **save as prompt** | — |
| `Tab` | switch tab | switch tab |
| `Esc` | dismiss | dismiss |

### 6.1 `⇧S` is the reason the two live in one app

Write a good instruction in a chat window, and it is already in clipboard
history. `⌘⇧V`, `⇧S`, and it is in the library permanently, with a title derived
from its first line.

This action cannot exist if clipboard and prompts are separate apps. It is the
whole argument for the merge — and it fills the gap the v1 Non-Goals left when
they rejected folders and tags: prompts are the long-lived tier, history stays
the short-term tier, and promotion between them is one keystroke.

### 6.2 Prompt shape

`title` + `body`. **No `{{variables}}`, no tags.** On save, the title is proposed
from the body's first line (~20 chars) with the cursor placed on it; `⏎` accepts.
Recording friction is close to zero, and the list is still scannable — which
matters, because every prompt in the author's real corpus starts with "请…".

Variables were specified in the 2026-05-28 draft and are deliberately not built:
nothing in the real corpus uses them. The schema does not preclude adding them.

### 6.3 Focus and paste

Unchanged from v1, because v1's design was right and needed no Accessibility
permission by default:

1. record the frontmost application **before** showing the panel;
2. show; the panel takes key status;
3. on `⏎`: write the pasteboard, hide, re-activate the recorded app;
4. **only if Auto Paste is enabled**, synthesise `⌘V` via `CGEvent`.

Auto Paste probes `AXIsProcessTrusted()` when switched on and refuses to enable
itself while untrusted, pointing at System Settings — closing SC-06, which in v1
failed silently and still returned success.

## 7. Testing

`SwilClipCore` links no AppKit, so the whole suite runs headless.

| Suite | What it protects |
|---|---|
| `SelectionReducerTests` | the v1 delete-wrong-row bug class, permanently |
| `FieldCipherTests` | seal/open round-trip; tampered ciphertext rejected; wrong key rejected |
| `KeychainKeyStoreTests` | **only `errSecItemNotFound` creates a key** |
| `ClipStoreTests` / `PromptStoreTests` | CRUD, pin ordering, dedup, eviction |
| `MatcherTests` | CJK + Latin, case folding, substring |
| `LegacyImporterTests` | a real v1 `history.json` fixture, asserted row by row |
| `ContentKindTests` | url / email / color / json / code detection |

`LegacyImporterTests` is the highest-stakes suite: migration runs once, and a bug
there is unrecoverable data loss.

Carried over from `CLAUDE.md`: **async store tests keep real timing gaps.**
Collapsing them to microtask-level mocks is what hid the v1 selection bug for
months.

## 8. Milestones

**M1 — clipboard only, in daily use, replacing the Tauri build.**

1. `swift/` skeleton · `FieldCipher` · `KeychainKeyStore`
2. `SQLite` wrapper · `Schema` · `ClipStore` · `LegacyImporter` (+ tests)
3. `FloatingPanel` · cursor placement · vibrancy · `LSUIElement`
4. `PasteboardMonitor` · `SelectionReducer` · clipboard tab UI
5. `FocusTarget` · `PasteSimulator` · Auto Paste gate
6. Settings · `GlobalHotkey` · status item
7. bundle · sign · notarize · install

**M2 — prompt library.** `PromptStore`, prompt tab, editor, `⇧S` promotion.

M1 ships before M2 starts. If prompts came first the author would run two apps at
once, dogfooding would never begin, and the clipboard half would stall at
"works" instead of reaching "good" — the exact failure mode this project was
warned about.

## 9. Out of scope

Unchanged from the v1 Non-Goals except where ADR-0002 reopens them: no sync, no
cross-platform, no AI features, no rich text, no chained pasting. Prompt library
and its long-lived storage tier are reopened. `{{variables}}`, tags and folders
remain closed.
