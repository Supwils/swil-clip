# Design — Collections

**Date:** 2026-08-21 · **Status:** Implemented
**Plan:** [`plan-collections.md`](./plan-collections.md)
**Supersedes:** nothing. **Extends:** [ADR-0002](./adr/0002-reopen-prompt-library.md)
**Schedules against:** [roadmap.md](./roadmap.md) Phase 2.1 / 2.2

---

## The claim

**Prompts was never a second tab. It was the first collection.**

The panel currently hard-codes "there is exactly one library, and it is called
Prompts". This design deletes that hard-coding. What is left is one built-in
concept — Clipboard — and an ordered list of collections that are all equal to
each other.

This is a subtraction, not a layer. The count of special cases in the codebase
goes *down*.

---

## What forced this

The author keeps personal constants — a GitHub URL, project URLs, an email
signature — in clipboard history, and reaches them by scrolling. History is a
tier that evicts and that nothing curates; using it as storage is using it
against its design. ADR-0002 already answered this once for prompts:

> when folders and tags were rejected, "important things get evicted by the
> 50-entry cap" was left with no answer. A separate long-lived tier is that
> answer, without organising history.

The same answer, one more time, is a *second* long-lived tier. And the moment
there are two, "long-lived tier" is a category with more than one member — which
means it should be data, not a Swift enum case.

### Both project questions pass

1. **Would I actually use it?** Observed behaviour, not a hypothesised need:
   the URLs are already being retrieved by scrolling history today.
2. **Is the code worth reading?** Generalising a 2-case enum that
   `SelectionReducer`, `PanelFocus`, `AppModel.undoStack` and the tab handover
   all sit on — without breaking the invariants that keep v1's delete-wrong-row
   bug dead — is a better work sample than a third storage tier bolted on beside
   the second.

### What is still closed

`{{variables}}`, tags, folders, sync, cross-platform, AI. A collection is not a
folder: folders organise *history*, which stays a flat evicting log. Collections
are separate curated tiers with their own lifecycle, which is exactly the shape
ADR-0002 accepted.

**Plugins are closed too**, and this is worth writing down because it was asked
for by name. An extension mechanism fails both questions: the author will not
write plugins for their own tool, and "plugin framework for a single-user
utility" reads as over-engineering in a portfolio, not as capability. Every
behaviour a plugin would have configured is instead *the same for every
collection*, which is the point of the equality model below.

---

## 1. The equality model

There is exactly one special tab, and its specialness is real:

| | Clipboard | A collection |
|---|---|---|
| table | `clip` | `prompt` |
| written by | the pasteboard poller | the user |
| evicted | yes, at `historyLimit` | never |
| editable | **no** | yes |
| position | always first, not reorderable | user-ordered |
| deletable | no | yes |

Everything that is *not* Clipboard is a row in the `collection` table, and every
such row obeys identical rules. There is **no `is_builtin` flag.**

Migration seeds two ordinary collections — `Prompts` and `Personal` — and then
forgets it did so. They can be renamed, re-iconed, reordered and deleted exactly
like one the user creates tomorrow.

### Why no built-in flag

An earlier draft of this design gave built-ins a flag and a nullable `name`, so
that an unrenamed built-in could take its name from `Strings` and follow the
language switch. It was clever and it was wrong:

- It is a mechanism built for two rows.
- It creates a state distinction the user cannot see — *have I renamed this?* —
  and this codebase spent v1's worst bug and SW-06 on invisible second sources
  of truth.
- It grows. Can a built-in be re-iconed? Reordered ahead of Clipboard? Restored
  after deletion? The flag needs an answer to each. The equality model answers
  all of them with one sentence: *same as any other collection.*
- Most of all it fails to deliver the claim. Code carrying `is_builtin = 1` on
  Prompts is code still asserting Prompts is special.

**Cost accepted:** seeded names do not follow a later language switch. They are
written once, in whatever language the app is in when the migration runs, and
they are user data from that moment on. Renaming is two seconds in Settings.

---

## 2. Data model

### Schema v3

`Schema.current` goes 2 → 3. The migration and its `PRAGMA user_version` stamp
go inside the same `transaction { }`, per the rule at the top of `Schema.swift` —
a stamp outside the transaction leaves a database carrying v3's column while
claiming v2, and `ALTER TABLE` is not idempotent.

