import Foundation

/// Substring search over clip and prompt rows.
///
/// Deliberately *not* fuzzy. In a clipboard manager you almost always remember a
/// literal fragment of what you copied, and fuzzy matching turns a three-letter
/// query into a list where everything matches a little — which is worse than a
/// short list where everything matches exactly.
///
/// Case- and diacritic-insensitive so `cafe` finds `Café` and `GIT` finds `git`.
/// Latin and CJK are handled by the same path: `range(of:options:)` folds via
/// ICU, so no separate branch is needed for Chinese input.
public enum Matcher {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Whether `query` occurs in any of `fields`. An empty query matches
    /// everything, which is what makes "search mode with no input" show the
    /// full list rather than nothing.
    public static func matches(query: String, in fields: [String?]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        for field in fields {
            guard let field, !field.isEmpty else { continue }
            if field.range(of: needle, options: options) != nil { return true }
        }
        return false
    }

    public static func filter(_ clips: [ClipItem], query: String) -> [ClipItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return clips }
        return clips.filter { matches(query: query, in: [$0.text, $0.preview, $0.sourceApp]) }
    }

    public static func filter(_ prompts: [PromptItem], query: String) -> [PromptItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return prompts }
        return prompts.filter { matches(query: query, in: [$0.title, $0.body]) }
    }

    /// Ranges of `query` within `haystack`, for highlighting matched runs in a
    /// row. Non-overlapping, in order.
    public static func highlightRanges(of query: String, in haystack: String) -> [Range<String.Index>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let found = haystack.range(
                  of: needle,
                  options: options,
                  range: searchStart..<haystack.endIndex
              ) {
            ranges.append(found)
            // `found.upperBound` always advances: a non-empty needle cannot
            // produce an empty range, so this terminates.
            searchStart = found.upperBound
        }
        return ranges
    }
}
