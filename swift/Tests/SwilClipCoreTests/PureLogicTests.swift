import CoreGraphics
import Foundation
import Testing

@testable import SwilClipCore

// MARK: - ContentKind

@Suite("ContentKind")
struct ContentKindTests {
    @Test("recognises URLs and emails")
    func recognisesLinks() {
        #expect(ContentKind.detect("https://github.com/supwils") == .url)
        #expect(ContentKind.detect("http://localhost:5173") == .url)
        #expect(ContentKind.detect("huahaoshang2000@gmail.com") == .email)
        // A sentence that merely mentions a URL is prose, not a link.
        #expect(ContentKind.detect("see https://example.com for details") != .url)
    }

    @Test("recognises colours")
    func recognisesColours() {
        #expect(ContentKind.detect("#fff") == .color)
        #expect(ContentKind.detect("#1a2b3c") == .color)
        #expect(ContentKind.detect("rgba(0,0,0,0.5)") == .color)
        #expect(ContentKind.detect("#nothex") != .color)
    }

    @Test("recognises JSON, and only actual JSON")
    func recognisesJSON() {
        #expect(ContentKind.detect(#"{"name": "swil"}"#) == .json)
        #expect(ContentKind.detect("[1, 2, 3]") == .json)
        // Brackets alone are not enough — the parse has to succeed.
        #expect(ContentKind.detect("{not json at all}") != .json)
    }

    @Test("recognises code by indentation or punctuation density")
    func recognisesCode() {
        #expect(ContentKind.detect("func main() {\n    print(1)\n}") == .code)
        #expect(ContentKind.detect("if (a) { b(); } else { c(); }\nmore();") == .code)
        // Prose across lines is multiline, not code.
        #expect(ContentKind.detect("第一行\n第二行\n第三行") == .multiline)
    }

    @Test("falls back to plain text")
    func fallsBackToText() {
        #expect(ContentKind.detect("just some words") == .text)
        #expect(ContentKind.detect("") == .text)
        #expect(ContentKind.detect("   ") == .text)
    }
}

// MARK: - PreviewText

@Suite("PreviewText")
struct PreviewTextTests {
    @Test("collapses newlines and runs of whitespace into single spaces")
    func collapsesWhitespace() {
        // A one-line row cannot render newlines, and leaving them in produced
        // rows that looked blank in v1.
        #expect(PreviewText.derive(from: "line one\n\nline two") == "line one line two")
        #expect(PreviewText.derive(from: "  padded   out  ") == "padded out")
        #expect(PreviewText.derive(from: "tabs\there") == "tabs here")
    }

    @Test("truncates to the limit")
    func truncates() {
        let long = String(repeating: "x", count: 500)
        #expect(PreviewText.derive(from: long).count == PreviewText.limit)
        #expect(PreviewText.derive(from: long, limit: 10).count == 10)
    }

    @Test("handles an empty or whitespace-only value")
    func handlesEmpty() {
        #expect(PreviewText.derive(from: "").isEmpty)
        #expect(PreviewText.derive(from: "\n\n  \t ").isEmpty)
    }
}

// MARK: - PromptTitle

@Suite("PromptTitle")
struct PromptTitleTests {
    @Test("takes the first line")
    func takesFirstLine() {
        #expect(PromptTitle.propose(from: "简历优化\n\n详细说明…") == "简历优化")
    }

    @Test("strips markdown leaders so a bullet does not become the name")
    func stripsLeaders() {
        #expect(PromptTitle.propose(from: "# Heading\nbody") == "Heading")
        #expect(PromptTitle.propose(from: "- bullet\nbody") == "bullet")
        #expect(PromptTitle.propose(from: "1. numbered\nbody") == "numbered")
        #expect(PromptTitle.propose(from: "> quoted\nbody") == "quoted")
    }

    @Test("truncates long first lines with an ellipsis")
    func truncatesLongTitles() {
        let title = PromptTitle.propose(from: String(repeating: "长", count: 60))
        #expect(title.count == PromptTitle.limit + 1) // + the ellipsis
        #expect(title.hasSuffix("…"))
    }

    @Test("falls back when the first line is blank")
    func fallsBack() {
        #expect(PromptTitle.propose(from: "\n\nactual content here").isEmpty == false)
        #expect(PromptTitle.propose(from: "") == "Untitled")
        #expect(PromptTitle.propose(from: "   \n  ") == "Untitled")
    }

    @Test("handles a real prompt from the author's corpus")
    func handlesRealCorpus() {
        let body = "请根据岗位要求，对简历的技能速查部分进行优化，基于岗位描述对技能种类进行排序"
        #expect(PromptTitle.propose(from: body).hasPrefix("请根据岗位要求"))
        #expect(PromptTitle.propose(from: body).count <= PromptTitle.limit + 1)
    }
}

// MARK: - Matcher

@Suite("Matcher")
struct MatcherTests {
    private let items = [
        ClipItem(kind: .text, preview: "git rebase -i HEAD~3", text: "git rebase -i HEAD~3"),
        ClipItem(kind: .text, preview: "请优化语言描述", text: "请优化语言描述，降低AI感"),
        ClipItem(kind: .text, preview: "Café Society", text: "Café Society"),
    ]

