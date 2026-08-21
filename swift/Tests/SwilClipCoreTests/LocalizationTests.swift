import Foundation
import Testing

@testable import SwilClipCore

@Suite("AppLanguage")
struct AppLanguageTests {
    @Test("explicit choices ignore the system preference")
    func explicitWins() {
        #expect(AppLanguage.english.resolved(preferring: ["zh-Hans-CN"]) == .english)
        #expect(AppLanguage.chinese.resolved(preferring: ["en-US"]) == .chinese)
    }

    @Test("system follows the language subtag, not the exact tag")
    func systemFollowsSubtag() {
        for tag in ["zh", "zh-Hans", "zh-Hant-TW", "zh-Hans-CN", "ZH-hans"] {
            #expect(AppLanguage.system.resolved(preferring: [tag]) == .chinese, "\(tag)")
        }
        for tag in ["en", "en-GB", "fr-FR", "ja-JP"] {
            #expect(AppLanguage.system.resolved(preferring: [tag]) == .english, "\(tag)")
        }
    }

    @Test("no preferred language at all falls back to English")
    func emptyFallsBack() {
        #expect(AppLanguage.system.resolved(preferring: []) == .english)
    }
}

@Suite("Strings")
struct StringsTests {
    private let en = Strings(.english)
    private let zh = Strings(.chinese)

    @Test("both languages differ where they should, and agree on keycaps")
    func bothPopulated() {
        #expect(en.clipboardTab != zh.clipboardTab)
        #expect(en.promptsTab != zh.promptsTab)
        // Never translated: it is what is printed on the key.
        #expect(en.languageOption(.english) == zh.languageOption(.english))
        #expect(en.languageOption(.chinese) == zh.languageOption(.chinese))
    }

    /// The reason this catalog is a struct of properties rather than a lookup
    /// table: there is no key that can go missing. This test is the belt to
    /// that braces — it catches an empty string, which the compiler cannot.
    @Test("every shortcut group and action has copy in both languages")
    func shortcutCopyIsComplete() {
        for language in ResolvedLanguage.allCases {
            let strings = Strings(language)
            for group in ShortcutGroup.allCases {
                #expect(!strings.title(for: group).isEmpty, "\(language) \(group)")
            }
            for action in ShortcutAction.allCases {
                #expect(!strings.label(for: action).isEmpty, "\(language) \(action)")
            }
        }
    }

    @Test("ages read naturally at every boundary")
    func ages() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func age(_ secondsAgo: TimeInterval, _ strings: Strings) -> String {
            strings.ageLabel(for: now.addingTimeInterval(-secondsAgo), now: now)
        }
        #expect(age(10, en) == "now")
        #expect(age(10, zh) == "刚刚")
        #expect(age(300, en) == "5m")
        #expect(age(300, zh) == "5分")
        #expect(age(7_200, en) == "2h")
        #expect(age(7_200, zh) == "2时")
        #expect(age(172_800, en) == "2d")
        #expect(age(172_800, zh) == "2天")
    }

    @Test("dates older than a week render as a date in both calendars")
    func oldDates() {
        // 2020-08-12, in whatever zone the machine is in — the label only ever
        // shows month and day, so the exact instant does not matter.
        var components = DateComponents()
        components.year = 2020
        components.month = 8
        components.day = 12
        components.hour = 12
        let date = Calendar.current.date(from: components)!

        #expect(en.dateLabel(for: date) == "12 Aug")
        #expect(zh.dateLabel(for: date) == "8月12日")
    }

    @Test("'edited just now' never becomes 'edited now ago'")
    func editedReadsAsASentence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(en.editedLabel(for: now.addingTimeInterval(-5), now: now) == "edited just now")
        #expect(zh.editedLabel(for: now.addingTimeInterval(-5), now: now) == "刚刚编辑")
        #expect(en.editedLabel(for: now.addingTimeInterval(-300), now: now) == "edited 5m ago")
        #expect(zh.editedLabel(for: now.addingTimeInterval(-300), now: now) == "5分前编辑")
    }
}

