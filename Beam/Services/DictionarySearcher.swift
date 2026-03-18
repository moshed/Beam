import AppKit
import CoreServices

class DictionarySearcher {
    func search(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        // Check if query starts with "define " — use the rest as the word
        var word = trimmed
        let lower = trimmed.lowercased()
        if lower.hasPrefix("define ") {
            word = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }

        // Skip if it looks like math, a path, or has numbers
        if word.contains("/") || word.contains("*") || word.contains("+") ||
           word.contains("$") || word.contains(".") { return [] }
        if word.rangeOfCharacter(from: .decimalDigits) != nil { return [] }

        // Only look up single words or two-word phrases
        let wordCount = word.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        guard wordCount <= 2 else { return [] }

        guard let definition = DCSCopyTextDefinition(nil, word as CFString, CFRangeMake(0, word.utf16.count))?.takeRetainedValue() as String? else {
            return []
        }

        // Trim to first ~150 chars for subtitle
        let short = definition.count > 150 ? String(definition.prefix(150)) + "..." : definition

        let icon = NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: nil)
        icon?.size = NSSize(width: 32, height: 32)

        let fullDef = definition
        let defWord = word
        return [SearchResult(
            type: .definition,
            title: defWord.capitalized,
            subtitle: short,
            icon: icon,
            actions: [
                ResultAction(name: "Copy definition") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(defWord): \(fullDef)", forType: .string)
                },
                ResultAction(name: "Copy word") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(defWord, forType: .string)
                },
            ]
        )]
    }
}
