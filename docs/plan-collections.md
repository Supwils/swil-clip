# Collections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalise the panel's hard-coded Clipboard/Prompts pair into Clipboard
plus an ordered list of equal, user-managed collections.

**Architecture:** One built-in concept (Clipboard, the `clip` table) and N rows in
a new `collection` table. Existing prompts land in a seeded `prompts` collection
via a column default, so no data moves. `PanelTab` becomes
`.clipboard | .collection(id)`, and the tab list is passed into
`SelectionReducer` the same way `visibleIDs` and `actions` already are — the
reducer keeps assuming nothing about what is on screen.

**Tech Stack:** Swift 6 (language mode v6), SPM, AppKit + SwiftUI, system SQLite
via the hand-rolled `Database` wrapper, swift-testing (`@Test` / `#expect`).
**Zero third-party dependencies — do not add any.**

**Spec:** [`docs/design-collections.md`](./design-collections.md)

---

## Global Constraints

Copied from `CLAUDE.md` and the spec. Every task's requirements implicitly
include this section.

- **Do not `git commit` or `git push` unless the user explicitly asks.** Commit
  messages below are *prepared*, not *authorised*. Group them at phase
  boundaries (M0 / M1 / M2 / M3), not per task — the user's global rule is 2–3
  commits per day per repo, Conventional Commits, one-line subject, body at most
  2–3 short sentences.
- **Do not touch `tauri/`.** Frozen at v0.1.3 (ADR-0001).
- **`SwilClipCore` must never `import AppKit`.** If a rule can be tested without
  a window, it belongs in Core.
- **Zero third-party dependencies** (spec §4.2).
- **All UI copy goes in `SwilClipCore/Localization/Strings.swift`** as
  `pick(english, chinese)`. Both languages mandatory — a missing one is a
  compile error, which is the point. Chinese uses full-width punctuation.
  Keycaps (`⏎`, `⇧S`, `⌘V`) are never translated.
- **No hard-coded colours, spacing, radii or font sizes.** Everything via
  `Design/Tokens.swift` and `@Environment(\.metrics)`. Hairline is always 0.5pt.
- **`Token.Accent` does not exist and must not come back.** Theme colour is
  `@Environment(\.theme)`.
- **Scroll only via `ScrollAnchoring`, always `anchor: nil`.** Never
  `anchor: .center`.
- **Selection lives only in `SelectionReducer.State`. Views read it, never
  write it.** Focus travels by `RowAction` identity, never by index.
- **The reducer receives the *currently rendered* list**, never the full one.
- **`PRAGMA user_version` is written inside the same `transaction { }` as the
  migration it describes.**
- **`SelectionReducerTests` and `PanelFocusTests` are not to be deleted or
  "simplified".** Each case maps to a state v1's delete-wrong-row bug passed
  through. Edit them only where the compiler forces it.
- **Bundle identifier `com.supwilsoft.swilclip.swift` and data directory
  `SwilClipSwift` are frozen.** Never change them.
- Build/verify commands:
  - `cd swift && swift build`
  - `cd swift && swift test` (currently 220 tests, headless, ~0.15s)
  - Device check: `swift/scripts/bundle.sh --release` (~13s). **Debug builds do
    not run** — ad-hoc signing does not match the Keychain ACL.

### Out of scope for this plan

- **Roadmap 2.2's "arrow-scroll inside an expanded row" (spec §11 M4).** Making
  `↑/↓` modal on an expanded row is a change to shipped keys and has not been
  designed. It needs its own brainstorm. The editor's `⇥` field cycling *is* in
  scope (Task 14) because the collection picker requires it.
- Roadmap 2.1.2 (wiring manifest test) and 2.1.4 (Settings round trip) beyond
  what Task 2 establishes.

---

## File Structure

### Created

| Path | Responsibility |
|---|---|
| `swift/Sources/SwilClipCore/Models/LibraryCollection.swift` | `LibraryCollection` value + `CollectionSymbol` closed set |
| `swift/Sources/SwilClipCore/Models/LibraryEntry.swift` | renamed from `PromptItem.swift`; adds `collectionID` |
| `swift/Sources/SwilClipCore/Database/LocalStore+Library.swift` | renamed from `LocalStore+Prompts.swift`; adds collection CRUD |
| `swift/Sources/SwilClipUI/**` | the whole app shell, moved out of `Sources/SwilClip` |
| `swift/Sources/SwilClipUI/App/AppDelegate.swift` | wiring, extracted from `main.swift` |
| `swift/Sources/SwilClipUI/Views/LibraryRowView.swift` | renamed from `PromptRowView.swift` |
| `swift/Sources/SwilClipUI/Views/LibraryEditorView.swift` | renamed from `PromptEditorView.swift`; adds collection picker |
| `swift/Sources/SwilClipUI/Views/CollectionsPane.swift` | Settings pane for collection CRUD (split out of `SettingsView`) |
| `swift/Tests/SwilClipCoreTests/CollectionTests.swift` | model + store + migration coverage |
| `swift/Tests/SwilClipCoreTests/TabNavigationTests.swift` | N-tab reducer coverage |
| `swift/Tests/SwilClipUITests/AppModelTests.swift` | shell coverage, newly possible |

### Modified

`swift/Package.swift` · `Sources/SwilClip/main.swift` (shrinks to an entry
point) · `SwilClipCore/Database/Schema.swift` · `SwilClipCore/Database/LocalStore.swift` ·
`SwilClipCore/Selection/SelectionReducer.swift` · `PanelFocus.swift` ·
`KeyMapping.swift` · `ShortcutReference.swift` ·
`SwilClipCore/Localization/Strings.swift` · `SwilClipCore/Search/Matcher.swift` ·
`SwilClipUI/State/AppModel.swift` · `SwilClipUI/Views/PanelRootView.swift` ·
`SwilClipUI/Views/SettingsView.swift` · `SwilClipUI/Panel/PanelController.swift`

### Why `SettingsView` gets split

`SettingsView.swift` is already the largest file in the tree at 664 lines.
Collection CRUD adds a list with inline rename, a symbol picker, reordering and
a two-button destructive confirm. Putting that inline would push the file past
900 lines. `CollectionsPane` is a self-contained pane with one responsibility,
so it moves out; `SettingsView` keeps the pane switcher and the existing General
sections.

---

## Phase M0 — make the shell testable

`Sources/SwilClip/main.swift` is top-level code, which is why SPM cannot
`@testable import` the app. Everything in M1–M3 that touches `AppModel` is
untestable until this lands, and `AppModel` is exactly where SW-06 lived.

---

### Task 1: Split the app target

**Files:**
- Modify: `swift/Package.swift`
- Move: `swift/Sources/SwilClip/**` → `swift/Sources/SwilClipUI/**` *(everything except `main.swift`)*
- Create: `swift/Sources/SwilClipUI/App/AppDelegate.swift` (extracted from `main.swift`)
- Modify: `swift/Sources/SwilClip/main.swift` (shrinks to 5 lines)

**Interfaces:**
- Consumes: nothing.
- Produces: a `SwilClipUI` library target that `@testable import SwilClipUI`
  can reach, and `public final class AppDelegate: NSObject, NSApplicationDelegate`
  with `public override init()`.

- [ ] **Step 1: Move every shell file except `main.swift`**

```bash
cd swift
mkdir -p Sources/SwilClipUI Sources/SwilClipUI/App
for d in Branding Clipboard Design Focus Hotkey Panel State StatusItem Views; do
  git mv "Sources/SwilClip/$d" "Sources/SwilClipUI/$d"
done
ls Sources/SwilClip      # must print only: main.swift
ls Sources/SwilClipUI    # Branding Clipboard Design Focus Hotkey Panel State StatusItem Views App
```

- [ ] **Step 2: Extract `AppDelegate` into the library**

Move the entire `AppDelegate` class out of `Sources/SwilClip/main.swift` into
`Sources/SwilClipUI/App/AppDelegate.swift` verbatim, changing only the class
declaration and adding an initialiser (the executable is now a *different
module*, so it needs public access):

```swift
// Sources/SwilClipUI/App/AppDelegate.swift
import AppKit
import CryptoKit
import SwilClipCore

/// Wires the app together and owns everything that must outlive a window.
///
/// Public because it now lives in `SwilClipUI` while the process entry point
/// stays in the `SwilClip` executable. That split is what lets the shell be
/// `@testable import`ed: SPM cannot reliably import an executable target, so
/// everything except `main.swift` moved here.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    // ... the rest of the class, byte-for-byte unchanged ...
}
```

Everything else in the class stays `private`/internal. Do not widen anything
else — `@testable` reaches `internal`.

- [ ] **Step 3: Reduce `main.swift` to an entry point**

```swift
// Sources/SwilClip/main.swift
import AppKit
import SwilClipUI

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
```

- [ ] **Step 4: Declare the new targets**

In `swift/Package.swift`, replace the `SwilClip` executable target and add two
new targets. The final `targets:` array:

```swift
    targets: [
        .target(
            name: "SwilClipCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The shell as a library, so it can be @testable imported. SPM cannot
        // reliably import an executable target, which is why the four wiring
        // bugs (SW-01, SW-02, SW-06, SW-12) shipped from untestable code.
        .target(
            name: "SwilClipUI",
            dependencies: ["SwilClipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // main.swift only.
        .executableTarget(
            name: "SwilClip",
            dependencies: ["SwilClipUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SwilClipRecover",
            dependencies: ["SwilClipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwilClipCoreTests",
            dependencies: ["SwilClipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwilClipUITests",
            dependencies: ["SwilClipUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
```

Also add the library product so the shape is declared, not implied:

```swift
    products: [
        .executable(name: "SwilClip", targets: ["SwilClip"]),
        .executable(name: "swilclip-recover", targets: ["SwilClipRecover"]),
        .library(name: "SwilClipCore", targets: ["SwilClipCore"]),
        .library(name: "SwilClipUI", targets: ["SwilClipUI"]),
    ],
```

- [ ] **Step 5: Create a placeholder test so the new target compiles**

```swift
// Tests/SwilClipUITests/AppModelTests.swift
import Testing

@testable import SwilClipUI

@Suite("SwilClipUI target")
struct TargetSanityTests {
    /// The whole point of Task 1: this file existing and importing the shell
    /// is what 4,618 previously-unreachable lines were waiting on.
    @Test("the shell is importable from a test target")
    func importable() {
        #expect(PanelSize.medium.scale == 1.25)
    }
}
```

- [ ] **Step 6: Verify the build and the whole suite**

```bash
cd swift && swift build && swift test 2>&1 | tail -20
```

Expected: build succeeds; **221 tests pass** (220 existing + 1 new). If a
`fileprivate`/`private` access error appears, it is a file that was split across
the module boundary — fix by moving the file, never by widening access.

- [ ] **Step 7: Confirm the app still launches**

```bash
cd swift && ./scripts/bundle.sh --release
```

Expected: bundle succeeds. Launch it, press the summon hotkey, confirm the panel
appears and `⇥` still switches tabs. **Debug builds do not run — always use
`--release`.**

- [ ] **Step 8: Prepared commit** *(run only if the user has asked to commit)*

```bash
git add -A swift/
git commit -m "refactor: split the app shell into a library target so it can be tested"
```

---

### Task 2: Cut `AppModel`'s AppKit dependency

`AppModel` imports AppKit for exactly two calls, both
`NSWorkspace.shared.frontmostApplication?.localizedName`. Behind a closure they
disappear and `AppModel` becomes constructible in a test with a temp store.

**Files:**
- Modify: `swift/Sources/SwilClipUI/State/AppModel.swift`
- Modify: `swift/Sources/SwilClipUI/App/AppDelegate.swift`
- Modify: `swift/Tests/SwilClipUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: `SwilClipUI` target from Task 1.
- Produces: `AppModel.init(store:settings:sourceApp:)` where
  `sourceApp: @MainActor () -> String?` defaults to `{ nil }`, and a reusable
  `TempModel` test fixture.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwilClipUITests/AppModelTests.swift — replace the placeholder suite
import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore
@testable import SwilClipUI

/// A model on a throwaway store, with no window server anywhere in reach.
@MainActor
final class TempModel {
    let root: URL
    let settings: Settings
    let model: AppModel

    init(sourceApp: @escaping @MainActor () -> String? = { nil }) throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-ui-tests-\(UUID().uuidString)", isDirectory: true)
        let locations = StorageLocations(root: root)
        let store = try LocalStore(locations: locations, key: SymmetricKey(size: .bits256))
        // A scratch domain, so a test never reads or writes the real prefs.
        settings = Settings(defaults: UserDefaults(suiteName: "swilclip-tests-\(UUID().uuidString)")!)
        model = AppModel(store: store, settings: settings, sourceApp: sourceApp)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("AppModel")
struct AppModelTests {
    @MainActor
    @Test("the source-app name is injected, not read from NSWorkspace")
    func sourceAppIsASeam() async throws {
        let temp = try TempModel(sourceApp: { "Xcode" })
        await temp.model.recordForTesting(text: "hello")
        await temp.model.refresh()
        #expect(temp.model.clips.first?.sourceApp == "Xcode")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd swift && swift test --filter AppModelTests 2>&1 | tail -20
```

Expected: FAIL — `AppModel` has no `sourceApp:` parameter and no
`recordForTesting`.

- [ ] **Step 3: Add the seam**

In `AppModel.swift`, replace `import AppKit` usage. Add the stored closure and
the parameter:

```swift
    /// Name of the app that was frontmost when a clip was captured.
    ///
    /// Injected rather than read inline. It was the only reason this file
    /// imported AppKit, and with it gone the model is constructible in a test
    /// with a temp store — which is what the undo stack and the per-tab state
    /// machine needed in order to be asserted rather than hand-walked.
    private let sourceApp: @MainActor () -> String?

    init(
        store: LocalStore,
        settings: Settings,
        sourceApp: @escaping @MainActor () -> String? = { nil }
    ) {
        self.store = store
        self.settings = settings
        self.sourceApp = sourceApp
    }
```

Replace both `NSWorkspace.shared.frontmostApplication?.localizedName` call sites
in `record(_:)` with `sourceApp()`.

Add the test hook next to `record(_:)`:

```swift
    /// Record a clip without a pasteboard. Test-only entry to the same path
    /// `PasteboardMonitor` drives, so the tests exercise production code.
    func recordForTesting(text: String) async {
        await record(.text(text))
    }
```

`record(_:)` is `private`; change it to `internal` (drop `private`) so
`@testable` can reach it, or keep it private and let `recordForTesting` call it —
the latter is what the snippet above does, so no visibility change is needed.

- [ ] **Step 4: Give `Settings` an injectable defaults suite**

In `Settings.swift`, the initialiser must accept a `UserDefaults`:

```swift
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // ... existing body unchanged ...
    }
```

- [ ] **Step 5: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

Expected: **222 tests pass.** Confirm `AppModel.swift` no longer needs AppKit:

```bash
grep -n "^import AppKit" swift/Sources/SwilClipUI/State/AppModel.swift
```

Expected: no output. If `AccessibilityPermission` or `PasteSimulator` still pull
AppKit types into a signature, leave the import — the point is that the *model's
own logic* no longer reaches for the window server. Note which symbol kept it.

- [ ] **Step 6: Prepared commit** *(run only if the user has asked to commit)*

```bash
git add -A swift/
git commit -m "test: make AppModel constructible without a window server"
```

---
## Phase M1 — Core

Pure Swift, no AppKit, fully tested. **Runs in parallel with M0** — nothing here
depends on the target split.

---

### Task 3: `LibraryCollection` and `CollectionSymbol`

**Files:**
- Create: `swift/Sources/SwilClipCore/Models/LibraryCollection.swift`
- Create: `swift/Tests/SwilClipCoreTests/CollectionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `LibraryCollection(id:name:symbol:position:createdAt:isUnreadable:)`
  and `CollectionSymbol(rawValue:)` with `.textQuote` as the fallback, plus
  `CollectionSymbol.fallback(_ raw: String) -> CollectionSymbol`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwilClipCoreTests/CollectionTests.swift
import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore

@Suite("CollectionSymbol")
struct CollectionSymbolTests {
    /// A row written by a future version — or a corrupted one — must still draw
    /// something. A tab with no glyph reads as a layout bug, and the same rule
    /// already governs `ClipItem.isUnreadable`: never render "nothing" for
    /// "could not read".
    @Test("an unknown stored value degrades to the default glyph")
    func unknownFallsBack() {
        #expect(CollectionSymbol.fallback("text.quote") == .textQuote)
        #expect(CollectionSymbol.fallback("person") == .person)
        #expect(CollectionSymbol.fallback("nonsense.symbol") == .textQuote)
        #expect(CollectionSymbol.fallback("") == .textQuote)
    }

    @Test("every case carries a distinct, non-empty SF Symbol name")
    func namesAreWellFormed() {
        let names = CollectionSymbol.allCases.map(\.rawValue)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
        #expect(CollectionSymbol.allCases.count >= 8, "a picker with too few options is not a picker")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd swift && swift test --filter CollectionSymbolTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'CollectionSymbol' in scope`.