```sql
CREATE TABLE collection (
  id         TEXT PRIMARY KEY,
  name       BLOB    NOT NULL,   -- sealed
  symbol     TEXT    NOT NULL,
  position   INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

ALTER TABLE prompt ADD COLUMN collection_id TEXT NOT NULL DEFAULT 'prompts';

CREATE INDEX IF NOT EXISTS idx_prompt_collection
  ON prompt(collection_id, is_pinned DESC, updated_at DESC);
```

Then seed:

```sql
INSERT INTO collection VALUES ('prompts',  <sealed name>, 'text.quote', 0, <now>);
INSERT INTO collection VALUES ('personal', <sealed name>, 'person',     1, <now>);
```

Existing prompt rows land in `prompts` by the column default. No data moves.

**`name` is sealed** for the same reason prompt titles are: a collection called
"Acme interview loop" is as disclosing as its contents. A name that fails to
decrypt renders as `—` and the tab is marked unreadable — same treatment as
`ClipItem.isUnreadable`, and for the same reason: a blank tab looks like the app
lost something.

**`symbol` is not sealed.** It is not sensitive and it comes from a fixed
picker.

**`position` is a dense 0..n-1 integer**, rewritten wholesale on reorder. With a
hard cap of five collections there is no case for fractional indexing.

### Seed names cross the Core boundary as parameters

`SwilClipCore` must not import AppKit and does not know the UI language, so the
names are passed in:

```swift
LocalStore(locations:key:seedNames: Schema.SeedNames)
```

`AppDelegate` already builds `Settings` before `LocalStore` (`main.swift:22`
vs. `:33`), so `settings.strings.promptsTab` / `.personalTab` are available at
that point. Core stays pure and the seeding is testable with fixed strings.

### The table keeps its name

The SQL table stays `prompt`. Renaming it would be a data-moving migration for
a nicer identifier, and the first rule in `Schema.swift` is that shipped
migrations are append-only.

The **Swift type** does rename: `PromptItem` → `LibraryEntry`, plus
`collectionID: String`. That is a pure-Swift rename with no data risk, and it
stops the code from calling a GitHub URL a "prompt". The mismatch between table
name and type name gets one comment saying the file format is frozen history and
the type name is current intent.

### New Core types

```swift
public struct LibraryCollection: Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var symbol: CollectionSymbol
    public var position: Int
    public let createdAt: Date
    public var isUnreadable: Bool
}

/// A closed set, so an unknown value from a corrupted row degrades to
/// `.textQuote` instead of drawing nothing. Precedent: `ShortcutEntry.symbol`
/// already stores an SF Symbol name in Core, with the same justification.
public enum CollectionSymbol: String, CaseIterable, Sendable {
    case textQuote   = "text.quote"      // default
    case person      = "person"
    case briefcase   = "briefcase"
    case link        = "link"
    case terminal    = "terminal"
    case curlybraces = "curlybraces"
    case envelope    = "envelope"
    case creditCard  = "creditcard"
    case key         = "key"
    case star        = "star"
    case flag        = "flag"
    case tag         = "tag"
}
```

**Not `Collection`, and not `LibraryEntry`'s first name.** Declaring
`public struct Collection` in `SwilClipCore` shadows `Swift.Collection` inside
the module, so every `where T: Collection` constraint would need qualifying and
consumers get an ambiguity after `import SwilClipCore`. The entry type was
called `LibraryItem` until implementation, where it collided the same way one
level out: **SwiftUI already declares `LibraryItem`** (the type
`LibraryContentProvider` returns), so no view file importing both modules can
name it. Caught by the compiler during the Core phase rather than by
inspection — which is an argument for landing Core before the shell rather than
alongside it. `LibraryCollection` and `LibraryEntry` are verbose and
unambiguous; the user-facing words stay "Collection" / "集合" in `Strings`.

---

## 3. `PanelTab`

```swift
public enum PanelTab: Hashable, Sendable {
    case clipboard
    case collection(String)   // collection id

    /// Stable string form, for `UserDefaults` and for undo entries.
    public var storageKey: String { ... }
}
```

Kept as an enum rather than flattened into a String id, because *"the clipboard
is a different kind of thing"* belongs in the type system — it is the one
special case that is real. `topBarItems` then derives naturally, and in doing so
loses a special case:

```swift
// before: `+` only on .prompts
// after:  `+` on every collection tab
public var topBarItems: [TopBarItem] {
    switch self {
    case .clipboard:  [.tabs, .settings]
    case .collection: [.tabs, .newItem, .settings]
    }
}
```