@Suite("ShortcutReference")
struct ShortcutReferenceTests {
    @Test("every action the enum declares is actually listed")
    func nothingIsDeclaredButUnlisted() {
        let listed = ShortcutReference.documentedActions
        for action in ShortcutAction.allCases {
            #expect(listed.contains(action), "\(action) is declared but never shown to the user")
        }
    }

    @Test("no action is listed twice, and none is filed under the wrong heading")
    func sectionsAreWellFormed() {
        let sections = ShortcutReference.sections(summon: "⌘⇧V", tabSwitch: "⇥")
        var seen: Set<ShortcutAction> = []
        for section in sections {
            #expect(!section.entries.isEmpty, "\(section.group) is empty")
            for entry in section.entries {
                #expect(entry.action.group == section.group, "\(entry.action) is in the wrong section")
                #expect(seen.insert(entry.action).inserted, "\(entry.action) listed twice")
            }
        }
        #expect(Set(sections.map(\.group)).count == ShortcutGroup.allCases.count)
    }

    /// The point of ``KeyCommand/documentedAction``: a key the reducer accepts
    /// but the reference never mentions is a key nobody will find.
    @Test("every command the keyboard can produce is documented")
    func everyCommandIsDocumented() {
        let commands: [KeyCommand] = [
            .moveUp, .moveDown, .moveToFirst, .moveToLast,
            .beginSearch, .appendToQuery("a"), .deleteQueryCharacter, .clearQuery,
            .switchTab, .confirm, .deleteItem, .togglePin, .toggleExpand,
            .undo, .newPrompt, .promoteToPrompt, .dismiss, .selectID("x"),
        ]
        let listed = ShortcutReference.documentedActions
        for command in commands {
            #expect(listed.contains(command.documentedAction), "\(command)")
        }
    }

    @Test("the rebindable keys are the ones actually printed")
    func rebindableKeysAreSubstituted() {
        let sections = ShortcutReference.sections(summon: "⌃⌥C", tabSwitch: "⌘⇥")
        let entries = sections.flatMap(\.entries)
        #expect(entries.first { $0.action == .summon }?.keys == ["⌃⌥C"])
        #expect(entries.first { $0.action == .switchTab }?.keys == ["⌘⇥"])
    }
}

extension ShortcutReferenceTests {
    /// Every row in the reference has to draw *something* in its left column.
    /// An entry with neither keys nor a glyph renders as a blank gap that reads
    /// like a layout bug rather than like "this one is not a keystroke".
    @Test("no entry has an empty left column")
    func everyEntryHasAMark() {
        for section in ShortcutReference.sections(summon: "⌘⇧V", tabSwitch: "⇥") {
            for entry in section.entries {
                #expect(!entry.keys.isEmpty || entry.symbol != nil, "\(entry.action)")
                #expect(entry.keys.allSatisfy { !$0.isEmpty }, "\(entry.action)")
            }
        }
    }
}

@Suite("AccentPalette")
struct AccentPaletteTests {
    @Test("hues wrap instead of clamping, and nonsense falls back")
    func normalization() {
        #expect(AccentPalette.normalized(0) == 0)
        #expect(AccentPalette.normalized(359.5) == 359.5)
        #expect(AccentPalette.normalized(360) == 0)
        #expect(AccentPalette.normalized(420) == 60)
        #expect(AccentPalette.normalized(-30) == 330)
        #expect(AccentPalette.normalized(.nan) == AccentPalette.defaultHue)
        #expect(AccentPalette.normalized(.infinity) == AccentPalette.defaultHue)
    }