- [ ] **Step 3: Write the model**

```swift
// Sources/SwilClipCore/Models/LibraryCollection.swift
import Foundation

/// One user-managed tab: a named, ordered home for ``LibraryEntry``s.
///
/// ## Why there is no `isBuiltIn`
///
/// Clipboard is the only special tab, and its specialness is real — it lives in
/// another table, it is written by the pasteboard poller, it evicts, and it is
/// read-only. Everything else is one of these, and every one of these obeys
/// identical rules.
///
/// The migration seeds two of them (Prompts, Personal) and then forgets that it
/// did. A flag marking them would be a mechanism built for two rows, and it
/// would create a state the user cannot see — *have I renamed this?* — which is
/// the shape of every bug this codebase has shipped. It would also contradict
/// the whole change: code carrying `isBuiltIn` on Prompts is code still
/// asserting Prompts is special.
///
/// ## Why the name is not a `Strings` property
///
/// It is user data, not interface copy. `Strings` is a compile-time-exhaustive
/// catalog precisely because interface copy must exist in both languages; a
/// name the user typed exists in exactly one, theirs. Seeded names are written
/// once in whatever language the app was in at migration and are user data from
/// that moment on.
public struct LibraryCollection: Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var symbol: CollectionSymbol
    /// Dense `0..<n`, rewritten wholesale on reorder. With a hard cap of five
    /// collections there is no case for fractional indexing.
    public var position: Int
    public let createdAt: Date
    /// This row's sealed name could not be opened. Surfaced rather than
    /// swallowed — a blank tab looks like the app lost something. Same rule as
    /// ``ClipItem/isUnreadable``.
    public let isUnreadable: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        symbol: CollectionSymbol = .textQuote,
        position: Int,
        createdAt: Date = Date(),
        isUnreadable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.position = position
        self.createdAt = createdAt
        self.isUnreadable = isUnreadable
    }

    /// The ids the migration seeds. Constants rather than literals scattered
    /// across the store, because `prompt.collection_id`'s column default is one
    /// of them and the two must not drift.
    public enum Seed {
        public static let prompts = "prompts"
        public static let personal = "personal"
    }

    /// Hard cap, from the physical width of the Small panel: 340 pt fits about
    /// six stops once the top bar's `⇥`, `＋` and `⚙` are accounted for, and the
    /// ladder in `TabBar` degrades to icons before that. Not a taste judgement —
    /// change it only alongside a measurement.
    public static let maximumCount = 5
}

/// The glyphs a collection may wear.
///
/// A closed set rather than a bare `String`, so an unknown value from a
/// corrupted row degrades to ``textQuote`` instead of drawing nothing.
/// Precedent: ``ShortcutEntry/symbol`` already stores an SF Symbol name in this
/// AppKit-free module, with the same justification — it is an identifier for
/// something printed, chosen once, next to the thing it belongs to.
public enum CollectionSymbol: String, CaseIterable, Sendable, Identifiable {
    case textQuote = "text.quote"
    case person = "person"
    case briefcase = "briefcase"
    case link = "link"
    case terminal = "terminal"
    case curlybraces = "curlybraces"
    case envelope = "envelope"
    case creditcard = "creditcard"
    case key = "key"
    case star = "star"
    case flag = "flag"
    case tag = "tag"

    public var id: String { rawValue }

    public static func fallback(_ raw: String) -> CollectionSymbol {
        CollectionSymbol(rawValue: raw) ?? .textQuote
    }
}
```

- [ ] **Step 4: Verify**

```bash
cd swift && swift test --filter CollectionSymbolTests 2>&1 | tail -20
```

Expected: PASS, 2 tests.

---

### Task 4: `PromptItem` → `LibraryEntry`, with a `collectionID`

A pure-Swift rename with no data risk. The SQL table stays `prompt` — shipped
migrations are append-only, and renaming a table to get a nicer identifier is a
data move for zero user-visible benefit.

**Files:**
- Move: `swift/Sources/SwilClipCore/Models/PromptItem.swift` → `Models/LibraryEntry.swift`
- Modify: every file referencing `PromptItem` (see Step 1)
- Modify: `swift/Tests/SwilClipCoreTests/CollectionTests.swift`

**Interfaces:**
- Consumes: `LibraryCollection.Seed` from Task 3.
- Produces: `LibraryEntry(id:collectionID:title:body:isPinned:createdAt:updatedAt:)`
  with `var collectionID: String`, `var preview: String`,
  `var rowActions: [RowAction]`. `PromptTitle` is unchanged and keeps its name.

- [ ] **Step 1: Find every reference**

```bash
cd swift && grep -rln "PromptItem" Sources Tests
```

Expected (before M0's move, adjust the `SwilClip`/`SwilClipUI` prefix to match):
`Models/PromptItem.swift`, `Database/LocalStore+Prompts.swift`,
`Search/Matcher.swift`, `State/AppModel.swift`, `Views/PanelRootView.swift`,
`Views/PromptRowView.swift`, `Views/PromptEditorView.swift`,
`Panel/PanelController.swift`, `Tests/SwilClipCoreTests/LocalStoreTests.swift`.

- [ ] **Step 2: Write the failing test**

Append to `Tests/SwilClipCoreTests/CollectionTests.swift`:

```swift
@Suite("LibraryEntry")
struct LibraryEntryTests {
    @Test("an item knows which collection it belongs to")
    func carriesItsCollection() {
        let item = LibraryEntry(collectionID: "personal", title: "GitHub", body: "https://github.com/supwils")
        #expect(item.collectionID == "personal")
        #expect(item.preview == "https://github.com/supwils")
    }

    /// Unchanged from `PromptItem`, and asserted so the rename cannot quietly
    /// change what the row draws — focus travels by `RowAction` identity, so a
    /// reordering here would slide `⏎` from "edit" onto "expand".
    @Test("the row still draws pin, edit, expand, delete in that order")
    func rowActionsAreUnchanged() {
        let item = LibraryEntry(collectionID: "prompts", title: "t", body: "b")
        #expect(item.rowActions == [.pin, .edit, .expand, .delete])
    }

    @Test("items default into the seeded prompts collection")
    func defaultsToSeed() {
        #expect(LibraryEntry(title: "t", body: "b").collectionID == LibraryCollection.Seed.prompts)
    }
}
```

- [ ] **Step 3: Run it and watch it fail**

```bash
cd swift && swift test --filter LibraryEntryTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'LibraryEntry' in scope`.

- [ ] **Step 4: Rename the file and the type**

```bash
cd swift
git mv Sources/SwilClipCore/Models/PromptItem.swift Sources/SwilClipCore/Models/LibraryEntry.swift
grep -rl "PromptItem" Sources Tests | xargs sed -i '' 's/\bPromptItem\b/LibraryEntry/g'
grep -rn "PromptItem" Sources Tests   # must print nothing
```

- [ ] **Step 5: Add `collectionID` and retitle the doc comment**

In `Models/LibraryEntry.swift`, replace the type's doc comment and add the field:

```swift
/// A curated, long-lived entry — the tier history eviction never touches.
///
/// Two content fields, on purpose. The 2026-05-28 draft specified
/// `{{variables}}` and tags; neither is built, and nothing in the real corpus
/// uses a variable. At this corpus size a tag is one more decision to make while
/// saving — friction that decides whether a personal tool actually gets used.
///
/// A GitHub URL and a prompt are the same shape (`title` + `body`), which is
/// the observation the whole Collections change rests on: what differed between
/// them was never the record, only which tab it was allowed to appear in.
public struct LibraryEntry: Sendable, Identifiable, Equatable {
    public let id: String
    /// Which collection this lives in. Mutable, because the editor's collection
    /// picker doubles as the only "move between collections" affordance.
    public var collectionID: String
    public var title: String
    public var body: String
    public var isPinned: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        collectionID: String = LibraryCollection.Seed.prompts,
        title: String,
        body: String,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.body = body
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Single-line form for the list row.
    public var preview: String { PreviewText.derive(from: body) }

    /// The buttons this row draws, in render order. See ``ClipItem/rowActions``.
    /// A library item is editable where a clip is promotable.
    public var rowActions: [RowAction] { [.pin, .edit, .expand, .delete] }
}
```

- [ ] **Step 6: Verify**

```bash
cd swift && swift build 2>&1 | tail -20
```

Compile errors are expected in `LocalStore+Prompts.swift` (the `upsert`/`decode`
helpers do not know the new column yet) — those are Task 5 and Task 6. Fix only
what the rename broke: pass `collectionID: row.text(N)` where the decoder needs
it *after* Task 5 adds the column. Until then, temporarily decode it as
`LibraryCollection.Seed.prompts` so the tree builds:

```swift
        LibraryEntry(
            id: row.text(0),
            collectionID: LibraryCollection.Seed.prompts,   // replaced in Task 6
            title: (try? cipher.openString(row.blob(1))) ?? "",
            ...
        )
```

```bash
cd swift && swift test --filter LibraryEntryTests 2>&1 | tail -20
```

Expected: PASS, 3 tests.

---

### Task 5: Schema v3 — the `collection` table, the column, and the seed

**Files:**
- Modify: `swift/Sources/SwilClipCore/Database/Schema.swift`
- Modify: `swift/Sources/SwilClipCore/Database/LocalStore.swift` (init signature)
- Modify: `swift/Tests/SwilClipCoreTests/CollectionTests.swift`

**Interfaces:**
- Consumes: `LibraryCollection.Seed`, `CollectionSymbol` from Task 3.
- Produces: `Schema.current == 3`;
  `Schema.SeedNames(prompts:personal:)` with a `.fallback` static;
  `Schema.migrate(_ database: Database, cipher: FieldCipher, seedNames: SeedNames)`;
  `LocalStore.init(locations:key:seedNames:)` with
  `seedNames: Schema.SeedNames = .fallback`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwilClipCoreTests/CollectionTests.swift`:

```swift
@Suite("Schema v3")
struct SchemaV3Tests {
    @Test("existing prompts land in the seeded prompts collection, unmoved")
    func existingPromptsKeepTheirHome() async throws {
        let temp = try TempStore()
        let created = try await temp.store.createPrompt(title: "Handoff", body: "session handoff")!

        let items = try await temp.store.allItems()
        #expect(items.count == 1)
        #expect(items[0].id == created.id)
        #expect(items[0].collectionID == LibraryCollection.Seed.prompts)
    }

    @Test("both collections are seeded, in order, with the supplied names")
    func seedsTwoCollections() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(
            locations: StorageLocations(root: root),
            key: SymmetricKey(size: .bits256),
            seedNames: .init(prompts: "提示词", personal: "个人")
        )

        let collections = try await store.allCollections()
        #expect(collections.map(\.id) == [LibraryCollection.Seed.prompts, LibraryCollection.Seed.personal])
        #expect(collections.map(\.name) == ["提示词", "个人"])
        #expect(collections.map(\.position) == [0, 1])
        #expect(collections[0].symbol == .textQuote)
        #expect(collections[1].symbol == .person)
        #expect(collections.allSatisfy { !$0.isUnreadable })
    }

    @Test("the version stamp is committed with the migration, not after it")
    func versionIsStampedInsideTheTransaction() async throws {
        let temp = try TempStore()
        #expect(try await temp.store.schemaVersion() == 3)
    }

    /// The rule at the top of `Schema.swift`: `ALTER TABLE` is not idempotent,
    /// so a second run on an already-migrated file must be a no-op rather than
    /// an error that bricks a perfectly good database.
    @Test("re-opening a v3 database does not re-run the migration")
    func migrationIsNotRerun() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swilclip-remigrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256)

        let first = try LocalStore(locations: StorageLocations(root: root), key: key)
        try await first.createPrompt(title: "keep", body: "keep me")

        let second = try LocalStore(locations: StorageLocations(root: root), key: key)
        #expect(try await second.schemaVersion() == 3)
        #expect(try await second.allItems().count == 1)
        #expect(try await second.allCollections().count == 2, "seeding must not duplicate")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd swift && swift test --filter SchemaV3Tests 2>&1 | tail -30
```

Expected: FAIL — no `allCollections`, no `allItems`, no `seedNames:`.

- [ ] **Step 3: Write the migration**

In `Schema.swift`, bump the version, thread the cipher and the names, and add
`applyV3`:

```swift
public enum Schema {
    public static let current: Int32 = 3

    /// Names for the two collections the v3 migration seeds.
    ///
    /// Passed in rather than read from a preference, because `SwilClipCore`
    /// does not import AppKit and does not know the UI language. `AppDelegate`
    /// builds `Settings` before `LocalStore`, so `settings.strings.promptsTab`
    /// is in hand at the call site. The seeded names are ordinary user data
    /// from the moment they are written — they do not follow a later language
    /// switch, and renaming is two seconds in Settings.
    public struct SeedNames: Sendable, Equatable {
        public let prompts: String
        public let personal: String

        public init(prompts: String, personal: String) {
            self.prompts = prompts
            self.personal = personal
        }

        /// For the recovery tool and the tests, which have no `Strings`.
        public static let fallback = SeedNames(prompts: "Prompts", personal: "Personal")
    }

    public static func migrate(
        _ database: Database,
        cipher: FieldCipher,
        seedNames: SeedNames = .fallback
    ) throws {
        let version = try database.queryOne("PRAGMA user_version") { Int32($0.int(0)) } ?? 0
        guard version < current else { return }

        try database.transaction {
            if version < 1 { try applyV1(database) }
            if version < 2 { try applyV2(database) }
            if version < 3 { try applyV3(database, cipher: cipher, seedNames: seedNames) }
            try database.execute("PRAGMA user_version = \(current)")
        }
    }