`PanelTab` loses `CaseIterable`. **That is the important consequence:** the set
of tabs becomes runtime data, so the reducer has to be *told* it.

---

## 4. `SelectionReducer`

### 4.1 The tab list is passed in, like everything else

```swift
public static func reduce(
    _ state: State,
    _ command: KeyCommand,
    visibleIDs: [String],
    actions: [RowAction] = [],
    tabs: [PanelTab] = [.clipboard]
) -> Outcome
```

This is the file's existing promise stated one axis further out. `visibleIDs` is
"the list as currently rendered"; `actions` is "the buttons the selected row is
currently drawing"; `tabs` is "the tabs the bar is currently drawing". The
reducer keeps assuming nothing.

The default value is load-bearing for the *existing* test suite: every current
call site compiles unchanged, and only new tab tests pass a list. Same trick as
`actions: [RowAction] = []`, whose comment reads *"left empty, `←`/`→` simply do
nothing on a row — the feature degrades off rather than pointing somewhere
wrong."*

`SelectionReducerTests` and `PanelFocusTests` are not to be edited beyond what
the compiler forces. Each case there corresponds to a state v1's delete-wrong-row
bug walked through (CLAUDE.md §4).

### 4.2 `⇥` cycles, `⇧⇥` reverses

```swift
case switchTab           // next, wrapping      — the rebindable binding
case switchTabBackward   // previous, wrapping  — that binding + ⇧
```

Two cases rather than one case with a `Direction` payload, so the ~10 existing
`.switchTab` literals in the tests keep compiling and `documentedAction` stays
flat.

`⇧⇥` is verified free today: `KeyBinding.matches` requires exact modifier
equality, `KeyCode.tab` is not in `KeyMapping`'s keyCode switch, and `"\t"`
fails `isTypable` (0x09 < 0x20). It currently returns `nil`.

**If the user rebinds the switch key to a combination that already contains
`⇧`, there is no reverse key.** Documented, not worked around: `←`/`→` on the
tab band reaches every tab anyway.

**No `⌘1`–`⌘5`.** `KeyMapping` carries an explicit rule — *"`⌘`-anything else
belongs to the system: `⌘Q`, `⌘W`, `⌘,`"* — and this design does not drill a
hole in it. Five tabs are at most two `⇥` presses apart in a wrapping ring.

#### Why wrapping is right here and wrong in the list

`neighbour(of:in:offset:)` refuses to wrap, with the comment *"the list is
ordered by recency, and jumping from the newest entry to the oldest on one `↑`
is never what was meant."* The tab ring wraps. These are consistent under one
rule:

> **Wrapping is safe exactly when the boundary is visible.** A list is unbounded
> and its ends are off-screen. A tab bar is five stops and all of them are drawn.

That sentence goes in the code as the justification.

### 4.3 `swapTab` takes a destination

```swift
public static func swapTab(
    current: State, incoming: State,
    from previousTab: PanelTab, to targetTab: PanelTab
) -> (outgoing: State, adopted: State)
```

The target used to be derived by negation. Everything else is untouched — in
particular `adopted.focus = current.focus` and its doc comment, which is the
SW-06 rule (focus is panel-wide, selection/query/expansion are per tab).

### 4.4 `reconcileTab` — the new invariant

This is the most important new piece of pure logic, and it exists because
deleting a collection is deleting a *tab*:

```swift
public static func reconcileTab(_ state: State, with tabs: [PanelTab]) -> State
```

- If `state.tab` is not in `tabs`, fall back to `tabs.first` (always
  `.clipboard`).
- Drop row-level focus — the other tab's rows carry different buttons.
- **Keep top-bar band focus**, for the same reason `reconcile` keeps it: a
  background change must not eject someone out of the tab bar mid-gesture.

It is the tab-level twin of `reconcile`, which exists because *"a selection
pointing at a row that no longer exists is the state from which every 'acted on
the wrong row' bug is one keystroke away."* A `tab` pointing at a collection
that no longer exists is that same sentence one dimension up.

`AppModel` must also **prune its parked-state dictionary** against the live tab
list, or a deleted-and-recreated collection id inherits a stale cursor.

---

## 5. Keyboard, complete

