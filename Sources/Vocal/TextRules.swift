import Foundation

/// Plain find-and-replace on a transcript. Nothing here guesses: every change
/// comes from the replacements file or the filler list.
struct TextRules {
    struct Replacement: Equatable {
        let heard: String
        let written: String
    }

    var replacements: [Replacement] = []
    var removeFillers = false

    static let fillers = ["uh", "uhh", "um", "umm", "uhm", "erm", "hmm"]

    private static let letterBefore = "(?<![\\p{L}\\p{N}])"
    private static let letterAfter = "(?![\\p{L}\\p{N}])"

    /// Reads lines like `Coruna => Coruña`. Blank lines and lines starting with # are skipped.
    static func parseReplacements(_ text: String) -> [Replacement] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.components(separatedBy: "=>")
            guard parts.count == 2 else { return nil }
            let heard = parts[0].trimmingCharacters(in: .whitespaces)
            let written = parts[1].trimmingCharacters(in: .whitespaces)
            guard !heard.isEmpty else { return nil }
            return Replacement(heard: heard, written: written)
        }
    }

    func apply(to text: String) -> String {
        var result = text
        if removeFillers {
            result = Self.removingFillers(from: result)
        }
        return applyingReplacements(to: result)
    }

    /// One pass over the text, so a replacement's output is never replaced again.
    /// Longest first, so "Ribera Sacra" wins over a rule for "Sacra".
    private func applyingReplacements(to text: String) -> String {
        let ordered = replacements.sorted { $0.heard.count > $1.heard.count }
        guard !ordered.isEmpty else { return text }
        let alternatives = ordered.map { NSRegularExpression.escapedPattern(for: $0.heard) }.joined(separator: "|")
        let pattern = Self.letterBefore + "(?:" + alternatives + ")" + Self.letterAfter
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let found = result[range]
            guard let replacement = ordered.first(where: {
                $0.heard.compare(found, options: .caseInsensitive) == .orderedSame
            }) else { continue }
            result.replaceSubrange(range, with: replacement.written)
        }
        return result
    }

    /// Drops "uh", "um" and the like with the comma or space after them, and
    /// capitalizes the next word when the filler started a sentence.
    static func removingFillers(from text: String) -> String {
        let pattern = letterBefore + "(?:" + fillers.joined(separator: "|") + ")" + letterAfter + ",?\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let before = result[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let startsSentence = before.isEmpty || ".!?".contains(before.last!)
            result.removeSubrange(range)
            if startsSentence, range.lowerBound < result.endIndex {
                let next = result[range.lowerBound]
                result.replaceSubrange(range.lowerBound...range.lowerBound, with: next.uppercased())
            }
        }
        // A filler before punctuation leaves "word ," or "word ."; close the gap.
        result = result.replacingOccurrences(of: "\\s+([,.!?])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: ",([.!?])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }
}
