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
        return DictionaryResult(definition: cleanDefinition(full, term: trimmed),
                                partOfSpeech: parsePartOfSpeech(full),
                                ipa: parseIPA(full))
    }

    /// The dictionary text starts with the headword; trim it and collapse whitespace.
    private static func cleanDefinition(_ text: String, term: String) -> String? {
        var s = text
        if s.lowercased().hasPrefix(term.lowercased()) {
            s = String(s.dropFirst(term.count))
        }
        s = s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : String(s.prefix(400))
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