| key | where | meaning |
|---|---|---|
| `⇥` | anywhere | next tab, wrapping |
| `⇧⇥` | anywhere | previous tab, wrapping |
| `↑` | first row | go to the tab band |
| `↑` | tab band | **nothing** — there is nothing above the top bar |
| `←` `→` | tab band | walk the tabs, then on to `＋` / `⚙` |
| `⏎` | tab band | enter the list |
| `n` | any tab | new item (see below) |
| `⇧S` | Clipboard | save the clip into the first collection |
| `e` `p` `d` `u` | any tab | unchanged |

**`n` on the Clipboard tab keeps working** and creates an item in the first
collection, with the editor's collection picker pre-selected there. The `＋`
button still does not appear on the Clipboard tab — its absence is a *visual*
judgement (*"a plus next to Clipboard would read as 'add a clip'"*), not a
statement about capability. This asymmetry is deliberate and is written down
rather than left to be discovered.

### `ShortcutReference` fallout

The exhaustive switches will force all of this; listing it so nothing is a
surprise:

- `ShortcutAction` gains `.switchTabBackward`; `.newPrompt` → `.newItem`.
- `ShortcutGroup.prompts` → `.library`.
- `KeyCommand.documentedAction` gains `.switchTabBackward`.
- `TopBarItem.newPrompt` → `.newItem`.
- `SelectionEffect.newPrompt` → `.newItem`.

---

## 6. Top bar (shell)

A `ViewThatFits` ladder, the same device `FooterBar.hints` already uses, with
the same discipline of writing down *what is sacrificed first and why*:

```
fits        →  ▣ Clipboard 9   ✎ Prompts 12   ★ Personal 7
sacrifice 1 →  ▣ Clipboard     ✎ Prompts      ★ Personal 7    (inactive counts)
sacrifice 2 →  ▣  ✎  ★ Personal 7  ⚑  ◆                       (inactive names)
```

The active tab always keeps icon + name + count. Inactive counts go first
because they are the least load-bearing thing on the bar; inactive names go
second because the icon is a usable identifier once you have chosen it yourself.

**Cap: Clipboard + 5 collections.** One constant, with a comment recording that
it comes from the 340 pt physical width of the Small panel, not from taste.
`＋` in Settings greys out at the cap.

---

## 7. Editor

`PromptEditorView` → `LibraryEditorView`, gaining a **collection picker**. The
picker is also the only "move an item between collections" affordance — no
separate move command is needed.

