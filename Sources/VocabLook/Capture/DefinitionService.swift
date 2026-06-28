import Foundation
import CoreServices

struct DictionaryResult {
    var definition: String?
    var partOfSpeech: String?
    var ipa: String?
}

/// Wraps macOS Dictionary Services. Best-effort parsing of the plain-text entry.
enum DefinitionService {
    static func define(_ term: String) -> DictionaryResult {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DictionaryResult() }

        let range = CFRangeMake(0, trimmed.utf16.count)
        guard let unmanaged = DCSCopyTextDefinition(nil, trimmed as CFString, range) else {
            return DictionaryResult()
        }
        let full = unmanaged.takeRetainedValue() as String
        // Store the RAW dictionary text; formatting is applied at display time (formatForDisplay)
        // so improvements to the formatter also benefit previously-captured words.
        return DictionaryResult(definition: full,
                                partOfSpeech: parsePartOfSpeech(full),
                                ipa: parseIPA(full))
    }

    /// The formatted English definition for display. Re-fetches the full entry from the dictionary
    /// (so words captured before raw-storage, or truncated ones, still show in full), falling back
    /// to the stored text only if the dictionary no longer resolves the term.
    static func displayText(for term: String, fallback: String?) -> String? {
        let raw = define(term).definition ?? fallback
        guard let raw, !raw.isEmpty else { return nil }
        return formatForDisplay(raw, term: term)
    }

    private static let posWords = ["noun", "verb", "adjective", "adverb", "pronoun",
                                   "preposition", "conjunction", "interjection", "determiner",
                                   "exclamation", "abbreviation", "prefix", "suffix"]

    /// Dictionary Services returns one flat plain-text blob like:
    ///   "headword syl·la·bles | ipa | (also variant) noun first sense. • second sense. ORIGIN ..."
    /// We strip the redundant "headword | ipa |" preamble + leading variant/part-of-speech
    /// (those are shown separately on the card), cut the etymology, and turn "•" sense markers
    /// into their own lines so the card can render a clean list. Applied at DISPLAY time.
    static func formatForDisplay(_ text: String, term: String) -> String? {
        var body = text

        // 1. Drop the "headword | ipa |" preamble: keep everything after the 2nd pipe.
        let parts = text.components(separatedBy: "|")
        if parts.count >= 3 {
            body = parts[2...].joined(separator: "|")
        } else if body.lowercased().hasPrefix(term.lowercased()) {
            body = String(body.dropFirst(term.count))
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Drop a leading variant note like "(also incrustation)".
        if body.hasPrefix("("), let close = body.firstIndex(of: ")") {
            body = String(body[body.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 3. Drop a leading part-of-speech word (shown separately on the card).
        for pos in posWords where body.lowercased().hasPrefix(pos + " ") {
            body = String(body.dropFirst(pos.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // 4. Cut etymology / extra sections to keep the card focused.
        for marker in ["ORIGIN", "DERIVATIVES", "PHRASES", "PHRASAL VERBS", "USAGE"] {
            if let r = body.range(of: marker) {
                body = String(body[..<r.lowerBound])
            }
        }

        // 5. Normalize whitespace, then split bullet ("•") and numbered ("1 …", "2 …") senses
        //    onto their own lines. Leading space lets the regex also catch the first numbered sense.
        body = body.replacingOccurrences(of: "\n", with: " ")
        while body.contains("  ") { body = body.replacingOccurrences(of: "  ", with: " ") }
        body = body.replacingOccurrences(of: "•", with: "\n• ")
        // Split numbered senses ("1 …", "2 …") even when the number is glued to the previous word.
        body = body.replacingOccurrences(of: #"(?<!\d)(\d{1,2})\s"#, with: "\n$1. ", options: .regularExpression)

        // Drop empty fragments and lone bullets; no length cap (the card scrolls).
        let lines = body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "•" }
        let result = lines.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    /// IPA is typically delimited by pipes, e.g. "ephemeral | əˈfem(ə)rəl |".
    private static func parseIPA(_ text: String) -> String? {
        let parts = text.components(separatedBy: "|")
        guard parts.count >= 2 else { return nil }
        let candidate = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    private static func parsePartOfSpeech(_ text: String) -> String? {
        for pos in ["noun", "verb", "adjective", "adverb", "pronoun",
                    "preposition", "conjunction", "interjection", "determiner"] {
            if text.range(of: "\\b\(pos)\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                return pos
            }
        }
        return nil
    }
}
