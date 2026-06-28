import AppKit
import ApplicationServices

struct CapturedLookup {
    var term: String
    var context: String?
    var sourceApp: String?
    var sourceDetail: String?
}

/// Reads the currently selected text (the word being looked up) via the Accessibility API,
/// plus the surrounding sentence and the frontmost app. Falls back to a pasteboard copy.
final class LookupCapturer {

    func capture() -> CapturedLookup? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let sourceApp = frontApp?.localizedName

        if let element = focusedElement() {
            if let selected = selectedText(of: element),
               !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let context = surroundingSentence(of: element, selected: selected)
                return CapturedLookup(term: clean(selected), context: context,
                                      sourceApp: sourceApp, sourceDetail: windowTitle(of: element))
            }
        }
        return copyFallback(sourceApp: sourceApp)
    }

    // MARK: - Accessibility reads

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success
        else { return nil }
        return (value as! AXUIElement)
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// Best-effort: read the full text + selected range, then expand to sentence boundaries.
    private func surroundingSentence(of element: AXUIElement, selected: String) -> String? {
        var fullValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullValue) == .success,
              let full = fullValue as? String, !full.isEmpty else { return nil }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success
        else { return sentenceFallback(in: full, containing: selected) }

        var cfRange = CFRange()
        if AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange), cfRange.location != kCFNotFound {
            let ns = full as NSString
            let loc = min(max(cfRange.location, 0), ns.length)
            return sentence(in: full, atUTF16Offset: loc)
        }
        return sentenceFallback(in: full, containing: selected)
    }

    private func sentence(in text: String, atUTF16Offset offset: Int) -> String? {
        let ns = text as NSString
        var start = offset, end = offset
        let terminators = CharacterSet(charactersIn: ".!?\n")
        while start > 0 {
            let ch = ns.substring(with: NSRange(location: start - 1, length: 1))
            if ch.rangeOfCharacter(from: terminators) != nil { break }
            start -= 1
        }
        while end < ns.length {
            let ch = ns.substring(with: NSRange(location: end, length: 1))
            end += 1
            if ch.rangeOfCharacter(from: terminators) != nil { break }
        }
        let s = ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func sentenceFallback(in text: String, containing selected: String) -> String? {
        guard let r = text.range(of: selected) else { return nil }
        let offset = text.distance(from: text.startIndex, to: r.lowerBound)
        let utf16Offset = (text as NSString).length == text.count ? offset
            : (String(text[..<r.lowerBound]) as NSString).length
        return sentence(in: text, atUTF16Offset: utf16Offset)
    }

    private func windowTitle(of element: AXUIElement) -> String? {
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &win) == .success
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }

    // MARK: - Pasteboard fallback

    private func copyFallback(sourceApp: String?) -> CapturedLookup? {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let beforeCount = pb.changeCount

        sendCopy()

        // Poll briefly for the target app to update the pasteboard.
        var copied: String?
        for _ in 0..<20 {
            if pb.changeCount != beforeCount { copied = pb.string(forType: .string); break }
            usleep(10_000) // 10ms
        }

        // Restore the user's previous pasteboard contents.
        pb.clearContents()
        if let previous { pb.setString(previous, forType: .string) }

        guard let text = copied?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return CapturedLookup(term: clean(text), context: nil, sourceApp: sourceApp, sourceDetail: nil)
    }

    private func sendCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'C'
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cmdUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    /// Keep only the first ~6 words so a stray paragraph selection still yields a reasonable term.
    private func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count > 6 ? words.prefix(6).joined(separator: " ") : trimmed
    }
}