    @Test("the default hue is still the ratified Brushed Quartz azure")
    func defaultIsUnchanged() {
        // docs/ui-design.md §2.4 — hsl(214, 84%, 62%). If this ever drifts, a
        // user who never opened the colour picker has had their app restyled.
        #expect(AccentPalette.defaultHue == 214)
        #expect(AccentPalette.saturation == 84)
        #expect(AccentPalette.darkLightness == 62)

        // #4D93F0 — the same bytes tauri/src/global.css shipped, which is how
        // we know the port is a port and not a re-derivation by eye.
        let (r, g, b) = AccentPalette.rgb(hue: 214, saturation: 84, lightness: 62)
        #expect(abs(r - 0.3008) < 0.0005)
        #expect(abs(g - 0.5774) < 0.0005)
        #expect(abs(b - 0.9392) < 0.0005)
    }

    @Test("relative luminance is anchored at black and white")
    func luminanceAnchors() {
        #expect(abs(AccentPalette.relativeLuminance(hue: 0, saturation: 0, lightness: 0)) < 1e-9)
        #expect(abs(AccentPalette.relativeLuminance(hue: 0, saturation: 0, lightness: 100) - 1) < 1e-9)
    }

    /// The reason the label colour is derived rather than hard-coded to white:
    /// at one fixed saturation and lightness, hue alone swings the accent from
    /// navy to highlighter.
    @Test("bright hues get a dark label, dark hues get a light one")
    func labelContrast() {
        let l = AccentPalette.darkLightness
        // Lime and amber are near-fluorescent at 84/62 — white text vanishes.
        #expect(AccentPalette.prefersDarkLabel(hue: 92, lightness: l))
        #expect(AccentPalette.prefersDarkLabel(hue: 60, lightness: l))
        // Blues and violets stay dark enough to carry white.
        #expect(!AccentPalette.prefersDarkLabel(hue: 214, lightness: l))
        #expect(!AccentPalette.prefersDarkLabel(hue: 248, lightness: l))
        #expect(!AccentPalette.prefersDarkLabel(hue: 350, lightness: l))
    }

    @Test("every preset is a distinct, valid hue")
    func presetsAreWellFormed() {
        let hues = AccentPalette.presets.map(\.hue)
        #expect(hues.allSatisfy { (0..<360).contains($0) })
        #expect(Set(hues).count == hues.count)
        #expect(Set(AccentPalette.presets.map(\.id)).count == hues.count)
        // The default must be reachable by clicking, not only by dragging.
        #expect(hues.contains(AccentPalette.defaultHue))
    }
}

@Suite("PanelTint")
struct PanelTintTests {
    /// The control only means something if the steps actually differ, and only
    /// reads correctly if they run in the order the labels imply.
    @Test("opacity increases from sheer to solid and stays in range")
    func monotonic() {
        let steps = PanelTint.allCases.map(\.scrimOpacity)
        #expect(steps == steps.sorted())
        #expect(Set(steps).count == steps.count)
        #expect(steps.allSatisfy { (0...1).contains($0) })
        #expect(PanelTint.sheer.scrimOpacity < PanelTint.standard.scrimOpacity)
        #expect(PanelTint.standard.scrimOpacity < PanelTint.solid.scrimOpacity)
    }

    /// The default has to be the one that keeps text readable over anything —
    /// that is the whole reason the setting exists.
    @Test("the default is opaque enough to be a contrast floor")
    func defaultCoversBrightBackdrops() {
        #expect(PanelTint.standard.scrimOpacity >= 0.7)
    }
}

extension StringsTests {
    @Test("appearance and tint options have copy in both languages")
    func appearanceCopyIsComplete() {
        for language in ResolvedLanguage.allCases {
            let strings = Strings(language)
            for appearance in Appearance.allCases {
                #expect(!strings.appearanceOption(appearance).isEmpty, "\(language) \(appearance)")
            }
            for tint in PanelTint.allCases {
                #expect(!strings.panelTintOption(tint).isEmpty, "\(language) \(tint)")
            }
        }
        #expect(!en.accentSection.isEmpty && !zh.accentSection.isEmpty)
        #expect(en.appearanceHint != zh.appearanceHint)
    }
}