    @Test("an empty query matches everything")
    func emptyQueryMatchesAll() {
        // This is what makes "search mode, nothing typed" show the full list
        // rather than an empty one.
        #expect(Matcher.filter(items, query: "").count == 3)
        #expect(Matcher.filter(items, query: "   ").count == 3)
    }

    @Test("matches case-insensitively")
    func caseInsensitive() {
        #expect(Matcher.filter(items, query: "GIT").count == 1)
        #expect(Matcher.filter(items, query: "Rebase").count == 1)
    }

    @Test("matches diacritic-insensitively")
    func diacriticInsensitive() {
        #expect(Matcher.filter(items, query: "cafe").count == 1)
    }

    @Test("matches CJK substrings")
    func matchesCJK() {
        #expect(Matcher.filter(items, query: "优化").count == 1)
        // Matches the full text, not only the truncated preview.
        #expect(Matcher.filter(items, query: "降低AI感").count == 1)
    }

    @Test("returns nothing when nothing matches")
    func noMatches() {
        #expect(Matcher.filter(items, query: "zzzz").isEmpty)
    }

    @Test("reports highlight ranges in order and without overlap")
    func highlightRanges() {
        let ranges = Matcher.highlightRanges(of: "a", in: "banana")
        #expect(ranges.count == 3)
        let text = "banana"
        #expect(ranges.map { text.distance(from: text.startIndex, to: $0.lowerBound) } == [1, 3, 5])
    }

    @Test("an empty query highlights nothing")
    func emptyQueryHighlightsNothing() {
        #expect(Matcher.highlightRanges(of: "", in: "banana").isEmpty)
    }
}

// MARK: - PanelPlacement

@Suite("PanelPlacement")
struct PanelPlacementTests {
    private let panel = CGSize(width: 340, height: 480)
    /// A 1440×900 display with the menu bar excluded.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test("opens below-right of the cursor when there is room")
    func opensBelowRight() {
        let origin = PanelPlacement.origin(
            forCursor: CGPoint(x: 400, y: 700), panelSize: panel, visibleFrame: screen
        )
        #expect(origin.x == 408)
        #expect(origin.y == 212) // 700 - 8 - 480
    }

    @Test("flips left rather than overhanging the right edge")
    func flipsHorizontally() {
        let origin = PanelPlacement.origin(
            forCursor: CGPoint(x: 1400, y: 700), panelSize: panel, visibleFrame: screen
        )
        #expect(origin.x + panel.width <= screen.maxX)
    }

    @Test("flips up rather than falling off the bottom")
    func flipsVertically() {
        let origin = PanelPlacement.origin(
            forCursor: CGPoint(x: 400, y: 100), panelSize: panel, visibleFrame: screen
        )
        #expect(origin.y >= screen.minY)
    }

    @Test("always lands fully on screen, from any cursor position")
    func alwaysOnScreen() {
        // The property that matters: a panel you cannot see is a panel you
        // cannot move back (SC-03).
        for x in stride(from: -100.0, through: 1600.0, by: 137) {
            for y in stride(from: -100.0, through: 1000.0, by: 131) {
                let origin = PanelPlacement.origin(
                    forCursor: CGPoint(x: x, y: y), panelSize: panel, visibleFrame: screen
                )
                let frame = CGRect(origin: origin, size: panel)
                #expect(screen.contains(frame), "off-screen for cursor (\(x), \(y))")
            }
        }
    }

    @Test("clamps a panel larger than the screen instead of inverting")
    func handlesOversizedPanel() {
        let huge = CGSize(width: 2000, height: 2000)
        let origin = PanelPlacement.clamp(
            origin: CGPoint(x: 500, y: 500), panelSize: huge, visibleFrame: screen
        )
        #expect(origin.x == screen.minX + PanelPlacement.screenMargin)
        #expect(origin.y == screen.minY + PanelPlacement.screenMargin)
    }

    @Test("restores a position that is still substantially visible")
    func restoresVisiblePosition() {
        #expect(
            PanelPlacement.isRestorable(
                origin: CGPoint(x: 100, y: 100), panelSize: panel, screens: [screen]
            )
        )
    }

    @Test("rejects a position on a display that is gone")
    func rejectsUnpluggedDisplay() {
        // Saved on a second monitor at x = 2000; that display is no longer
        // attached. Clamping it onto the remaining screen would put the panel
        // somewhere the user never placed it, so the cursor path is used instead.
        #expect(
            PanelPlacement.isRestorable(
                origin: CGPoint(x: 2000, y: 300), panelSize: panel, screens: [screen]
            ) == false
        )
    }

    @Test("rejects a position that is only marginally on screen")
    func rejectsBarelyVisible() {
        #expect(
            PanelPlacement.isRestorable(
                origin: CGPoint(x: 1420, y: 100), panelSize: panel, screens: [screen]
            ) == false
        )
    }

    @Test("accepts a position nudged slightly past an edge")
    func acceptsSlightOverhang() {
        // A panel the user dragged a few points off the edge should still come
        // back where they left it.
        #expect(
            PanelPlacement.isRestorable(
                origin: CGPoint(x: -20, y: 100), panelSize: panel, screens: [screen]
            )
        )
    }
}
