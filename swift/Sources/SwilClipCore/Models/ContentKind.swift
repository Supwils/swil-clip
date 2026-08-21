import Foundation

/// What a text clip appears to be, used to pick the row's type chip.
///
/// This is a rendering hint, not a parser. It runs on every visible row, so it
/// is ordered cheapest-test-first and never scans more than the prefix it needs.
/// Being wrong costs a slightly odd icon; being slow costs a dropped frame.
public enum ContentKind: String, Sendable, CaseIterable {
    case url
    case email
    case color
    case json
    case code
    case multiline
    case text
    case image

    public static func detect(_ raw: String) -> ContentKind {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        // Single-token tests first — they short-circuit on the common cases.
        if !trimmed.contains(where: \.isWhitespace) {
            if isURL(trimmed) { return .url }
            if isEmail(trimmed) { return .email }
            if isColor(trimmed) { return .color }
        }
        if isJSON(trimmed) { return .json }
        if isCode(trimmed) { return .code }
        if trimmed.contains("\n") { return .multiline }
        return .text
    }

    // MARK: - Predicates

    static func isURL(_ text: String) -> Bool {
        text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    static func isEmail(_ text: String) -> Bool {
        guard let at = text.firstIndex(of: "@"), text.firstIndex(of: "@") == text.lastIndex(of: "@")
        else { return false }
        let local = text[text.startIndex..<at]
        let domain = text[text.index(after: at)...]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        let tld = domain[domain.index(after: dot)...]
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }

    static func isColor(_ text: String) -> Bool {
        if text.hasPrefix("#") {
            let digits = text.dropFirst()
            return (3...8).contains(digits.count) && digits.allSatisfy(\.isHexDigit)
        }
        let lowered = text.lowercased()
        return (lowered.hasPrefix("rgb(") || lowered.hasPrefix("rgba("))
            && lowered.hasSuffix(")")
    }

    static func isJSON(_ text: String) -> Bool {
        guard text.count >= 2, let first = text.first, let last = text.last else { return false }
        guard (first == "{" && last == "}") || (first == "[" && last == "]") else { return false }
        // Only now pay for a parse — the bracket check rejects nearly everything.
        guard let data = text.data(using: .utf8) else { return false }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return false }
        return parsed is [String: Any] || parsed is [Any]
    }

    static func isCode(_ text: String) -> Bool {
        guard text.contains("\n") else { return false }
        // An indented continuation line is the strongest single signal.
        for line in text.split(separator: "\n").dropFirst()
        where line.hasPrefix("  ") || line.hasPrefix("\t") {
            return true
        }
        // Otherwise fall back to punctuation density.
        let punctuation: Set<Character> = ["{", "}", ";", "(", ")", "<", ">", "[", "]"]
        var hits = 0
        for character in text where punctuation.contains(character) {
            hits += 1
            if hits >= 4 { return true }
        }
        return false
    }
}
