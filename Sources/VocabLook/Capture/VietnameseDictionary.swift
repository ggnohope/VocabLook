import Foundation
import CoreServices

/// Looks a word up in the user's installed Vietnamese–English dictionary via Dictionary Services.
///
/// `DCSCopyTextDefinition(nil, …)` only returns the first active dictionary (English). To reach the
/// Vietnamese one we must enumerate active dictionaries — but `DCSGetActiveDictionaries` /
/// `DCSDictionaryGetName` aren't exported to Swift, so we resolve them via dlsym. The symbols are
/// present in CoreServices (DictionaryServices); only their headers are private.
enum VietnameseDictionary {
    private typealias GetActiveFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetNameFn = @convention(c) (AnyObject) -> Unmanaged<CFString>?
    private typealias CopyDefFn = @convention(c) (AnyObject?, CFString, CFRange) -> Unmanaged<CFString>?

    private static let handle = dlopen(
        "/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW)

    private static let getActive: GetActiveFn? = sym("DCSGetActiveDictionaries")
    private static let getName: GetNameFn? = sym("DCSDictionaryGetName")
    private static let copyDef: CopyDefFn? = sym("DCSCopyTextDefinition")

    private static func sym<T>(_ name: String) -> T? {
        guard let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    /// Returns a cleaned Vietnamese definition, or nil if no Vietnamese dictionary / entry exists.
    static func lookup(_ term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let getActive, let getName, let copyDef,
              let dicts = getActive()?.takeUnretainedValue() as? [AnyObject] else { return nil }

        let range = CFRangeMake(0, trimmed.utf16.count)
        // Vietnamese dictionaries are named in Vietnamese ("Từ điển Lạc Việt", "Từ Điển Tiếng Việt").
        // A monolingual VN dictionary returns nothing for an English headword, so try each candidate
        // and use the first that actually yields an entry (the Anh–Việt "Lạc Việt" one).
        for dict in dicts {
            let name = getName(dict)?.takeUnretainedValue() as String? ?? ""
            let lower = name.lowercased()
            guard lower.contains("việt") || lower.contains("viet") else { continue }
            if let raw = copyDef(dict, trimmed as CFString, range)?.takeRetainedValue() as String?,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return clean(raw, term: trimmed)
            }
        }
        return nil
    }

    /// Strip the "headword | ipa |" preamble (when present) or a leading headword, drop the
    /// synonym/extra trailer, and keep the senses.
    private static func clean(_ text: String, term: String) -> String? {
        var body = text
        let parts = text.components(separatedBy: "|")
        if parts.count >= 3 {
            body = parts[2...].joined(separator: "|")
        } else if body.lowercased().hasPrefix(term.lowercased()) {
            body = String(body.dropFirst(term.count))
        }

        for marker in ["TỪ ĐỒNG NGHĨA", "ĐỒNG NGHĨA", "Xem thêm", "NGUỒN GỐC"] {
            if let r = body.range(of: marker, options: .caseInsensitive) {
                body = String(body[..<r.lowerBound])
            }
        }

        body = body.replacingOccurrences(of: "\n", with: " ")
        while body.contains("  ") { body = body.replacingOccurrences(of: "  ", with: " ") }
        // Put each numbered sense ("1 …", "2 …") on its own line — even glued to a word ("incrustation1").
        body = body.replacingOccurrences(of: #"(?<!\d)(\d{1,2})\s"#, with: "\n$1. ", options: .regularExpression)
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : String(body.prefix(400))
    }
}