`⇥` must cycle Title → Body → Collection. That is
[roadmap 2.2](./roadmap.md#phase-22--daily-use-wear)'s second item — *"`⇥`
between Title and Prompt in the editor is currently unhandled, so the editor is
the one place in the app that needs the mouse"* — and it stops being optional
here, because a third control the keyboard cannot reach is a regression.

**This design pays off that roadmap item.**

---

## 8. Collection management (Settings)

Creating a tab is a few-times-a-year action; the panel is a high-frequency
surface that must stay fast. ADR-0002 already paid once for *"the panel now has
a mode"*. So management lives in the Settings sheet: a list of collections, each
row offering symbol picker, name field, reorder, delete, plus a `＋`.

### Deleting a collection that still has items

A confirmation with **two buttons, and no guessing**:

- **`Move 7 items to Prompts`** — default
- `Delete the collection and its 7 items`

The "move" target is the first remaining collection. When the collection being
deleted is the last one, only the destructive button is offered, worded
explicitly.

Why a non-destructive default rather than relying on undo: the Settings sheet is
a separate `NSHostingView` (CLAUDE.md §8), so `u` does not reach it — the user
would have to close Settings, return to the panel, and press `u`. Backstopping
data loss with a cross-window undo is too thin for a project whose stated
ordering is *correctness / silent data loss / security-narrative coherence above
new features*.

### Undo still covers it

One operation covers both buttons, because `LibraryEntry` carries its own
`collectionID` and the snapshot is taken *before* the change:

```swift
case deletedCollection(collection: LibraryCollection, items: [LibraryEntry])
```

- Items were deleted → restore re-inserts them.
- Items were moved → restore rewrites their `collection_id` back.

Restore order is collection first, then items, so no item is ever momentarily
homeless. Per CLAUDE.md §5.1, a failed undo puts the entry **back on the stack**.

The confirmation text says undo is available from the panel, so the reach is
stated rather than discovered.

---

## 9. `⇧S` lands in the first collection

*First* means lowest `position` — the leftmost collection on the top bar,
`tabs[1]`, since `tabs[0]` is always Clipboard.

No preference key, no stored collection id, no dangling reference to handle when
that collection is deleted. To change where clips land, drag that collection to
the front.

This is not hidden state: the order **is drawn across the top bar**, which makes
it the most visible state in the app. The footer already confirms the
destination (`Saved to Prompts`), so it is also never silent.

The alternative — "remember the last collection used" — was rejected as an
invisible second source of truth, the exact failure mode CLAUDE.md §4 and §9
were written about.

### With zero collections

Deleting the last collection is reachable, so it has to be defined rather than
assumed away: the panel shows Clipboard alone, `＋` never appears on the bar,
and `⇧S` and `n` post a footer line pointing at Settings. Nothing is
auto-created — the user deleted every collection on purpose, and a tool that
silently recreates one is a tool that argues with you.

---

## 10. What this design deliberately does not build

**An edit button on clipboard rows.** History is a read-only log; that is the
decision, so the honest expression of it is that clips are not editable. `⇧S`
saves into a collection, the footer says where, and editing happens there. A
fifth button on text clips would lengthen the arrow walk and would not exist on
image clips — uniformity would get *worse*, not better.

If "save it and immediately edit it" turns out to be frequent in daily use, the
cheap follow-up is `⇧⏎` on a clip = promote + open the editor: one binding, no
new button. **Not now.**

**Per-collection behaviour profiles.** Every collection behaves identically. The
schema does not preclude adding a behaviour column later, exactly as ADR-0002
noted for `{{variables}}`.

---

## 11. Sequencing

This feature lands mostly in the shell, and [roadmap.md](./roadmap.md) is blunt
about what that means: 4,618 lines, **zero tests**, ten of fourteen audit
findings, four shipped user-visible defects. SW-06 — undo across tabs bypassing
the handover — is a bug in exactly the code this design multiplies, taking that
path's branch count from 2 to 6.

Building an N-tab state machine on an untested `AppModel` is how SW-06 recurs.

| | work | note |
|---|---|---|
| **M0** | roadmap **2.1.1** — split the app target so the shell is testable | prerequisite; an afternoon, almost all of it moving files |
| **M1** | Core: `Collection`, `CollectionSymbol`, schema v3 + seeding, `LibraryEntry`, `PanelTab`, `tabs:` parameter, `reconcileTab`, `swapTab`, `⇧⇥` | fully tested, no UI; **runs in parallel with M0** |
| **M2** | Shell: top-bar ladder, per-tab parked state + pruning, editor collection picker (pays off roadmap 2.2 `⇥`) | needs M0 |
| **M3** | Settings CRUD, delete semantics, `deletedCollection` undo | needs roadmap **2.1.3** (undo-stack tests) |
| **M4** | Arrow-scroll inside an expanded row — roadmap 2.2's first item, *"the one that annoys me most"* | |

The full Phase 2.1 is **not** a prerequisite. Only **2.1.1** (testable shell) and
**2.1.3** (undo-stack tests) are, and 2.1.3 only blocks M3.

---

## 12. Test obligations

Core, all headless:

- Schema v3 migration: existing prompt rows land in `prompts`; both seeds exist
  with the supplied names; `user_version` is stamped inside the transaction
  (extend the existing `RestoreAndSchemaTests` assertion).
- Re-running the migration on a v3 database is a no-op.
- `reconcileTab`: missing tab → clipboard; row focus dropped; band focus kept;
  parked-state pruning.
- `⇥` / `⇧⇥` wrap in both directions across 1, 2 and 6 tabs.
- `←`/`→` on the band walk N tabs before reaching `＋` / `⚙`, and `＋` is absent
  on Clipboard.
- `swapTab` with an explicit destination preserves the SW-06 rule.
- A collection whose name fails to decrypt is marked unreadable, not blank.
- `deletedCollection` undo round-trips both the delete path and the move path.
- `ShortcutReference` still documents every `KeyCommand` (existing test).

Shell, once M0 lands:

- The wiring manifest (roadmap 2.1.2) grows the new callbacks.
- `⇧S` targets the first collection; targets nothing when there are none.
- Deleting the current tab's collection leaves the panel on Clipboard with a
  valid selection.

---

## 13. Open, and deliberately so

- **Seeding `Personal` empty.** It costs a top-bar slot and shows an empty state
  until used. Under the equality model deleting it is a two-second action, so
  the cost of guessing wrong is near zero — which is the argument for shipping
  it rather than making the first run start with a chore.
- **Six tabs vs five.** The cap is a constant. Five collections is what the
  degradation ladder comfortably fits at 340 pt; if daily use says four is
  plenty, lowering it is one line.