    /// Turns the single hard-coded prompt library into an ordered list of
    /// equal collections.
    ///
    /// The seed runs *inside* the same transaction as the DDL, not after it.
    /// A crash in between would leave a v3 database whose `prompt` rows all
    /// point at a `collection_id` that has no row — every prompt present in the
    /// file and none of them reachable from any tab.
    ///
    /// No `REFERENCES collection(id)` on the new column: SQLite only accepts a
    /// foreign key on `ALTER TABLE ADD COLUMN` when the default is NULL, and the
    /// default here has to be `'prompts'` so existing rows land somewhere
    /// without a data move. Referential integrity is therefore the store's job —
    /// see `deleteCollection`, which moves or deletes members in one
    /// transaction.
    private static func applyV3(
        _ database: Database,
        cipher: FieldCipher,
        seedNames: SeedNames
    ) throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS collection (
              id         TEXT PRIMARY KEY,
              name       BLOB    NOT NULL,
              symbol     TEXT    NOT NULL,
              position   INTEGER NOT NULL,
              created_at INTEGER NOT NULL
            )
            """
        )
        try database.execute(
            "ALTER TABLE prompt ADD COLUMN collection_id TEXT NOT NULL DEFAULT '\(LibraryCollection.Seed.prompts)'"
        )
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_prompt_collection
              ON prompt(collection_id, is_pinned DESC, updated_at DESC)
            """
        )

        let now = Date()
        for (id, name, symbol, position) in [
            (LibraryCollection.Seed.prompts, seedNames.prompts, CollectionSymbol.textQuote, 0),
            (LibraryCollection.Seed.personal, seedNames.personal, CollectionSymbol.person, 1),
        ] {
            try database.execute(
                """
                INSERT OR IGNORE INTO collection (id, name, symbol, position, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    .text(id),
                    .blob(try cipher.seal(name)),
                    .text(symbol.rawValue),
                    .integer(Int64(position)),
                    .date(now),
                ]
            )
        }
    }
```

Leave `applyV1` and `applyV2` byte-for-byte unchanged. A shipped migration is
never edited.

- [ ] **Step 4: Thread the names through `LocalStore.init`**

```swift
    public init(
        locations: StorageLocations,
        key: SymmetricKey,
        seedNames: Schema.SeedNames = .fallback
    ) throws {
        try locations.createDirectories()
        self.locations = locations
        self.database = try Database(path: locations.databaseURL.path)
        self.cipher = FieldCipher(key: key)
        try Schema.migrate(database, cipher: cipher, seedNames: seedNames)
    }
```

The default keeps `SwilClipRecover` and every existing test compiling unchanged.

- [ ] **Step 5: Verify (expect Task 6's methods still missing)**

```bash
cd swift && swift build 2>&1 | tail -20
```

Expected: fails only on `allCollections` / `allItems`, which Task 6 adds.

---

### Task 6: Store — collection CRUD and per-collection reads

**Files:**
- Move: `swift/Sources/SwilClipCore/Database/LocalStore+Prompts.swift` → `Database/LocalStore+Library.swift`
- Modify: `swift/Tests/SwilClipCoreTests/CollectionTests.swift`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces, on `LocalStore`:
  - `func allCollections() throws -> [LibraryCollection]`
  - `func createCollection(name: String, symbol: CollectionSymbol, now: Date = Date()) throws -> LibraryCollection?`
  - `func updateCollection(_ collection: LibraryCollection) throws`
  - `func reorderCollections(_ orderedIDs: [String]) throws`
  - `func deleteCollection(id: String, movingItemsTo destination: String?) throws`
  - `func restoreCollection(_ collection: LibraryCollection, items: [LibraryEntry]) throws`
  - `func allItems() throws -> [LibraryEntry]`
  - `func items(in collectionID: String) throws -> [LibraryEntry]`
  - `func createItem(collectionID: String, title: String? = nil, body: String, now: Date = Date()) throws -> LibraryEntry?`
  - `func promote(clipID: String, into collectionID: String, now: Date = Date()) throws -> LibraryEntry?`
  - Renamed from the prompt era: `updateItem`, `deleteItem(id:)`, `setItemPinned`,
    `restoreItemPinState`, `restoreItems`, `itemCount`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwilClipCoreTests/CollectionTests.swift`:

```swift
@Suite("LocalStore — collections")
struct LocalStoreCollectionTests {
    @Test("creates, renames and re-icons a collection")
    func crudRoundTrip() async throws {
        let temp = try TempStore()
        var made = try await temp.store.createCollection(name: "Work", symbol: .briefcase)!
        #expect(made.position == 2, "new collections go to the end")

        made.name = "Client work"
        made.symbol = .link
        try await temp.store.updateCollection(made)

        let back = try await temp.store.allCollections().first { $0.id == made.id }
        #expect(back?.name == "Client work")
        #expect(back?.symbol == .link)
    }

    @Test("refuses to create past the cap")
    func honoursTheCap() async throws {
        let temp = try TempStore()
        for index in 0..<(LibraryCollection.maximumCount - 2) {
            #expect(try await temp.store.createCollection(name: "C\(index)", symbol: .tag) != nil)
        }
        #expect(try await temp.store.createCollection(name: "one too many", symbol: .tag) == nil)
    }

    @Test("reordering rewrites positions densely")
    func reorderIsDense() async throws {
        let temp = try TempStore()
        let work = try await temp.store.createCollection(name: "Work", symbol: .briefcase)!
        try await temp.store.reorderCollections([work.id, LibraryCollection.Seed.personal, LibraryCollection.Seed.prompts])

        let ordered = try await temp.store.allCollections()
        #expect(ordered.map(\.id) == [work.id, LibraryCollection.Seed.personal, LibraryCollection.Seed.prompts])
        #expect(ordered.map(\.position) == [0, 1, 2])
    }

    @Test("items are read back scoped to their collection")
    func itemsAreScoped() async throws {
        let temp = try TempStore()
        try await temp.store.createItem(collectionID: LibraryCollection.Seed.prompts, body: "a prompt")
        try await temp.store.createItem(collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "https://github.com/supwils")

        #expect(try await temp.store.items(in: LibraryCollection.Seed.prompts).count == 1)
        let personal = try await temp.store.items(in: LibraryCollection.Seed.personal)
        #expect(personal.count == 1)
        #expect(personal[0].title == "GitHub")
        #expect(try await temp.store.allItems().count == 2)
    }

    @Test("deleting a collection can move its items instead of losing them")
    func deleteMovesItems() async throws {
        let temp = try TempStore()
        try await temp.store.createItem(collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "https://github.com/supwils")

        try await temp.store.deleteCollection(
            id: LibraryCollection.Seed.personal,
            movingItemsTo: LibraryCollection.Seed.prompts
        )

        #expect(try await temp.store.allCollections().map(\.id) == [LibraryCollection.Seed.prompts])
        let moved = try await temp.store.items(in: LibraryCollection.Seed.prompts)
        #expect(moved.count == 1, "the item survived the tab it lived in")
        #expect(moved[0].title == "GitHub")
    }

    @Test("deleting a collection outright takes its items with it")
    func deleteRemovesItems() async throws {
        let temp = try TempStore()
        try await temp.store.createItem(collectionID: LibraryCollection.Seed.personal, body: "throwaway")
        try await temp.store.deleteCollection(id: LibraryCollection.Seed.personal, movingItemsTo: nil)
        #expect(try await temp.store.allItems().isEmpty)
    }

    /// CLAUDE.md §5.1: undo has to be a real inverse. Restoring the collection
    /// without restoring membership leaves the tab back but empty.
    @Test("restore puts the collection and its membership back")
    func restoreIsARealInverse() async throws {
        let temp = try TempStore()
        try await temp.store.createItem(collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "https://github.com/supwils")

        let doomed = try await temp.store.allCollections().first { $0.id == LibraryCollection.Seed.personal }!
        let members = try await temp.store.items(in: LibraryCollection.Seed.personal)

        try await temp.store.deleteCollection(id: doomed.id, movingItemsTo: LibraryCollection.Seed.prompts)
        try await temp.store.restoreCollection(doomed, items: members)

        let back = try await temp.store.allCollections()
        #expect(back.map(\.id) == [LibraryCollection.Seed.prompts, LibraryCollection.Seed.personal])
        #expect(try await temp.store.items(in: LibraryCollection.Seed.personal).count == 1)
        #expect(try await temp.store.items(in: LibraryCollection.Seed.prompts).isEmpty)
    }

    @Test("a name that will not decrypt is marked unreadable, never blank")
    func unreadableNames() async throws {
        let temp = try TempStore()
        // Overwrite the sealed name with bytes this key cannot open.
        try await temp.store.corruptCollectionNameForTesting(id: LibraryCollection.Seed.personal)
        let broken = try await temp.store.allCollections().first { $0.id == LibraryCollection.Seed.personal }!
        #expect(broken.isUnreadable)
        #expect(broken.name.isEmpty, "the view supplies the placeholder, not the store")
    }

    @Test("promote lands a clip in the collection it is told, not a hard-coded one")
    func promoteTargetsACollection() async throws {
        let temp = try TempStore()
        let clip = try await temp.store.recordText("https://github.com/supwils", limit: 50)!
        let made = try await temp.store.promote(clipID: clip.id, into: LibraryCollection.Seed.personal)
        #expect(made?.collectionID == LibraryCollection.Seed.personal)
        #expect(try await temp.store.clipCount() == 1, "promoting does not remove the clip")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd swift && swift test --filter LocalStoreCollectionTests 2>&1 | tail -30
```

Expected: FAIL — none of these methods exist.

- [ ] **Step 3: Rename the file and its members**

```bash
cd swift
git mv Sources/SwilClipCore/Database/LocalStore+Prompts.swift \
       Sources/SwilClipCore/Database/LocalStore+Library.swift
```

Inside it rename, and update every call site the compiler reports:
`allPrompts` → `allItems`, `prompt(id:)` → `item(id:)`,
`promptCount` → `itemCount`, `createPrompt` → `createItem`,
`updatePrompt` → `updateItem`, `deletePrompt` → `deleteItem`,
`setPromptPinned` → `setItemPinned`,
`restorePromptPinState` → `restoreItemPinState`,
`restorePrompts` → `restoreItems`, `promoteToPrompt` → `promote`.

Keep `createPrompt` as a thin deprecated shim **only** if a test still needs it;
prefer updating the tests. `PromptTitle` keeps its name — it is about titles for
prompts *and* URLs alike, and renaming it buys nothing.

- [ ] **Step 4: Teach the decoders about the column**

```swift
    private static var itemColumns: String {
        "id, title, body, is_pinned, created_at, updated_at, collection_id"
    }

    public func allItems() throws -> [LibraryEntry] {
        try database.query(
            """
            SELECT \(Self.itemColumns) FROM prompt
            ORDER BY is_pinned DESC, updated_at DESC
            """
        ) { try decodeItem($0) }
    }

    /// One collection's rows, in render order. Scoped in SQL rather than
    /// filtered in Swift so the index earns its keep and the ordering is the
    /// one the list draws.
    public func items(in collectionID: String) throws -> [LibraryEntry] {
        try database.query(
            """
            SELECT \(Self.itemColumns) FROM prompt
            WHERE collection_id = ?
            ORDER BY is_pinned DESC, updated_at DESC
            """,
            [.text(collectionID)]
        ) { try decodeItem($0) }
    }

    private func decodeItem(_ row: Row) throws -> LibraryEntry {
        LibraryEntry(
            id: row.text(0),
            collectionID: row.text(6),
            title: (try? cipher.openString(row.blob(1))) ?? "",
            body: (try? cipher.openString(row.blob(2))) ?? "",
            isPinned: row.bool(3),
            createdAt: row.date(4),
            updatedAt: row.date(5)
        )
    }
```

And `upsert` gains the column:

```swift
    private func upsert(_ item: LibraryEntry) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO prompt
              (id, title, body, is_pinned, created_at, updated_at, collection_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id),
                .blob(try cipher.seal(item.title)),
                .blob(try cipher.seal(item.body)),
                .bool(item.isPinned),
                .date(item.createdAt),
                .date(item.updatedAt),
                .text(item.collectionID),
            ]
        )
    }
```

`createItem` takes the collection:

```swift
    @discardableResult
    public func createItem(
        collectionID: String,
        title: String? = nil,
        body: String,
        now: Date = Date()
    ) throws -> LibraryEntry? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }

        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LibraryEntry(
            collectionID: collectionID,
            title: (resolvedTitle?.isEmpty == false)
                ? resolvedTitle!
                : PromptTitle.propose(from: trimmedBody),
            body: trimmedBody,
            createdAt: now,
            updatedAt: now
        )
        try upsert(item)
        return item
    }

    /// Promote a clipboard entry into a collection — the `⇧S` action.
    ///
    /// Takes the destination rather than assuming one. Which collection `⇧S`
    /// aims at is the *caller's* rule (the first collection in tab order), and
    /// keeping it there means the store has no opinion to drift from the panel.
    @discardableResult
    public func promote(
        clipID: String,
        into collectionID: String,
        now: Date = Date()
    ) throws -> LibraryEntry? {
        guard let body = try text(for: clipID) else { return nil }
        return try createItem(collectionID: collectionID, body: body, now: now)
    }
```

- [ ] **Step 5: Add collection CRUD**

Append to `LocalStore+Library.swift`:

```swift
// MARK: - Collections

extension LocalStore {
    public func allCollections() throws -> [LibraryCollection] {
        try database.query(
            "SELECT id, name, symbol, position, created_at FROM collection ORDER BY position ASC"
        ) { row in
            let opened = try? cipher.openString(row.blob(1))
            return LibraryCollection(
                id: row.text(0),
                // Empty rather than a placeholder: the store does not write
                // interface copy. The view pairs `isUnreadable` with a `—`.
                name: opened ?? "",
                symbol: CollectionSymbol.fallback(row.text(2)),
                position: Int(row.int(3)),
                createdAt: row.date(4),
                isUnreadable: opened == nil
            )
        }
    }

    /// Create a collection at the end of the order.
    ///
    /// Returns `nil` at the cap rather than throwing: "you already have five
    /// tabs" is a UI state the `＋` button greys out for, not an error the user
    /// needs a dialog about.
    @discardableResult
    public func createCollection(
        name: String,
        symbol: CollectionSymbol,
        now: Date = Date()
    ) throws -> LibraryCollection? {
        let existing = try allCollections()
        guard existing.count < LibraryCollection.maximumCount else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collection = LibraryCollection(
            name: trimmed,
            symbol: symbol,
            position: existing.count,
            createdAt: now
        )
        try insert(collection)
        return collection
    }

    public func updateCollection(_ collection: LibraryCollection) throws {
        try database.execute(
            "UPDATE collection SET name = ?, symbol = ?, position = ? WHERE id = ?",
            [
                .blob(try cipher.seal(collection.name.trimmingCharacters(in: .whitespacesAndNewlines))),
                .text(collection.symbol.rawValue),
                .integer(Int64(collection.position)),
                .text(collection.id),
            ]
        )
    }

    /// Rewrite the whole order densely, in one transaction.
    ///
    /// Wholesale rather than by delta: five rows is nothing, and a partial
    /// rewrite is how two collections end up sharing a position and the tab bar
    /// starts flickering between two orders.
    public func reorderCollections(_ orderedIDs: [String]) throws {
        try database.transaction {
            for (position, id) in orderedIDs.enumerated() {
                try database.execute(
                    "UPDATE collection SET position = ? WHERE id = ?",
                    [.integer(Int64(position)), .text(id)]
                )
            }
        }
    }

    /// Delete a collection, either moving its members or taking them with it.
    ///
    /// One transaction, because the in-between state — a `collection_id`
    /// pointing at a row that is gone — is items present in the file and
    /// reachable from no tab. SQLite will not enforce that for us: the column
    /// carries no foreign key, because `ALTER TABLE ADD COLUMN` only accepts one
    /// when the default is NULL and this default has to be `'prompts'`.
    ///
    /// - Parameter destination: where the members go, or `nil` to delete them.
    public func deleteCollection(id: String, movingItemsTo destination: String?) throws {
        try database.transaction {
            if let destination {
                try database.execute(
                    "UPDATE prompt SET collection_id = ? WHERE collection_id = ?",
                    [.text(destination), .text(id)]
                )
            } else {
                try database.execute(
                    "DELETE FROM prompt WHERE collection_id = ?", [.text(id)]
                )
            }
            try database.execute("DELETE FROM collection WHERE id = ?", [.text(id)])
        }
    }

    /// The inverse of ``deleteCollection(id:movingItemsTo:)``.
    ///
    /// The collection goes back first, then its members — no item is ever
    /// momentarily homeless. `items` is the snapshot taken *before* the
    /// deletion, so a single upsert covers both cases: rows that were deleted
    /// are re-inserted, and rows that were moved have their `collection_id`
    /// rewritten back.
    public func restoreCollection(_ collection: LibraryCollection, items: [LibraryEntry]) throws {
        try database.transaction {
            try insert(collection)
            for item in items { try upsertItem(item) }
        }
    }

    private func insert(_ collection: LibraryCollection) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO collection (id, name, symbol, position, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                .text(collection.id),
                .blob(try cipher.seal(collection.name)),
                .text(collection.symbol.rawValue),
                .integer(Int64(collection.position)),
                .date(collection.createdAt),
            ]
        )
    }
}
```

Rename the private `upsert(_ item:)` to `upsertItem(_:)` so `restoreCollection`
can call it from the second extension, and update its call sites.

- [ ] **Step 6: Add the corruption hook the unreadable test needs**

```swift
    /// Test-only: replace a collection's sealed name with bytes this key cannot
    /// open, so the unreadable path is exercised rather than reasoned about.
    func corruptCollectionNameForTesting(id: String) throws {
        try database.execute(
            "UPDATE collection SET name = ? WHERE id = ?",
            [.blob(Data([0x00, 0x01, 0x02, 0x03])), .text(id)]
        )
    }
```

Internal, not public — `@testable import` reaches it.

- [ ] **Step 7: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

Expected: everything green. `LocalStoreTests.swift` will need the renames from
Step 3 applied; do that and nothing else.

- [ ] **Step 8: Prepared commit** *(run only if the user has asked to commit)*

```bash
git add -A swift/
git commit -m "feat: add the collection table and generalise the prompt tier into it"
```

---
### Task 7: `PanelTab` becomes an open list

**Files:**
- Modify: `swift/Sources/SwilClipCore/Selection/SelectionReducer.swift` (the `PanelTab` declaration only)
- Modify: `swift/Sources/SwilClipCore/Selection/PanelFocus.swift`
- Create: `swift/Tests/SwilClipCoreTests/TabNavigationTests.swift`

**Interfaces:**
- Consumes: Task 3.
- Produces: `PanelTab.clipboard` / `PanelTab.collection(String)`, `PanelTab.storageKey`,
  `PanelTab.collectionID`, `TopBarItem.newItem` (renamed from `.newPrompt`),
  and `PanelTab.topBarItems` derived from the case.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwilClipCoreTests/TabNavigationTests.swift
import Testing

@testable import SwilClipCore

@Suite("PanelTab")
struct PanelTabTests {
    /// The `＋` used to exist because the tab was *the* prompts tab. Now it
    /// exists because the tab is a collection — one rule instead of one name.
    @Test("every collection tab carries the add button; clipboard never does")
    func topBarStopsDeriveFromTheCase() {
        #expect(PanelTab.clipboard.topBarItems == [.tabs, .settings])
        #expect(PanelTab.collection("prompts").topBarItems == [.tabs, .newItem, .settings])
        #expect(PanelTab.collection("anything").topBarItems == [.tabs, .newItem, .settings])
    }

    @Test("tabs round-trip through a stable string form")
    func storageKeyRoundTrips() {
        #expect(PanelTab.clipboard.storageKey == "clipboard")
        #expect(PanelTab.collection("personal").storageKey == "collection:personal")
        #expect(PanelTab.clipboard.collectionID == nil)
        #expect(PanelTab.collection("personal").collectionID == "personal")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd swift && swift test --filter PanelTabTests 2>&1 | tail -20
```

Expected: FAIL — `.collection` and `.newItem` do not exist.

- [ ] **Step 3: Redeclare `PanelTab`**

In `SelectionReducer.swift`, replace the enum:

```swift
/// Which list the panel is showing.
///
/// ## Why this stays an enum
///
/// Flattening it to a bare id would make Clipboard just another string, and
/// Clipboard is genuinely not: it lives in another table, the pasteboard poller
/// writes it, it evicts, and it is read-only. That is the one special case worth
/// having in the type system — and putting it there is what lets `topBarItems`
/// stop asking *which tab is this* and start asking *what kind of tab is this*.
///
/// The consequence is that `PanelTab` is no longer `CaseIterable`: the set of
/// tabs is runtime data. So the reducer is *told* it, exactly as it is already
/// told `visibleIDs` and `actions`.
public enum PanelTab: Hashable, Sendable {
    case clipboard
    case collection(String)

    /// Stable string form, for `UserDefaults` keys and undo entries.
    public var storageKey: String {
        switch self {
        case .clipboard: "clipboard"
        case .collection(let id): "collection:\(id)"
        }
    }

    public var collectionID: String? {
        if case .collection(let id) = self { return id }
        return nil
    }
}
```

Delete the old `case prompts`. Every `.prompts` reference will now fail to
compile — that is the point, and fixing each one is how nothing gets missed.

- [ ] **Step 4: Rename `TopBarItem.newPrompt` and re-derive `topBarItems`**

In `PanelFocus.swift`:

```swift
public enum TopBarItem: String, Sendable, Equatable, CaseIterable, Identifiable {
    case tabs
    /// `＋`. Present on every collection tab and on no clipboard tab — a plus
    /// next to "Clipboard" would read as "add a clip", which is not a thing you
    /// can do. That is a judgement about the *glyph*, not about capability:
    /// pressing `n` on the clipboard still creates an item (see `KeyMapping`).
    case newItem
    case settings

    public var id: String { rawValue }
}

extension PanelTab {
    /// The stops this tab's top bar actually draws, left to right.
    public var topBarItems: [TopBarItem] {
        switch self {
        case .clipboard: [.tabs, .settings]
        case .collection: [.tabs, .newItem, .settings]
        }
    }
}
```

- [ ] **Step 5: Sweep the compiler errors**

```bash
cd swift
grep -rl "\.newPrompt\b" Sources Tests | xargs sed -i '' 's/\.newPrompt\b/.newItem/g'
swift build 2>&1 | grep "error:" | head -40
```

For each remaining `.prompts` error, substitute the right thing:
- `PanelTab.prompts` in a test fixture → `PanelTab.collection(LibraryCollection.Seed.prompts)`
- `selection.tab == .prompts` in `AppModel` → `selection.tab.collectionID != nil`
- `KeyCommand.newPrompt` → `KeyCommand.newItem`;
  `SelectionEffect.newPrompt` → `SelectionEffect.newItem`;
  `ShortcutAction.newPrompt` → `ShortcutAction.newItem`

Also rename `ShortcutGroup.prompts` → `.library`, and in `ShortcutAction.group`
the line `case .newItem, .editPrompt, .savePromptEditor, .cancelPromptEditor: .prompts`
→ `: .library`.

- [ ] **Step 6: Verify**

```bash
cd swift && swift test --filter PanelTabTests 2>&1 | tail -20
```

Expected: PASS, 2 tests. The rest of the suite may still fail — Task 8 finishes it.

---

### Task 8: The reducer is told which tabs exist

**Files:**
- Modify: `swift/Sources/SwilClipCore/Selection/SelectionReducer.swift`
- Modify: `swift/Tests/SwilClipCoreTests/TabNavigationTests.swift`

**Interfaces:**
- Consumes: Task 7.
- Produces: `reduce(_:_:visibleIDs:actions:tabs:)` with `tabs: [PanelTab] = [.clipboard]`;
  `KeyCommand.switchTabBackward`;
  `swapTab(current:incoming:from:to:)`;
  `reconcileTab(_:with:)`.

- [ ] **Step 1: Write the failing tests**

```swift
// append to Tests/SwilClipCoreTests/TabNavigationTests.swift
@Suite("Tab navigation over N tabs")
struct TabCyclingTests {
    private let tabs: [PanelTab] = [
        .clipboard, .collection("prompts"), .collection("personal"), .collection("work"),
    ]

    private func state(tab: PanelTab, focus: PanelFocus = .list) -> SelectionReducer.State {
        .init(selectedID: "a", tab: tab, focus: focus)
    }

    @Test("⇥ steps forward and wraps at the end")
    func forwardWraps() {
        var s = state(tab: .clipboard)
        for expected in tabs.dropFirst() + [.clipboard] {
            s = SelectionReducer.reduce(s, .switchTab, visibleIDs: ["a"], tabs: tabs).state
            #expect(s.tab == expected)
        }
    }

    @Test("⇧⇥ steps backward and wraps at the start")
    func backwardWraps() {
        let s = SelectionReducer.reduce(
            state(tab: .clipboard), .switchTabBackward, visibleIDs: ["a"], tabs: tabs
        )
        #expect(s.state.tab == .collection("work"))
        #expect(s.effect == .switchTab)
    }

    /// Wrapping is right here and wrong in the list, and the difference is not
    /// taste: a list is unbounded with both ends off-screen, a tab bar is four
    /// stops and all of them are drawn. Wrapping is safe exactly when the
    /// boundary is visible.
    @Test("a single tab has nowhere to go and emits no effect")
    func singleTabIsANoOp() {
        let outcome = SelectionReducer.reduce(
            state(tab: .clipboard), .switchTab, visibleIDs: ["a"], tabs: [.clipboard]
        )
        #expect(outcome.state.tab == .clipboard)
        #expect(outcome.effect == nil, "a no-op switch must not trigger a state handover")
    }

    @Test("switching tabs drops row focus but keeps the band")
    func focusRulesSurvive() {
        let fromRow = SelectionReducer.reduce(
            state(tab: .clipboard, focus: .row(action: .delete)),
            .switchTab, visibleIDs: ["a"], actions: [.pin, .delete], tabs: tabs
        )
        #expect(fromRow.state.focus == .list, "the next tab's rows carry different buttons")

        let fromBand = SelectionReducer.reduce(
            state(tab: .clipboard, focus: .tabs), .switchTab, visibleIDs: ["a"], tabs: tabs
        )
        #expect(fromBand.state.focus == .tabs, "the band is panel-wide, not per tab")
    }

    @Test("a stop the incoming tab lacks falls back to the tabs")
    func newItemStopIsDropped() {
        let outcome = SelectionReducer.reduce(
            .init(tab: .collection("work"), focus: .topBar(.newItem)),
            .switchTabBackward, visibleIDs: [], tabs: tabs
        )
        #expect(outcome.state.tab == .collection("personal"))
        #expect(outcome.state.focus == .topBar(.newItem), "personal is a collection too")

        let ontoClipboard = SelectionReducer.reduce(
            .init(tab: .collection("prompts"), focus: .topBar(.newItem)),
            .switchTabBackward, visibleIDs: [], tabs: tabs
        )
        #expect(ontoClipboard.state.tab == .clipboard)
        #expect(ontoClipboard.state.focus == .tabs, "clipboard has no ＋ to stand on")
    }
}

@Suite("Tab band arrows")
struct TabBandTests {
    private let tabs: [PanelTab] = [.clipboard, .collection("prompts"), .collection("personal")]

    @Test("→ walks the tabs first, and only then reaches ＋ and ⚙")
    func arrowsSpendThemselvesOnTabs() {
        var s = SelectionReducer.State(tab: .clipboard, focus: .tabs)

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.tab == .collection("prompts"))
        #expect(s.focus == .tabs)

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.tab == .collection("personal"))

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.tab == .collection("personal"), "the last tab does not wrap")
        #expect(s.focus == .topBar(.newItem), "it steps on to the buttons instead")

        s = SelectionReducer.reduce(s, .moveRight, visibleIDs: [], tabs: tabs).state
        #expect(s.focus == .topBar(.settings))
    }

    @Test("← from the first tab does nothing rather than wrapping onto the gear")
    func leftEdgeStops() {
        let s = SelectionReducer.reduce(
            .init(tab: .clipboard, focus: .tabs), .moveLeft, visibleIDs: [], tabs: tabs
        )
        #expect(s.state.tab == .clipboard)
        #expect(s.state.focus == .tabs)
    }
}

@Suite("reconcileTab")
struct ReconcileTabTests {
    /// The tab-level twin of `reconcile`. A selection pointing at a row that is
    /// gone is one keystroke from acting on the wrong thing; a `tab` pointing at
    /// a collection that is gone is that same sentence one dimension up.
    @Test("a deleted collection drops the panel back to clipboard")
    func deadTabFallsBack() {
        let s = SelectionReducer.reconcileTab(
            .init(selectedID: "x", query: "git", isSearching: true,
                  tab: .collection("gone"), expandedID: "x", focus: .row(action: .delete)),
            with: [.clipboard, .collection("prompts")]
        )
        #expect(s.tab == .clipboard)
        #expect(s.focus == .list)
        #expect(s.selectedID == nil)
        #expect(s.expandedID == nil)
        #expect(s.query.isEmpty)
        #expect(!s.isSearching, "the dead tab's search must not follow you")
    }

    @Test("someone standing in the band stays in the band")
    func bandSurvives() {
        let s = SelectionReducer.reconcileTab(
            .init(tab: .collection("gone"), focus: .topBar(.newItem)),
            with: [.clipboard]
        )
        #expect(s.tab == .clipboard)
        #expect(s.focus == .tabs, "ejecting someone out of the top bar mid-gesture is the SW-06 shape")
    }

    @Test("a live tab is left completely alone")
    func liveTabUntouched() {
        let original = SelectionReducer.State(selectedID: "x", query: "g", isSearching: true,
                                              tab: .collection("prompts"), focus: .list)
        #expect(SelectionReducer.reconcileTab(original, with: [.clipboard, .collection("prompts")]) == original)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd swift && swift test --filter TabCyclingTests 2>&1 | tail -30
```

Expected: FAIL — no `tabs:` parameter, no `.switchTabBackward`, no `reconcileTab`.

- [ ] **Step 3: Add the command case**

In `KeyCommand`, next to `switchTab`:

```swift
    case switchTab
    /// `⇧` plus the switch binding. A separate case rather than a payload on
    /// `switchTab`, so the ten existing `.switchTab` literals in the regression
    /// suite keep compiling and `documentedAction` stays flat.
    case switchTabBackward
```

- [ ] **Step 4: Add the `tabs:` parameter and the cycling helper**

Change the signature:

```swift
    /// - Parameter tabs: the tabs the bar is *currently drawing*, in order. The
    ///   third member of the same promise `visibleIDs` and `actions` make: the
    ///   reducer never assumes what is on screen, it is told. The default of a
    ///   lone clipboard is why every pre-existing call site still compiles, and
    ///   it degrades the feature *off* rather than pointing it somewhere wrong.
    public static func reduce(
        _ state: State,
        _ command: KeyCommand,
        visibleIDs: [String],
        actions: [RowAction] = [],
        tabs: [PanelTab] = [.clipboard]
    ) -> Outcome
```

Replace the `case .switchTab:` body with:

```swift
        case .switchTab:
            return cycleTab(next, offset: +1, tabs: tabs)

        case .switchTabBackward:
            return cycleTab(next, offset: -1, tabs: tabs)
```

And add the helper next to `stepTopBar`:

```swift
    /// `⇥` / `⇧⇥`: step through the tab ring.
    ///
    /// **Wrapping, unlike the list.** `neighbour(of:in:offset:)` refuses to wrap
    /// because a history list is unbounded and both ends are off-screen. A tab
    /// bar is at most six stops and every one of them is drawn. Wrapping is safe
    /// exactly when the boundary is visible.
    ///
    /// A one-tab panel emits **no effect**: the host treats `.switchTab` as a
    /// state handover, and handing a tab's state over to itself would park and
    /// re-adopt the same value for no reason.
    private static func cycleTab(_ state: State, offset: Int, tabs: [PanelTab]) -> Outcome {
        var next = state
        guard tabs.count > 1, let index = tabs.firstIndex(of: state.tab) else {
            return Outcome(state: next)
        }
        next.tab = tabs[(index + offset + tabs.count) % tabs.count]
        // The other tab's rows carry different buttons.
        if case .row = state.focus { next.focus = .list }
        // And its bar may have different stops: `＋` exists only on collections.
        if let item = state.focus.topBarItem, !next.tab.topBarItems.contains(item) {
            next.focus = .tabs
        }
        return Outcome(state: next, effect: .switchTab)
    }
```

- [ ] **Step 5: Teach the band's arrows about N tabs**

Replace `stepTopBar` entirely:

```swift
    /// `←` / `→` along the top bar.
    ///
    /// The tabs are a *group* of stops, and the arrows spend themselves inside
    /// it before carrying you out: from Clipboard, `→` lights the first
    /// collection, and only once you are on the last tab does another `→` reach
    /// `＋`. That keeps the commonest gesture — flipping between lists — one key,
    /// and it means you cannot land on `＋` while looking at the clipboard.
    ///
    /// **These arrows do not wrap, even though `⇥` does.** They have somewhere
    /// else to go; wrapping from the last tab back to the first would make `＋`
    /// and `⚙` unreachable by arrow entirely.
    private static func stepTopBar(
        _ state: State, _ offset: Int, from item: TopBarItem, tabs: [PanelTab]
    ) -> Outcome {
        var next = state
        let stops = state.tab.topBarItems

        if item == .tabs, let index = tabs.firstIndex(of: state.tab) {
            let target = index + offset
            if tabs.indices.contains(target) {
                next.tab = tabs[target]
                return Outcome(state: next, effect: .switchTab)
            }
            // Off the end of the tab group — fall through to the bar's other
            // stops. Going left, there are none, so this is a dead stop.
        }

        guard let index = stops.firstIndex(of: item) else {
            // A stop this tab does not have; the tabs are always present.
            next.focus = .tabs
            return Outcome(state: next)
        }
        let target = index + offset
        guard stops.indices.contains(target) else { return Outcome(state: next) }
        next.focus = .topBar(stops[target])
        return Outcome(state: next)
    }
```

Update `step(_:_:visibleIDs:actions:)` to take and forward `tabs`, and both
`.moveLeft` / `.moveRight` cases to pass it.

- [ ] **Step 6: Generalise `swapTab` and add `reconcileTab`**

```swift
    /// - Parameter targetTab: where the panel is going. Used to be derived by
    ///   negating a two-case enum; with an open list it has to be said.
    public static func swapTab(
        current: State,
        incoming: State,
        from previousTab: PanelTab,
        to targetTab: PanelTab
    ) -> (outgoing: State, adopted: State) {
        var outgoing = current
        outgoing.tab = previousTab

        var adopted = incoming
        adopted.tab = targetTab
        // Panel-wide, not per tab. Restoring the incoming tab's band drops
        // someone into the list mid-gesture and the next `⏎` copies a row and
        // closes the panel instead of entering the tab. That shipped once.
        adopted.focus = current.focus
        return (outgoing, adopted)
    }

    /// Re-anchor the *tab* against the tabs that actually exist.
    ///
    /// Deleting a collection deletes a tab, so this is ``reconcile`` one
    /// dimension up: a `tab` pointing at a collection that is gone is the state
    /// from which "acted on the wrong list" is one keystroke away.
    ///
    /// List-scoped fields are cleared because they described the dead tab. The
    /// host may overlay the destination tab's parked state afterwards; this
    /// function has no parking, so it leaves a clean slate rather than a stale
    /// one.
    public static func reconcileTab(_ state: State, with tabs: [PanelTab]) -> State {
        var next = state
        guard !tabs.contains(state.tab) else {
            if let item = next.focus.topBarItem, !next.tab.topBarItems.contains(item) {
                next.focus = .tabs
            }
            return next
        }
        next.tab = tabs.first ?? .clipboard
        // Only the band survives, and only as the band. Ejecting someone out of
        // the top bar because a background change removed a tab is the SW-06
        // failure wearing a different hat.
        next.focus = next.focus.isOnTopBar ? .tabs : .list
        next.selectedID = nil
        next.expandedID = nil
        next.query = ""
        next.isSearching = false
        return next
    }
```

- [ ] **Step 7: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

Expected: all Core tests pass. Existing `swapTab` call sites need the new `to:`
argument — that is compiler-forced and is the only edit allowed in
`SelectionReducerTests` / `PanelFocusTests`.

---

### Task 9: `⇧⇥` reaches the keyboard, and the reference documents it

**Files:**
- Modify: `swift/Sources/SwilClipCore/Selection/KeyMapping.swift`
- Modify: `swift/Sources/SwilClipCore/Selection/ShortcutReference.swift`
- Modify: `swift/Tests/SwilClipCoreTests/KeyMappingTests.swift`

**Interfaces:**
- Consumes: Task 8.
- Produces: `KeyBinding.reversed -> KeyBinding?`;
  `ShortcutAction.switchTabBackward`;
  `ShortcutReference.sections(summon:tabSwitch:tabSwitchBackward:)` where
  `tabSwitchBackward: String?`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwilClipCoreTests/KeyMappingTests.swift`:

```swift
@Suite("Reverse tab switching")
struct ReverseTabSwitchTests {
    private func command(
        keyCode: UInt16, modifiers: KeyModifiers, tabSwitch: KeyBinding = .tab
    ) -> KeyCommand? {
        KeyMapping.command(
            keyCode: keyCode, characters: "\t", charactersIgnoringModifiers: "\t",
            modifiers: modifiers, isSearching: false, tabSwitch: tabSwitch
        )
    }

    @Test("⇧⇥ is the reverse of the default ⇥")
    func shiftTabGoesBack() {
        #expect(command(keyCode: KeyCode.tab, modifiers: []) == .switchTab)
        #expect(command(keyCode: KeyCode.tab, modifiers: .shift) == .switchTabBackward)
    }

    @Test("the reverse follows a rebound key")
    func followsARebind() {
        let bound = KeyBinding(keyCode: KeyCode.space, modifiers: .command)
        #expect(command(keyCode: KeyCode.space, modifiers: .command, tabSwitch: bound) == .switchTab)
        #expect(
            command(keyCode: KeyCode.space, modifiers: [.command, .shift], tabSwitch: bound)
                == .switchTabBackward
        )
    }

    /// A binding that already carries ⇧ has no room for a reverse. Documented
    /// rather than worked around: `←`/`→` on the band reaches every tab anyway.
    @Test("a binding that already holds ⇧ has no reverse")
    func noRoomForAReverse() {
        let bound = KeyBinding(keyCode: KeyCode.tab, modifiers: .shift)
        #expect(bound.reversed == nil)
        #expect(command(keyCode: KeyCode.tab, modifiers: .shift, tabSwitch: bound) == .switchTab)
    }

    @Test("⇧⇥ while searching still switches tabs rather than typing a tab")
    func searchDoesNotSwallowIt() {
        let typed = KeyMapping.command(
            keyCode: KeyCode.tab, characters: "\t", charactersIgnoringModifiers: "\t",
            modifiers: .shift, isSearching: true, tabSwitch: .tab
        )
        #expect(typed == .switchTabBackward)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd swift && swift test --filter ReverseTabSwitchTests 2>&1 | tail -20
```

Expected: FAIL — no `reversed`, no `.switchTabBackward` from the mapper.

- [ ] **Step 3: Add `KeyBinding.reversed` and match it first**

In `KeyMapping.swift`, on `KeyBinding`:

```swift
    /// The same binding plus `⇧`, meaning "the other direction" — or `nil` when
    /// this binding already carries `⇧` and there is no room for one.
    public var reversed: KeyBinding? {
        guard !modifiers.contains(.shift) else { return nil }
        return KeyBinding(keyCode: keyCode, modifiers: modifiers.union(.shift))
    }
```

In `KeyMapping.command`, immediately after the existing forward check:

```swift
        if tabSwitch.matches(keyCode: keyCode, modifiers: modifiers) { return .switchTab }
        // Checked here, before the control/option guard and before search mode,
        // for the same reason the forward binding is: a user who maps switching
        // onto a key this function would otherwise claim still gets both
        // directions.
        if let reverse = tabSwitch.reversed,
           reverse.matches(keyCode: keyCode, modifiers: modifiers) {
            return .switchTabBackward
        }
```

- [ ] **Step 4: Document it**

In `ShortcutReference.swift`: add `case switchTabBackward` to `ShortcutAction`
(right after `switchTab`), put it in the `.navigate` group, and change the
signature:

```swift
    /// - Parameter tabSwitchBackward: `Settings.tabSwitchKey.reversed?.displayString`.
    ///   `nil` when the user's binding already carries `⇧`, in which case the
    ///   row is simply not drawn — a reference that printed a key which does
    ///   nothing would be worse than one that stays quiet.
    public static func sections(
        summon: String,
        tabSwitch: String,
        tabSwitchBackward: String?
    ) -> [ShortcutSection] {
```

In the `.navigate` section, after the `switchTab` entry:

```swift
                ShortcutEntry(.switchTab, keys: [tabSwitch]),
            ] + (tabSwitchBackward.map { [ShortcutEntry(.switchTabBackward, keys: [$0])] } ?? []) + [
                ShortcutEntry(.focusTabs, keys: ["↑"]),
```

And `documentedActions` uses a fully-populated call so the completeness test
still holds:

```swift
    public static var documentedActions: Set<ShortcutAction> {
        Set(
            sections(summon: "⌘⇧V", tabSwitch: "⇥", tabSwitchBackward: "⇧⇥")
                .flatMap(\.entries).map(\.action)
        )
    }
```

Add to `KeyCommand.documentedAction`:

```swift
        case .switchTabBackward: .switchTabBackward
```

- [ ] **Step 5: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

Expected: green, including `ShortcutReferenceTests` — which will fail loudly if
`Strings.label(for:)` has no copy for the new action. That is Task 11.

---

### Task 10: `Matcher` and `Strings` catch up

**Files:**
- Modify: `swift/Sources/SwilClipCore/Localization/Strings.swift`
- Modify: `swift/Sources/SwilClipCore/Search/Matcher.swift`
- Modify: `swift/Tests/SwilClipCoreTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: Tasks 4, 7, 9.
- Produces the new copy properties listed in Step 3. Removed:
  `searchPromptsPlaceholder`, `dividerLibrary`, `emptyPromptsTitle`,
  `emptyPromptsHint`, `statusSavedAsPrompt`, `newPromptTooltip`,
  `newPromptTitle`, `editPromptTitle`.

- [ ] **Step 1: Write the failing test**

Append to `LocalizationTests.swift`, inside `extension StringsTests`:

```swift
    @Test("collection copy exists in both languages and is not shared by accident")
    func collectionCopyIsComplete() {
        #expect(en.personalTab != zh.personalTab)
        #expect(en.collectionsSection != zh.collectionsSection)
        #expect(!en.statusNoCollections.isEmpty && !zh.statusNoCollections.isEmpty)
        #expect(en.searchCollectionPlaceholder("Personal").contains("Personal"))
        #expect(zh.searchCollectionPlaceholder("个人").contains("个人"))
        #expect(en.moveItemsButton(to: "Prompts", count: 7).contains("7"))
        #expect(zh.moveItemsButton(to: "提示词", count: 7).contains("7"))
        #expect(en.deleteCollectionButton(count: 7).contains("7"))
    }
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd swift && swift test --filter collectionCopyIsComplete 2>&1 | tail -20
```

Expected: FAIL — none of these properties exist.

- [ ] **Step 3: Write the copy**

In `Strings.swift`, in the panel-chrome section, **replace** the removed
properties and add the new ones. Full-width punctuation in the Chinese, and
footer labels stay two or three characters wide.

```swift
    public var clipboardTab: String { pick("Clipboard", "剪贴板") }
    /// Also the name the v3 migration seeds the first collection with.
    public var promptsTab: String { pick("Prompts", "提示词") }
    /// Ditto, for the second. From here on both are ordinary user data.
    public var personalTab: String { pick("Personal", "个人") }

    public var newItemTooltip: String { pick("New item (n)", "新建条目 (n)") }
    public func searchCollectionPlaceholder(_ name: String) -> String {
        pick("Search \(name)", "搜索\(name)")
    }
    public var dividerSaved: String { pick("Saved", "已保存") }
    /// Stands in for a collection whose sealed name will not open. Never blank —
    /// a nameless tab reads as "the app lost something".
    public var collectionUnreadable: String { pick("—", "—") }

    public var emptyCollectionTitle: String { pick("Nothing saved here yet", "这里还没有内容") }
    public var emptyCollectionHint: String {
        pick(
            "Press n to add one, or ⇧S on a clip to save it here.",
            "按 n 新建，或在剪贴板条目上按 ⇧S 存进来。"
        )
    }

    public func statusSavedTo(_ collection: String) -> String {
        pick("Saved to \(collection)", "已存入\(collection)")
    }
    public var statusNoCollections: String {
        pick("No collections — add one in Settings.", "还没有集合，请到设置里新建一个。")
    }

    // MARK: - Collections (Settings)

    public var collectionsPane: String { pick("Collections", "集合") }
    public var collectionsSection: String { pick("Collections", "集合") }
    public var collectionsHint: String {
        pick(
            "Tabs in the panel, left to right. ⇧S saves into the first one.",
            "面板顶栏从左到右的标签页。⇧S 会存进第一个。"
        )
    }
    public var newCollectionTooltip: String { pick("New collection", "新建集合") }
    public var collectionNamePlaceholder: String { pick("Name", "名称") }
    public func collectionCapHint(_ maximum: Int) -> String {
        pick("At most \(maximum) collections.", "最多 \(maximum) 个集合。")
    }
    public func deleteCollectionTitle(_ name: String) -> String {
        pick("Delete “\(name)”?", "删除「\(name)」？")
    }
    public func deleteCollectionBody(count: Int) -> String {
        pick(
            "It holds \(count) item(s). Undo is available from the panel with u.",
            "它里面有 \(count) 条内容。撤销请回到面板按 u。"
        )
    }
    public func moveItemsButton(to destination: String, count: Int) -> String {
        pick("Move \(count) to \(destination)", "把 \(count) 条移到\(destination)")
    }
    public func deleteCollectionButton(count: Int) -> String {
        pick("Delete the collection and \(count) item(s)", "连同 \(count) 条内容一起删除")
    }

    // MARK: - Editor

    public var fieldCollection: String { pick("Collection", "集合") }
    public var newItemTitle: String { pick("New item", "新建条目") }
    public var editItemTitle: String { pick("Edit item", "编辑条目") }

    public var errorDeleteCollection: (String) -> String {
        { detail in self.pick("Could not delete the collection: \(detail)", "删除集合失败：\(detail)") }
    }
```

> The `errorDeleteCollection` shape above matches whatever convention the other
> `error*` members already use in this file — check `errorDelete` and copy it
> exactly rather than introducing a second style.

Extend `label(for:)` with `.switchTabBackward` and rename `.newPrompt`:

```swift
        case .switchTabBackward: pick("Previous tab", "上一个标签页")
        case .newItem: pick("New item", "新建条目")
```

And `title(for:)` gains the renamed group:

```swift
        case .library: pick("Library", "库")
```

And `topBarLabel(_:)`:

```swift
        case .newItem: pick("new", "新建")
```

- [ ] **Step 4: Point `Matcher` at the renamed type**

The Task 4 sed already renamed `filter(_ prompts: [PromptItem])`. Rename the
parameter for readability only:

```swift
    public static func filter(_ items: [LibraryEntry], query: String) -> [LibraryEntry] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        return items.filter { matches(query: query, in: [$0.title, $0.body]) }
    }
```

- [ ] **Step 5: Verify the whole Core phase**

```bash
cd swift && swift test 2>&1 | tail -20
```

Expected: everything green. `LocalizationTests.shortcutCopyIsComplete` iterates
`ShortcutAction.allCases` and asserts non-empty copy, so a forgotten label fails
here rather than reaching a screen.

- [ ] **Step 6: Prepared commit** *(run only if the user has asked to commit)*

```bash
git add -A swift/
git commit -m "feat: generalise the panel's tab model from a pair to an ordered list"
```

---
## Phase M2 — the shell

Needs M0. This is the half the audit put ten of fourteen findings in, so every
task here lands a test in `SwilClipUITests` alongside the change.

---

### Task 11: `AppModel` holds an open list of tabs

**Files:**
- Modify: `swift/Sources/SwilClipUI/State/AppModel.swift`
- Modify: `swift/Tests/SwilClipUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 6, 8.
- Produces, on `AppModel`:
  - `private(set) var collections: [LibraryCollection]`
  - `private(set) var items: [LibraryEntry]`
  - `var tabs: [PanelTab]` — `[.clipboard]` plus one per collection, in order
  - `var visibleItems: [LibraryEntry]`
  - `var firstCollectionID: String?`
  - `func itemCount(in collectionID: String) -> Int`
  - `var onEditItem: ((LibraryEntry?, String) -> Void)?` *(replaces `onEditPrompt`)*

- [ ] **Step 1: Write the failing tests**

```swift
// append to Tests/SwilClipUITests/AppModelTests.swift
@Suite("AppModel — tabs")
struct AppModelTabTests {
    @MainActor
    @Test("the tab list is clipboard plus each collection, in stored order")
    func tabsFollowCollections() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        #expect(temp.model.tabs == [
            .clipboard,
            .collection(LibraryCollection.Seed.prompts),
            .collection(LibraryCollection.Seed.personal),
        ])
        #expect(temp.model.firstCollectionID == LibraryCollection.Seed.prompts)
    }

    @MainActor
    @Test("each tab keeps its own cursor and query across a switch")
    func perTabStateSurvives() async throws {
        let temp = try TempModel()
        await temp.model.recordForTesting(text: "one")
        await temp.model.recordForTesting(text: "two")
        await temp.model.refresh()

        let clipID = temp.model.visibleIDs[1]
        temp.model.handle(.selectID(clipID))
        temp.model.handle(.beginSearch)
        temp.model.handle(.appendToQuery("t"))

        temp.model.handle(.switchTab)
        #expect(temp.model.selection.tab == .collection(LibraryCollection.Seed.prompts))
        #expect(temp.model.selection.query.isEmpty, "the other tab's search must not follow")

        temp.model.handle(.switchTabBackward)
        #expect(temp.model.selection.tab == .clipboard)
        #expect(temp.model.selection.query == "t", "returning restores what you were doing")
        #expect(temp.model.selection.selectedID == clipID)
    }

    /// The tab-level version of "a selection pointing at a row that no longer
    /// exists". A stale parked entry would hand a resurrected id someone else's
    /// cursor.
    @MainActor
    @Test("deleting the current collection drops to clipboard and prunes its parked state")
    func deletedTabIsReconciled() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        temp.model.handle(.switchTab)
        temp.model.handle(.switchTab)
        #expect(temp.model.selection.tab == .collection(LibraryCollection.Seed.personal))

        try await temp.model.deleteCollection(
            id: LibraryCollection.Seed.personal, movingItemsTo: nil
        )

        #expect(temp.model.selection.tab == .clipboard)
        #expect(temp.model.tabs.count == 2)
        #expect(temp.model.parkedTabsForTesting == [.clipboard], "no orphan entries")
    }

    @MainActor
    @Test("items are scoped to the tab that is showing")
    func itemsAreScopedToTheTab() async throws {
        let temp = try TempModel()
        try await temp.model.createItemForTesting(
            collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "https://github.com/supwils"
        )
        try await temp.model.createItemForTesting(
            collectionID: LibraryCollection.Seed.prompts, title: "Handoff", body: "session handoff"
        )
        await temp.model.refresh()

        temp.model.handle(.switchTab)
        #expect(temp.model.visibleItems.map(\.title) == ["Handoff"])
        temp.model.handle(.switchTab)
        #expect(temp.model.visibleItems.map(\.title) == ["GitHub"])
        #expect(temp.model.itemCount(in: LibraryCollection.Seed.personal) == 1)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd swift && swift test --filter AppModelTabTests 2>&1 | tail -30
```

Expected: FAIL — no `tabs`, `visibleItems`, `parkedTabsForTesting`.

- [ ] **Step 3: Replace the data section**

```swift
    private(set) var clips: [ClipItem] = []
    private(set) var collections: [LibraryCollection] = []
    /// Every library item across every collection. Tens of entries of a few
    /// hundred characters, so one array filtered per render beats a dictionary
    /// that has to be kept in step with `collections`.
    private(set) var items: [LibraryEntry] = []

    /// The tabs the bar draws, left to right.
    ///
    /// Clipboard is pinned first and is not reorderable. That is not a
    /// convention — it is the one real special case: another table, written by
    /// the poller, evicting, read-only.
    var tabs: [PanelTab] { [.clipboard] + collections.map { .collection($0.id) } }

    /// Where `⇧S` and `n`-on-the-clipboard land.
    ///
    /// The first collection in tab order, with no preference key behind it. A
    /// stored destination could be deleted and would need a dangling-reference
    /// fallback; this cannot dangle, and the rule is *visible* — the order is
    /// drawn across the top bar, which makes it the least hidden state in the
    /// app. To change where clips land, move that collection to the front.
    var firstCollectionID: String? { collections.first?.id }

    /// Per-tab cursor, query and expansion, so returning to a tab does not
    /// silently reset what you were doing there. Keyed by tab, pruned whenever
    /// the tab list changes.
    private var parked: [PanelTab: SelectionReducer.State] = [:]

    /// Test-only view of the parking lot, so "no orphan entries" is an
    /// assertion rather than a hope.
    var parkedTabsForTesting: [PanelTab] {
        (parked.keys + [selection.tab]).uniqued().sorted { $0.storageKey < $1.storageKey }
    }
```

Add a tiny `uniqued()` helper in the same file, or use
`Array(Set(parked.keys).union([selection.tab]))` and sort — either is fine, but
pick one and use it consistently.

- [ ] **Step 4: Replace the derived views**

```swift
    var currentCollectionID: String? { selection.tab.collectionID }

    private var collectionItems: [LibraryEntry] {
        guard let id = currentCollectionID else { return [] }
        return items.filter { $0.collectionID == id }
    }

    var visibleItems: [LibraryEntry] {
        selection.isSearching
            ? Matcher.filter(collectionItems, query: selection.query)
            : collectionItems
    }

    var visibleIDs: [String] {
        currentCollectionID == nil ? visibleClips.map(\.id) : visibleItems.map(\.id)
    }

    var selectedRowActions: [RowAction] {
        guard let id = selection.selectedID else { return [] }
        if currentCollectionID == nil {
            return visibleClips.first { $0.id == id }?.rowActions ?? []
        }
        return visibleItems.first { $0.id == id }?.rowActions ?? []
    }

    var selectedItem: LibraryEntry? {
        guard let id = selection.selectedID else { return nil }
        return items.first { $0.id == id }
    }

    /// Count for the tab badge.
    func itemCount(in collectionID: String) -> Int {
        items.lazy.filter { $0.collectionID == collectionID }.count
    }
```

Delete `visiblePrompts`, `selectedPrompt`, and every `selection.tab == .prompts`
test — the question is now `currentCollectionID == nil`.

- [ ] **Step 5: Rework the tab handover and add tab reconciliation**

```swift
    func handle(_ command: KeyCommand) {
        let outcome = SelectionReducer.reduce(
            selection, command,
            visibleIDs: visibleIDs, actions: selectedRowActions, tabs: tabs
        )
        let previousTab = selection.tab
        let previousQuery = selection.query
        let previousSearching = selection.isSearching
        selection = outcome.state

        if previousTab != selection.tab {
            swapTabState(from: previousTab, to: selection.tab)
        }

        if selection.query != previousQuery || selection.isSearching != previousSearching {
            reconcileSelection()
        }

        guard let effect = outcome.effect else { return }
        perform(effect)
    }

    private func swapTabState(from previousTab: PanelTab, to targetTab: PanelTab) {
        let stored = parked[targetTab] ?? SelectionReducer.State(tab: targetTab)
        let (outgoing, adopted) = SelectionReducer.swapTab(
            current: selection, incoming: stored, from: previousTab, to: targetTab
        )
        parked[previousTab] = outgoing
        selection = adopted
        reconcileSelection()
    }

    /// Re-anchor the *tab* after the collection list changed underneath it.
    ///
    /// Two things, and both matter: the panel cannot be left sitting on a tab
    /// that no longer exists, and the parking lot cannot keep entries for tabs
    /// that are gone — a recreated collection reusing an id would inherit a
    /// stranger's cursor.
    private func reconcileTabs() {
        let live = tabs
        parked = parked.filter { live.contains($0.key) }

        let before = selection.tab
        selection = SelectionReducer.reconcileTab(selection, with: live)
        guard selection.tab != before else { return }
        // `reconcileTab` leaves a clean slate because Core has no parking;
        // overlay the destination's own state if we kept some.
        if let stored = parked[selection.tab] {
            selection.selectedID = stored.selectedID
            selection.query = stored.query
            selection.isSearching = stored.isSearching
            selection.expandedID = stored.expandedID
        }
    }
```

Call `reconcileTabs()` from `refresh()` **before** `reconcileSelection()`:

```swift
    func refresh() async {
        do {
            let loadedClips = try await store.allClips()
            let loadedCollections = try await store.allCollections()
            let loadedItems = try await store.allItems()
            clips = loadedClips
            collections = loadedCollections
            items = loadedItems
            // Order matters: the tab decides which list `visibleIDs` returns,
            // so it has to be valid before the selection is anchored against it.
            reconcileTabs()
            reconcileSelection()
        } catch {
            setStatus(strings.errorReadHistory("\(error)"))
        }
    }
```

- [ ] **Step 6: Retarget the effects**

```swift
    private func perform(_ effect: SelectionEffect) {
        switch effect {
        case .confirm(let id): confirm(id: id)
        case .delete(let id): Task { await delete(id: id) }
        case .togglePin(let id): Task { await togglePin(id: id) }
        case .toggleExpand: break
        case .undo: Task { await undo() }
        case .newItem: beginNewItem()
        case .promote(let id): Task { await promote(clipID: id) }
        case .edit(let id): beginEdit(id: id)
        case .openSettings: onOpenSettings?()
        case .switchTab: break // handled above, where both tabs' state is in hand
        case .dismiss: onDismiss?()
        }
    }

    /// `n` and `＋`. On a collection tab the new item goes there; on the
    /// clipboard it goes to the first collection, which is the same rule `⇧S`
    /// follows. The `＋` glyph is still absent from the clipboard's bar — that
    /// is a judgement about what a plus *reads* as next to the word
    /// "Clipboard", not a statement that the action is unavailable.
    private func beginNewItem() {
        guard let target = currentCollectionID ?? firstCollectionID else {
            setStatus(strings.statusNoCollections)
            return
        }
        onEditItem?(nil, target)
    }

    private func beginEdit(id: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        onEditItem?(item, item.collectionID)
    }
```

Rename the callback:

```swift
    /// Called when an item should be opened in the editor. The `String` is the
    /// collection the picker should start on.
    var onEditItem: ((LibraryEntry?, String) -> Void)?
```

Update `delete`, `togglePin`, `promote`, `deliver`, `expandedText` to branch on
`currentCollectionID == nil` and to call the renamed store methods
(`deleteItem`, `setItemPinned`, `restoreItems`, `restoreItemPinState`).
`promote` takes a destination:

```swift
    private func promote(clipID: String) async {
        guard let target = firstCollectionID,
              let collection = collections.first(where: { $0.id == target })
        else {
            setStatus(strings.statusNoCollections)
            return
        }
        do {
            guard try await store.promote(clipID: clipID, into: target) != nil else {
                setStatus(strings.statusOnlyTextPromotes)
                return
            }
            await refresh()
            // Never silent about the destination: the rule is "the first
            // collection", and the footer is where the user reads it back.
            setStatus(strings.statusSavedTo(collection.name))
        } catch {
            setStatus(strings.errorPromote("\(error)"))
        }
    }
```

Rename `UndoableOperation.deletedPrompts` → `deletedItems(items: [LibraryEntry])`.

- [ ] **Step 7: Add the test hooks**

```swift
    /// Test-only wrappers over the store, so the shell tests drive the same
    /// path the UI does rather than reaching around the model.
    func createItemForTesting(collectionID: String, title: String, body: String) async throws {
        try await store.createItem(collectionID: collectionID, title: title, body: body)
    }

    func deleteCollection(id: String, movingItemsTo destination: String?) async throws {
        try await store.deleteCollection(id: id, movingItemsTo: destination)
        await refresh()
    }
```

`deleteCollection` is production code — Task 17 adds the undo capture around it.

- [ ] **Step 8: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

Expected: green. `PanelController` will fail to compile on `onEditPrompt` —
that is Task 14; to keep the tree building now, rename the call site to
`onEditItem` and ignore the second argument temporarily.

---

### Task 12: The top bar's degradation ladder

**Files:**
- Modify: `swift/Sources/SwilClipUI/Views/PanelRootView.swift`

**Interfaces:**
- Consumes: Task 11.
- Produces: a `TabBar` that renders from `model.tabs` and degrades under width.

- [ ] **Step 1: Replace `TabBar`**

```swift
private struct TabBar: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    let tabs: [PanelTab]
    let current: PanelTab
    let focusedItem: TopBarItem?
    let strings: Strings
    let clipCount: Int
    let collections: [LibraryCollection]
    let itemCount: (String) -> Int
    let switchKeyLabel: String
    let onSelect: (PanelTab) -> Void
    let onNewItem: () -> Void
    let onOpenSettings: () -> Void

    /// What the bar gives up, in order, when it will not fit.
    ///
    /// The same device `FooterBar.hints` uses, and the order is as deliberate
    /// there as here: inactive counts go first because they are the least
    /// load-bearing thing on the bar, inactive names go second because an icon
    /// you chose yourself is a usable identifier. The active tab never
    /// degrades — losing the label for *where you are* is the one thing the bar
    /// exists to say.
    private enum Density { case full, noInactiveCounts, iconsOnly }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(.full)
            bar(.noInactiveCounts)
            bar(.iconsOnly)
        }
        .padding(.horizontal, metrics.edge)
        .padding(.bottom, 6 * metrics.scale)
    }

    private func bar(_ density: Density) -> some View {
        HStack(spacing: 2 * metrics.scale) {
            ForEach(tabs, id: \.storageKey) { tab in
                tabButton(tab, density: density)
            }
            Spacer(minLength: 0)
            Keycap(label: switchKeyLabel)
                .opacity(0.55)
            // Rendered from `current.topBarItems` — the same array the reducer
            // steps along — so a stop cannot exist in one and not the other.
            ForEach(current.topBarItems.filter { $0 != .tabs }) { item in
                RowActionButton(
                    symbol: item == .newItem ? "plus" : "gearshape",
                    help: item == .newItem ? strings.newItemTooltip : strings.settingsTooltip,
                    isFocused: focusedItem == item,
                    action: item == .newItem ? onNewItem : onOpenSettings
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func label(for tab: PanelTab) -> String {
        switch tab {
        case .clipboard: strings.clipboardTab
        case .collection(let id):
            guard let collection = collections.first(where: { $0.id == id }) else { return "" }
            // Never blank: a nameless tab reads as "the app lost something".
            return collection.isUnreadable ? strings.collectionUnreadable : collection.name
        }
    }

    private func symbol(for tab: PanelTab) -> String {
        switch tab {
        case .clipboard: "doc.on.clipboard"
        case .collection(let id):
            collections.first { $0.id == id }?.symbol.rawValue ?? CollectionSymbol.textQuote.rawValue
        }
    }

    private func count(for tab: PanelTab) -> Int {
        switch tab {
        case .clipboard: clipCount
        case .collection(let id): itemCount(id)
        }
    }

    private func tabButton(_ target: PanelTab, density: Density) -> some View {
        let isActive = target == current
        let showsName = isActive || density != .iconsOnly
        let showsCount = count(for: target) > 0 && (isActive || density == .full)

        return Button { onSelect(target) } label: {
            HStack(spacing: 4 * metrics.scale) {
                Image(systemName: symbol(for: target))
                    .font(.system(size: metrics.actionGlyph, weight: .medium))
                    .foregroundStyle(isActive ? Token.Foreground.strong : Token.Foreground.subtle)
                if showsName {
                    Text(label(for: target))
                        .font(metrics.brandFont)
                        .lineLimit(1)
                        .foregroundStyle(
                            isActive ? Token.Foreground.strong : Token.Foreground.subtle
                        )
                }
                if showsCount {
                    Text("\(count(for: target))")
                        .font(metrics.badgeFont)
                        .foregroundStyle(isActive ? theme.accent : Token.Foreground.faint)
                }
            }
            .padding(.horizontal, 7 * metrics.scale)
            .padding(.vertical, 3 * metrics.scale)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                        .fill(focusedItem == .tabs ? theme.accentSoft : Token.Surface.soft)
                }
            }
            .overlay {
                if isActive && focusedItem == .tabs {
                    RoundedRectangle(cornerRadius: metrics.radiusSM, style: .continuous)
                        .strokeBorder(theme.accent, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Update the call site in `PanelRootView.body`**

```swift
                TabBar(
                    tabs: model.tabs,
                    current: model.selection.tab,
                    focusedItem: model.selection.focus.topBarItem,
                    strings: strings,
                    clipCount: model.clips.count,
                    collections: model.collections,
                    itemCount: { model.itemCount(in: $0) },
                    switchKeyLabel: model.settings.tabSwitchKey.displayString,
                    onSelect: { tab in
                        guard tab != model.selection.tab, let index = model.tabs.firstIndex(of: tab)
                        else { return }
                        // Clicking a tab is the same command the keyboard emits,
                        // repeated — so the click cannot take a second path with
                        // its own idea of what a handover is.
                        let current = model.tabs.firstIndex(of: model.selection.tab) ?? 0
                        let command: KeyCommand = index > current ? .switchTab : .switchTabBackward
                        for _ in 0..<abs(index - current) { model.handle(command) }
                    },
                    onNewItem: { model.handle(.newItem) },
                    onOpenSettings: { model.onOpenSettings?() }
                )
```

- [ ] **Step 3: Route the list and the search placeholder by tab kind**

In `body`, the search field:

```swift
                if model.selection.isSearching {
                    SearchField(
                        query: model.selection.query,
                        placeholder: model.currentCollectionID == nil
                            ? strings.searchHistoryPlaceholder
                            : strings.searchCollectionPlaceholder(
                                model.collections
                                    .first { $0.id == model.currentCollectionID }?.name ?? ""
                            )
                    )
                    .padding(.top, 6 * metrics.scale)
                }
```

And in `list`, `if model.currentCollectionID == nil { clipRows } else { itemRows }`.
Rename `promptRows` → `itemRows`, drive it from `model.visibleItems`, use
`strings.emptyCollectionTitle` / `.emptyCollectionHint` and
`strings.dividerSaved`.

- [ ] **Step 4: Verify by eye**

```bash
cd swift && swift build && ./scripts/bundle.sh --release
```

Launch, then check all three rungs of the ladder by switching panel size in
Settings (Large → Medium → Small) with four collections present. Confirm the
active tab always keeps icon + name + count, and that the bar never clips.

---
### Task 13: `PromptRowView` → `LibraryRowView`

**Files:**
- Move: `swift/Sources/SwilClipUI/Views/PromptRowView.swift` → `Views/LibraryRowView.swift`
- Modify: `swift/Sources/SwilClipUI/Views/PanelRootView.swift`

**Interfaces:**
- Consumes: Tasks 4, 11.
- Produces: `LibraryRowView(item:symbol:isSelected:query:isExpanded:focusedAction:onSelect:onConfirm:onAction:)`.

- [ ] **Step 1: Rename**

```bash
cd swift
git mv Sources/SwilClipUI/Views/PromptRowView.swift Sources/SwilClipUI/Views/LibraryRowView.swift
grep -rl "PromptRowView" Sources | xargs sed -i '' 's/\bPromptRowView\b/LibraryRowView/g'
```

- [ ] **Step 2: Take the glyph from the collection**

The chip currently hard-codes `Image(systemName: "text.quote")`. Replace the
stored property `let prompt: LibraryEntry` with:

```swift
    let item: LibraryEntry
    /// The glyph of the collection this row lives in.
    ///
    /// Passed in rather than looked up: the row does not get to know about the
    /// collection list, and the tab bar and the row must not each derive the
    /// symbol from their own copy of it.
    let symbol: CollectionSymbol
```

and the chip's overlay with:

```swift
                    Image(systemName: symbol.rawValue)
```

Then `sed 's/\bprompt\./item./g'` inside this file only, and rename the
`prompt:` label at the call site.

- [ ] **Step 3: Update `itemRows` in `PanelRootView`**

```swift
    @ViewBuilder
    private var itemRows: some View {
        let items = model.visibleItems
        let symbol = model.collections
            .first { $0.id == model.currentCollectionID }?.symbol ?? .textQuote
        if items.isEmpty {
            EmptyState(
                symbol: model.selection.isSearching ? "magnifyingglass" : symbol.rawValue,
                title: model.selection.isSearching
                    ? strings.emptyNoMatchesTitle : strings.emptyCollectionTitle,
                hint: model.selection.isSearching
                    ? strings.emptyNoMatchesHint : strings.emptyCollectionHint
            )
            .frame(height: metrics.panelHeight / 2)
        } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if isFirstUnpinned(at: index, in: items) {
                    SectionDivider(label: strings.dividerSaved)
                }
                LibraryRowView(
                    item: item,
                    symbol: symbol,
                    isSelected: model.selection.selectedID == item.id,
                    query: model.selection.isSearching ? model.selection.query : "",
                    isExpanded: model.selection.expandedID == item.id,
                    focusedAction: focusedAction(for: item.id),
                    onSelect: { model.handle(.selectID(item.id)) },
                    onConfirm: {
                        model.handle(.selectID(item.id))
                        model.handle(.confirm)
                    },
                    onAction: { action in
                        model.handle(.selectID(item.id))
                        model.handle(action.command)
                    }
                )
                .id(item.id)
            }
        }
    }
```

- [ ] **Step 4: Verify**

```bash
cd swift && swift build 2>&1 | tail -20
```

Expected: builds, apart from the editor (Task 14).

---

### Task 14: `LibraryEditorView` — the collection picker, reachable by keyboard

**Files:**
- Move: `swift/Sources/SwilClipUI/Views/PromptEditorView.swift` → `Views/LibraryEditorView.swift`
- Modify: `swift/Sources/SwilClipUI/Panel/PanelController.swift`

**Interfaces:**
- Consumes: Tasks 4, 11, 13.
- Produces: `LibraryEditorView(item:collections:initialCollectionID:onCancel:onSave:)`
  where `onSave: (String, String, String) -> Void` is `(title, body, collectionID)`.

- [ ] **Step 1: Rename and restate the type**

```bash
cd swift
git mv Sources/SwilClipUI/Views/PromptEditorView.swift Sources/SwilClipUI/Views/LibraryEditorView.swift
grep -rl "PromptEditorView" Sources | xargs sed -i '' 's/\bPromptEditorView\b/LibraryEditorView/g'
```

Replace the stored properties and `init`:

```swift
    let item: LibraryEntry?
    let collections: [LibraryCollection]
    let onCancel: () -> Void
    /// `(title, body, collectionID)`. The collection is part of saving, not a
    /// separate "move" command — the picker *is* the move affordance, which is
    /// why there is no third verb anywhere in the app for it.
    let onSave: (String, String, String) -> Void

    @State private var title: String
    @State private var body_: String
    @State private var collectionID: String
    @State private var titleIsManual: Bool
    @FocusState private var focus: Field?

    /// Ordered, because `⇥` walks them in this order and the order is the
    /// reading order of the form.
    private enum Field: CaseIterable { case title, body, collection }

    init(
        item: LibraryEntry?,
        collections: [LibraryCollection],
        initialCollectionID: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, String) -> Void
    ) {
        self.item = item
        self.collections = collections
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? "")
        _body_ = State(initialValue: item?.body ?? "")
        _collectionID = State(initialValue: item?.collectionID ?? initialCollectionID)
        _titleIsManual = State(initialValue: item != nil)
    }
```

Update the header text to `strings.newItemTitle` / `strings.editItemTitle` and
the save button to `onSave(title, body_, collectionID)`.

- [ ] **Step 2: Add the picker as a third field**

Inside the `VStack(alignment: .leading, spacing: 12)`, after the body field:

```swift
                field(label: strings.fieldCollection) {
                    Picker("", selection: $collectionID) {
                        ForEach(collections) { collection in
                            Label(
                                collection.isUnreadable
                                    ? strings.collectionUnreadable : collection.name,
                                systemImage: collection.symbol.rawValue
                            )
                            .tag(collection.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .focused($focus, equals: .collection)
                }
```

- [ ] **Step 3: Wire `⇥`**

`roadmap.md` 2.2 records that `⇥` between the fields was never handled, making
the editor the one place in the app that needs the mouse. A third control makes
that a blocker, not a wart.

Add to the outer `VStack` in `body`, next to `.onAppear`:

```swift
        // The editor owns its keyboard the same way the panel does. Without
        // this, AppKit's own ring decides where ⇥ goes, and a picker that the
        // keyboard cannot reach is a control that does not exist for anyone
        // driving this app the way it is meant to be driven.
        .onKeyPress(.tab) {
            let order = Field.allCases
            guard let current = focus, let index = order.firstIndex(of: current) else {
                focus = .title
                return .handled
            }
            focus = order[(index + 1) % order.count]
            return .handled
        }
```

- [ ] **Step 4: Rewire `PanelController`**

```swift
        model.onEditItem = { [weak self] item, collectionID in
            self?.presentEditor(for: item, startingIn: collectionID)
        }
```

```swift
    private func presentEditor(for item: LibraryEntry?, startingIn collectionID: String) {
        guard editorWindow == nil else { return }

        let editor = LibraryEditorView(
            item: item,
            collections: model.collections,
            initialCollectionID: collectionID,
            onCancel: { [weak self] in self?.dismissEditor() },
            onSave: { [weak self] title, body, target in
                guard let self else { return }
                Task {
                    await self.model.saveItem(
                        id: item?.id, title: title, body: body, collectionID: target
                    )
                    self.dismissEditor()
                }
            }
        )

        let window = Self.makeSheetWindow(
            size: LibraryEditorView.preferredSize,
            content: Localized(settings: settings) { editor }
        )
        editorWindow = window
        panel?.beginSheet(window) { [weak self] _ in self?.editorWindow = nil }
    }
```

- [ ] **Step 5: Replace `AppModel.savePrompt`**

```swift
    func saveItem(id: String?, title: String, body: String, collectionID: String) async {
        do {
            if let id, var existing = items.first(where: { $0.id == id }) {
                existing.title = title
                existing.body = body
                // Changing this in the editor *is* the move. Saving writes the
                // membership like any other field, so there is no second code
                // path that could disagree about where the item lives.
                existing.collectionID = collectionID
                try await store.updateItem(existing)
            } else {
                try await store.createItem(collectionID: collectionID, title: title, body: body)
            }
            await refresh()
        } catch {
            setStatus(strings.errorSavePrompt("\(error)"))
        }
    }
```

- [ ] **Step 6: Verify**

```bash
cd swift && swift test 2>&1 | tail -20 && ./scripts/bundle.sh --release
```

Then by hand, on the device build:
1. `n` on a collection tab → editor opens with that collection preselected.
2. `⇥` cycles Title → Body → Collection → Title. **No mouse.**
3. Change the collection on an existing item, save, confirm it moved tabs.
4. `⌘⏎` saves, `⎋` cancels.

---

### Task 15: `⇧S`, `n`, and the zero-collection state

**Files:**
- Modify: `swift/Sources/SwilClipUI/Views/PanelRootView.swift` (footer hints)
- Modify: `swift/Tests/SwilClipUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: Tasks 11, 14.
- Produces: no new API — this task proves the targeting rules and covers the
  state the equality model makes reachable.

- [ ] **Step 1: Write the failing tests**

```swift
// append to Tests/SwilClipUITests/AppModelTests.swift
@Suite("AppModel — save targets")
struct SaveTargetTests {
    @MainActor
    @Test("⇧S lands in the first collection, and says so")
    func promoteTargetsTheFirstCollection() async throws {
        let temp = try TempModel()
        await temp.model.recordForTesting(text: "https://github.com/supwils")
        await temp.model.refresh()
        temp.model.handle(.selectID(temp.model.visibleIDs[0]))

        temp.model.handle(.promoteToPrompt)
        try await Task.sleep(for: .milliseconds(50))

        #expect(temp.model.itemCount(in: LibraryCollection.Seed.prompts) == 1)
        #expect(temp.model.statusMessage?.contains("Prompts") == true)
        #expect(temp.model.clips.count == 1, "promoting never removes the clip")
    }

    /// The rule is "the first collection in tab order", and the order is drawn
    /// across the top bar — so reordering *is* the way to change the target.
    @MainActor
    @Test("reordering the collections retargets ⇧S")
    func reorderingRetargets() async throws {
        let temp = try TempModel()
        try await temp.model.reorderCollections(
            [LibraryCollection.Seed.personal, LibraryCollection.Seed.prompts]
        )
        await temp.model.recordForTesting(text: "https://github.com/supwils")
        await temp.model.refresh()
        temp.model.handle(.selectID(temp.model.visibleIDs[0]))

        temp.model.handle(.promoteToPrompt)
        try await Task.sleep(for: .milliseconds(50))
        #expect(temp.model.itemCount(in: LibraryCollection.Seed.personal) == 1)
    }

    /// Deleting every collection is reachable under the equality model, so it
    /// is defined rather than assumed away. Nothing is auto-created: the user
    /// deleted them on purpose, and a tool that silently rebuilds one is a tool
    /// that argues with you.
    @MainActor
    @Test("with no collections at all, saving points at Settings instead of guessing")
    func zeroCollections() async throws {
        let temp = try TempModel()
        try await temp.model.deleteCollection(id: LibraryCollection.Seed.prompts, movingItemsTo: nil)
        try await temp.model.deleteCollection(id: LibraryCollection.Seed.personal, movingItemsTo: nil)
        await temp.model.recordForTesting(text: "orphan")
        await temp.model.refresh()

        #expect(temp.model.tabs == [.clipboard])
        #expect(temp.model.firstCollectionID == nil)
        #expect(temp.model.selection.tab.topBarItems == [.tabs, .settings], "no ＋ to press")

        temp.model.handle(.selectID(temp.model.visibleIDs[0]))
        temp.model.handle(.promoteToPrompt)
        try await Task.sleep(for: .milliseconds(50))
        #expect(temp.model.statusMessage == temp.settings.strings.statusNoCollections)

        temp.model.handle(.newItem)
        #expect(temp.model.statusMessage == temp.settings.strings.statusNoCollections)
    }
}
```

Add the `reorderCollections` passthrough on `AppModel` if Task 11 did not:

```swift
    func reorderCollections(_ orderedIDs: [String]) async throws {
        try await store.reorderCollections(orderedIDs)
        await refresh()
    }
```

- [ ] **Step 2: Run and watch it fail, then make it pass**

```bash
cd swift && swift test --filter SaveTargetTests 2>&1 | tail -30
```

Most of this should already pass from Task 11. Fix whatever does not — the
likely gap is `beginNewItem` not posting `statusNoCollections`.

- [ ] **Step 3: Make the footer hint follow the tab kind**

In `FooterBar.reel`, replace the `isClipboard` branch:

```swift
        let isClipboard = model.currentCollectionID == nil

            if labels != .minimal {
                if isClipboard {
                    KeyHint(keys: ["⇧S"], label: labels == .full ? strings.hintSaveAsPrompt : "")
                } else {
                    KeyHint(keys: ["n"], label: labels == .full ? strings.hintNew : "")
                }
            }
```

and the tab hint, which can no longer name "the other tab" because there may be
four:

```swift
            // With more than two tabs there is no single "other" one to name, so
            // the keycap stands alone. It is still always present: the switch key
            // is rebindable, and it is the one hint convention cannot supply.
            KeyHint(keys: [tabKey], label: "")
```

- [ ] **Step 4: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

- [ ] **Step 5: Prepared commit** *(run only if the user has asked to commit)*

```bash
git add -A swift/
git commit -m "feat: render an open list of tabs and save into the collection you pick"
```

---
## Phase M3 — managing collections

Needs M0 for the tests and **roadmap 2.1.3** (undo-stack round trips) before
Task 17 — this is where a new undo operation joins the stack.

---

### Task 16: The Collections pane

Creating a tab is a few-times-a-year action and the panel is a high-frequency
surface, so management lives in Settings. ADR-0002 already paid once for "the
panel now has a mode".

**Files:**
- Create: `swift/Sources/SwilClipUI/Views/CollectionsPane.swift`
- Modify: `swift/Sources/SwilClipUI/Views/SettingsView.swift`
- Modify: `swift/Sources/SwilClipUI/Panel/PanelController.swift`
- Modify: `swift/Tests/SwilClipUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: Tasks 6, 11.
- Produces: `CollectionsPane(model:)`;
  `SettingsView(settings:model:onClose:)`;
  on `AppModel`: `createCollection(name:symbol:) async -> Bool`,
  `updateCollection(_:) async`, `reorderCollections(_:) async throws`.

- [ ] **Step 1: Write the failing tests**

```swift
// append to Tests/SwilClipUITests/AppModelTests.swift
@Suite("AppModel — collection management")
struct CollectionManagementTests {
    @MainActor
    @Test("creating a collection adds a tab at the end")
    func createAppendsATab() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        #expect(await temp.model.createCollection(name: "Work", symbol: .briefcase))
        #expect(temp.model.tabs.count == 4)
        #expect(temp.model.collections.last?.name == "Work")
    }

    @MainActor
    @Test("the cap is enforced and reported, not silently ignored")
    func capIsEnforced() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        for index in 0..<(LibraryCollection.maximumCount - 2) {
            #expect(await temp.model.createCollection(name: "C\(index)", symbol: .tag))
        }
        #expect(await temp.model.createCollection(name: "over", symbol: .tag) == false)
        #expect(temp.model.collections.count == LibraryCollection.maximumCount)
    }

    @MainActor
    @Test("renaming a collection renames its tab, and the item stays put")
    func renameKeepsMembership() async throws {
        let temp = try TempModel()
        try await temp.model.createItemForTesting(
            collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "u"
        )
        await temp.model.refresh()

        var personal = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!
        personal.name = "Me"
        personal.symbol = .link
        await temp.model.updateCollection(personal)

        let back = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!
        #expect(back.name == "Me")
        #expect(back.symbol == .link)
        #expect(temp.model.itemCount(in: LibraryCollection.Seed.personal) == 1)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd swift && swift test --filter CollectionManagementTests 2>&1 | tail -30
```

- [ ] **Step 3: Add the model passthroughs**

```swift
    // MARK: - Collections

    /// - Returns: `false` at the cap. Not an error: "you already have five
    ///   tabs" is a state the `＋` greys out for, not something to interrupt
    ///   anyone about.
    @discardableResult
    func createCollection(name: String, symbol: CollectionSymbol) async -> Bool {
        do {
            let made = try await store.createCollection(name: name, symbol: symbol)
            await refresh()
            return made != nil
        } catch {
            setStatus(strings.errorSavePrompt("\(error)"))
            return false
        }
    }

    func updateCollection(_ collection: LibraryCollection) async {
        do {
            try await store.updateCollection(collection)
            await refresh()
        } catch {
            setStatus(strings.errorSavePrompt("\(error)"))
        }
    }
```

`reorderCollections` and `deleteCollection` already exist from Tasks 11 and 15.

- [ ] **Step 4: Write the pane**

```swift
// Sources/SwilClipUI/Views/CollectionsPane.swift
import SwiftUI
import SwilClipCore

/// Create, rename, re-icon, reorder and delete collections.
///
/// A separate file because `SettingsView` was already the largest in the tree at
/// 664 lines, and this pane is a self-contained responsibility: it is the only
/// place the tab list is edited, and nothing else in Settings needs the model.
struct CollectionsPane: View {
    @Bindable var model: AppModel
    @Environment(\.strings) private var strings
    @Environment(\.theme) private var theme

    @State private var pendingDeletion: LibraryCollection?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(model.collections) { collection in
                row(collection)
            }
            Text(strings.collectionCapHint(LibraryCollection.maximumCount))
                .font(Token.Typography.meta)
                .foregroundStyle(Token.Foreground.faint)
        }
        .confirmationDialog(
            pendingDeletion.map { strings.deleteCollectionTitle(displayName($0)) } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            deletionButtons
        } message: {
            if let pendingDeletion {
                Text(strings.deleteCollectionBody(count: model.itemCount(in: pendingDeletion.id)))
            }
        }
    }

    private var header: some View {
        HStack {
            Text(strings.collectionsSection)
                .font(Token.Typography.sectionLabel)
                .foregroundStyle(Token.Foreground.primary)
            Spacer()
            Button {
                Task { await model.createCollection(name: "", symbol: .tag) }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help(strings.newCollectionTooltip)
            .disabled(model.collections.count >= LibraryCollection.maximumCount)
        }
    }

    private func row(_ collection: LibraryCollection) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: symbolBinding(collection)) {
                ForEach(CollectionSymbol.allCases) { symbol in
                    Image(systemName: symbol.rawValue).tag(symbol)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)

            TextField(strings.collectionNamePlaceholder, text: nameBinding(collection))
                .textFieldStyle(.plain)
                .font(Token.Typography.body)

            Button { move(collection, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .disabled(collection.position == 0)
            Button { move(collection, by: +1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .disabled(collection.position == model.collections.count - 1)

            Button { pendingDeletion = collection } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(Token.Foreground.muted)
        }
        .padding(8)
        .background(
            Token.Surface.sunk,
            in: RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
        )
    }

    /// Two buttons, and no guessing which one you meant.
    ///
    /// The non-destructive one is listed first and is the default. Settings is a
    /// separate `NSHostingView`, so `u` does not reach it — backstopping data
    /// loss with a cross-window undo is too thin for a project whose stated
    /// ordering puts silent data loss above new features.
    @ViewBuilder
    private var deletionButtons: some View {
        if let collection = pendingDeletion {
            let count = model.itemCount(in: collection.id)
            let destination = model.collections.first { $0.id != collection.id }

            if count > 0, let destination {
                Button(strings.moveItemsButton(to: displayName(destination), count: count)) {
                    delete(collection, movingTo: destination.id)
                }
            }
            Button(
                count > 0 ? strings.deleteCollectionButton(count: count) : strings.delete,
                role: .destructive
            ) {
                delete(collection, movingTo: nil)
            }
            Button(strings.cancel, role: .cancel) { pendingDeletion = nil }
        }
    }

    private func delete(_ collection: LibraryCollection, movingTo destination: String?) {
        pendingDeletion = nil
        Task { await model.deleteCollectionWithUndo(collection, movingItemsTo: destination) }
    }

    private func move(_ collection: LibraryCollection, by offset: Int) {
        var ids = model.collections.map(\.id)
        guard let index = ids.firstIndex(of: collection.id),
              ids.indices.contains(index + offset)
        else { return }
        ids.swapAt(index, index + offset)
        Task { try? await model.reorderCollections(ids) }
    }

    private func displayName(_ collection: LibraryCollection) -> String {
        collection.isUnreadable ? strings.collectionUnreadable : collection.name
    }

    private func nameBinding(_ collection: LibraryCollection) -> Binding<String> {
        Binding(
            get: { collection.name },
            set: { newValue in
                var updated = collection
                updated.name = newValue
                Task { await model.updateCollection(updated) }
            }
        )
    }

    private func symbolBinding(_ collection: LibraryCollection) -> Binding<CollectionSymbol> {
        Binding(
            get: { collection.symbol },
            set: { newValue in
                var updated = collection
                updated.symbol = newValue
                Task { await model.updateCollection(updated) }
            }
        )
    }
}
```

Add `strings.delete` if the catalog has no plain "Delete" yet:
`public var delete: String { pick("Delete", "删除") }`.

- [ ] **Step 5: Hang the pane off `SettingsView`**

Add `case collections` to the existing `Pane` enum, a segment for it in the
header switcher (label `strings.collectionsPane`), and:

```swift
    @Bindable var model: AppModel
    ...
        case .collections:
            CollectionsPane(model: model)
```

Then update the two call sites:

```swift
    // PanelController.presentSettings()
    let view = SettingsView(settings: settings, model: model) { [weak self] in
        self?.dismissSettings()
    }
```

The pane reads `strings`/`theme` from the environment, and `SettingsView` is a
standalone `NSHostingView` — so wrap the content in `Localized` the way the
editor already is, or pass the values down explicitly. Match whatever
`SettingsView` does today; do not introduce a second convention.

- [ ] **Step 6: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

---

### Task 17: Deleting a collection is undoable

**Files:**
- Modify: `swift/Sources/SwilClipUI/State/AppModel.swift`
- Modify: `swift/Tests/SwilClipUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: Tasks 6, 16.
- Produces: `AppModel.deleteCollectionWithUndo(_:movingItemsTo:) async` and the
  `UndoableOperation.deletedCollection(collection:items:)` case.

- [ ] **Step 1: Write the failing tests**

```swift
// append to Tests/SwilClipUITests/AppModelTests.swift
@Suite("AppModel — collection undo")
struct CollectionUndoTests {
    @MainActor
    @Test("undo brings back a collection whose items were deleted with it")
    func undoAfterHardDelete() async throws {
        let temp = try TempModel()
        try await temp.model.createItemForTesting(
            collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "u"
        )
        await temp.model.refresh()
        let doomed = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!

        await temp.model.deleteCollectionWithUndo(doomed, movingItemsTo: nil)
        #expect(temp.model.tabs.count == 2)
        #expect(temp.model.items.isEmpty)

        temp.model.handle(.undo)
        try await Task.sleep(for: .milliseconds(50))
        #expect(temp.model.tabs.count == 3)
        #expect(temp.model.itemCount(in: LibraryCollection.Seed.personal) == 1)
    }

    /// One operation covers both buttons, because the snapshot is taken before
    /// the change and `LibraryEntry` carries its own `collectionID`: deleted rows
    /// are re-inserted, moved rows have their membership rewritten back.
    @MainActor
    @Test("undo also un-moves items that were relocated instead of deleted")
    func undoAfterMove() async throws {
        let temp = try TempModel()
        try await temp.model.createItemForTesting(
            collectionID: LibraryCollection.Seed.personal, title: "GitHub", body: "u"
        )
        await temp.model.refresh()
        let doomed = temp.model.collections.first { $0.id == LibraryCollection.Seed.personal }!

        await temp.model.deleteCollectionWithUndo(
            doomed, movingItemsTo: LibraryCollection.Seed.prompts
        )
        #expect(temp.model.itemCount(in: LibraryCollection.Seed.prompts) == 1)

        temp.model.handle(.undo)
        try await Task.sleep(for: .milliseconds(50))
        #expect(temp.model.itemCount(in: LibraryCollection.Seed.personal) == 1)
        #expect(temp.model.itemCount(in: LibraryCollection.Seed.prompts) == 0)
    }

    /// CLAUDE.md §5.1: a failed undo must not cost the user both the data and
    /// their only way back to it.
    @MainActor
    @Test("the undo entry is pushed only after the delete actually succeeds")
    func undoIsNotSpentOnAFailure() async throws {
        let temp = try TempModel()
        await temp.model.refresh()
        let ghost = LibraryCollection(id: "does-not-exist", name: "ghost", position: 9)
        await temp.model.deleteCollectionWithUndo(ghost, movingItemsTo: nil)
        // Deleting a row that is not there is not an error in SQLite, so the
        // entry is pushed — but it must restore cleanly rather than corrupt.
        temp.model.handle(.undo)
        try await Task.sleep(for: .milliseconds(50))
        #expect(temp.model.collections.contains { $0.id == "does-not-exist" })
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
cd swift && swift test --filter CollectionUndoTests 2>&1 | tail -30
```

- [ ] **Step 3: Add the operation and the method**

In `UndoableOperation`:

```swift
        /// A collection and the membership of its items *as it was before* the
        /// deletion. One case covers both buttons: rows that were deleted are
        /// re-inserted from this snapshot, rows that were moved have their
        /// `collectionID` rewritten back to it.
        case deletedCollection(collection: LibraryCollection, items: [LibraryEntry])
```

In the `undo()` switch:

```swift
            case .deletedCollection(let collection, let members):
                // The collection first, then its members — no item is ever
                // momentarily homeless.
                try await store.restoreCollection(collection, items: members)
```

And the method:

```swift
    /// Delete a collection, capturing enough to undo it.
    ///
    /// The snapshot is taken *before* the store is touched, and the undo entry
    /// is pushed *after* it succeeds — a failed delete must not spend the user's
    /// `u` on a no-op (CLAUDE.md §5.1, and the shape of SW-14).
    func deleteCollectionWithUndo(
        _ collection: LibraryCollection,
        movingItemsTo destination: String?
    ) async {
        let members = items.filter { $0.collectionID == collection.id }
        do {
            try await store.deleteCollection(id: collection.id, movingItemsTo: destination)
            pushUndo(.deletedCollection(collection: collection, items: members))
            await refresh()
            // The tab list changed, so the selected row may be somewhere else
            // entirely — or on another tab.
            reorderToken &+= 1
        } catch {
            setStatus(strings.errorDeleteCollection("\(error)"))
            await refresh()
        }
    }
```

While here, apply roadmap 2.1.3's other half to `delete(id:)` and
`togglePin(id:)`: move their `pushUndo` calls to **after** the store call
succeeds, for the same reason.

- [ ] **Step 4: Verify**

```bash
cd swift && swift test 2>&1 | tail -20
```

- [ ] **Step 5: Prepared commit** *(run only if the user has asked to commit)*

```bash
git add -A swift/
git commit -m "feat: manage collections from Settings, with a non-destructive default"
```

---

### Task 18: Documentation and the wiring smoke walk

CLAUDE.md §9's lesson: Core has tests and the shell's errors only surface in a
wiring-level smoke walk. This task is that walk, plus keeping the repo from
simultaneously containing a document promising "one library" and a directory
implementing five.

**Files:**
- Modify: `CLAUDE.md`, `docs/roadmap.md`, `CHANGELOG.md`, `README.md`
- Modify: `docs/design-collections.md` (status line only)

- [ ] **Step 1: Update `CLAUDE.md`**

- §4.1: the top bar is a band whose stops come from `PanelTab.topBarItems`;
  `＋` is on every collection tab. `⇥` wraps, band arrows do not — and say why
  (visible boundary).
- §5: add the v3 rule — the seed runs inside the migration transaction, and the
  column carries no foreign key because `ALTER TABLE ADD COLUMN` forbids one
  with a non-NULL default, so `deleteCollection` is the integrity boundary.
- §5.1: add `deletedCollection` — restore inserts the collection before its
  items.
- §8: add the sentence that collection names are **user data, not `Strings`
  copy**, and that the seeded names are written once in the then-current
  language and do not follow a later switch.
- §9: add the two new wires — `AppModel.onEditItem` carries a collection id, and
  `SettingsView` now needs the model.
- §1: note the target split (`SwilClipUI` vs `SwilClip`).

- [ ] **Step 2: Update `docs/roadmap.md`**

Mark 2.1.1 and 2.1.3 done, and 2.2's `⇥`-in-the-editor item done. Move the
remaining 2.2 items (expanded-row scroll, `e`-opens-the-editor) forward, and
record that the expanded-row scroll still needs its own design pass.

- [ ] **Step 3: `CHANGELOG.md`**

One entry under a new version heading, in the voice the file already uses.

- [ ] **Step 4: Flip the spec's status**

In `docs/design-collections.md`, change `**Status:** Proposed` to
`**Status:** Implemented` and add the plan link.

- [ ] **Step 5: The wiring smoke walk** — on a `--release` bundle, by hand

```bash
cd swift && ./scripts/bundle.sh --release
```

- [ ] Summon the panel. Three tabs: Clipboard, Prompts, Personal — the existing prompts are all under Prompts and none were lost.
- [ ] `⇥` four times returns you to Clipboard. `⇧⇥` walks back.
- [ ] `↑` from the first row reaches the band; `↑` again does nothing; `←`/`→` walk the tabs, then reach `＋` and `⚙`; `⏎` on the tabs enters the list.
- [ ] `⇧S` on a clip → footer says "Saved to Prompts". The clip is still in history.
- [ ] Settings → Collections: add "Work", rename it, change its glyph, move it to the top.
- [ ] Back in the panel: Work is now the first collection. `⇧S` now says "Saved to Work".
- [ ] `n` on Work → editor. `⇥` cycles Title → Body → Collection with **no mouse**. Save.
- [ ] Edit that item, change its collection to Personal, save. It moved tabs.
- [ ] Settings → delete Personal → choose "Move N to …". Close Settings, press `u` in the panel. Personal is back with its items.
- [ ] Delete Personal again, choose "Delete the collection and N items", `u`, confirm both come back.
- [ ] Change the panel size to Small with five collections present. The bar degrades and never clips.
- [ ] Switch the language. Built-in tab names **stay as seeded** — that is the documented trade-off, not a bug.
- [ ] Change the summon hotkey; the new one fires and the old one does not (SW-01 guard).
- [ ] Menu bar → "Settings…" opens Settings, not the panel (SW-02 guard).
- [ ] Delete an image clip, `u`, expand it — the picture is there (SW-03 guard).

- [ ] **Step 6: Prepared commit** *(run only if the user has asked to commit)*

```bash
git add -A
git commit -m "docs: record the collections model and the shell target split"
```

---

## Self-review

**Spec coverage.** §1 equality model → Tasks 3, 5, 16. §2 data model → Tasks 3–6.
§3 `PanelTab` → Task 7. §4 reducer → Tasks 8, 10. §5 keyboard → Tasks 8, 9, 15.
§6 top bar → Task 12. §7 editor → Task 14. §8 Settings/delete → Tasks 16, 17.
§9 `⇧S` targeting and the zero-collection state → Task 15. §10 non-goals →
nothing to build, asserted by absence. §11 sequencing → the phase order.
§12 test obligations → each is a named test above. §13 open questions → the cap
is `LibraryCollection.maximumCount`, one constant.

**Known gap, deliberate:** spec §11's M4 (arrow-scroll inside an expanded row)
has no task. It is listed under *Out of scope* at the top with the reason.

**Type consistency.** `LibraryCollection` / `LibraryEntry` / `CollectionSymbol` /
`PanelTab.collection(_:)` / `TopBarItem.newItem` / `KeyCommand.newItem` /
`KeyCommand.switchTabBackward` / `SelectionEffect.newItem` /
`AppModel.onEditItem` / `store.createItem` / `store.promote(clipID:into:)` /
`store.deleteCollection(id:movingItemsTo:)` /
`store.restoreCollection(_:items:)` / `model.deleteCollectionWithUndo(_:movingItemsTo:)`
are each defined once and used with the same spelling everywhere above.
`PromptTitle` deliberately keeps its name.

---

## Execution

**Plan saved to `docs/plan-collections.md`.** Two execution options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, reviewed
   between tasks, fast iteration.
2. **Inline Execution** — tasks run in this session with batched checkpoints.

---

## What actually happened — deviations from this plan

Recorded after execution on 2026-08-21. The plan above is left as written; this
section is the diff between it and reality.

**1. `LibraryItem` → `LibraryEntry`.** The name collides with SwiftUI's own
`LibraryItem` (the type `LibraryContentProvider` returns), so every view file
importing both modules failed with *"'LibraryItem' is ambiguous for type
lookup"*. Renamed to `LibraryEntry`, and the store methods followed
(`allEntries`, `entries(in:)`, `createEntry`, `updateEntry`, `deleteEntry`,
`setEntryPinned`, `restoreEntries`, `restoreEntryPinState`,
`deleteCollection(id:movingEntriesTo:)`, `restoreCollection(_:entries:)`).
Caught by the compiler during the Core phase — an argument for landing Core
before the shell rather than alongside it.

**2. The decoder change moved from Task 6 into Task 5.** Task 5's assertion
"existing prompts land in the `prompts` collection" would have passed vacuously
while `collectionID` still came from its default, so reading the real column had
to land with the migration rather than after it.

**3. `AppModel` gained `import Foundation`, not just lost `import AppKit`.**
AppKit had been supplying `Data` and `Date` transitively. The file genuinely
needed Foundation and never needed the window server.

**4. Two protected regression suites needed compiler-forced edits.**
`PanelFocusTests` and `SelectionReducerTests` both spelled `.prompts`, which no
longer exists. Each got a *named* two-tab fixture
(`private let promptsTab = PanelTab.collection(LibraryCollection.Seed.prompts)`)
and its local `reduce` helper now passes `tabs:`. No assertion was rewritten and
no case was removed.

**5. One planned test was wrong, not the code.** "each tab keeps its own cursor"
originally typed the query `"t"`, which filtered out the selected row — so
`reconcileSelection` correctly moved the cursor and the assertion failed. The
query became `"o"`, which matches both rows.

**6. Extra wiring found while implementing.** `ShortcutSheet` was still calling
`ShortcutReference.sections(summon:tabSwitch:)`, leaving `tabSwitchBackward` at
its `nil` default — `⇧⇥` worked but the reference did not document it. Wired to
`settings.tabSwitchKey.reversed?.displayString`. This is CLAUDE.md §9's failure
mode exactly, found by reading rather than by a test.

**7. `bundle.sh` needed no change.** `TARGET_NAME` is the executable product
name, which is still `SwilClip`.

**Not done:** Task 18 Step 5, the manual wiring smoke walk. It needs a person at
the keyboard. The checklist stands as written.
