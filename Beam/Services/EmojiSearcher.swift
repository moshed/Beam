import AppKit

class EmojiSearcher {
    private var emojiData: [(emoji: String, name: String)] = []

    init() {
        loadEmoji()
    }

    private func loadEmoji() {
        // Build emoji list from Unicode ranges with their names
        var results: [(String, String)] = []
        // Common emoji ranges
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, // Emoticons
            0x1F300...0x1F5FF, // Misc Symbols and Pictographs
            0x1F680...0x1F6FF, // Transport and Map
            0x1F700...0x1F77F, // Alchemical
            0x1F780...0x1F7FF, // Geometric Shapes Extended
            0x1F900...0x1F9FF, // Supplemental Symbols
            0x1FA00...0x1FA6F, // Chess Symbols
            0x1FA70...0x1FAFF, // Symbols and Pictographs Extended-A
            0x2600...0x26FF,   // Misc symbols
            0x2700...0x27BF,   // Dingbats
            0x231A...0x231B,   // Watch, hourglass
            0x23E9...0x23F3,   // Various
            0x23F8...0x23FA,   // Various
            0x25AA...0x25AB,   // Squares
            0x25B6...0x25B6,   // Play
            0x25C0...0x25C0,   // Reverse
            0x25FB...0x25FE,   // Squares
            0x2614...0x2615,   // Umbrella, hot beverage
            0x2648...0x2653,   // Zodiac
            0x267F...0x267F,   // Wheelchair
            0x2693...0x2693,   // Anchor
            0x2702...0x2702,   // Scissors
            0x2708...0x2708,   // Airplane
            0x2764...0x2764,   // Heart
        ]

        for range in ranges {
            for scalar in range {
                guard let unicode = Unicode.Scalar(scalar) else { continue }
                let char = String(Character(unicode))
                guard let name = unicode.properties.name?.lowercased(), !name.isEmpty else { continue }
                // Filter out characters that can't be rendered (show as ? in box)
                guard canRender(char) else { continue }
                results.append((char, name))
            }
        }

        emojiData = results
    }

    func search(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else { return [] }

        // Search keyword — strip "emoji " prefix if present
        var keyword = trimmed
        if keyword.hasPrefix("emoji ") {
            keyword = String(keyword.dropFirst(6))
        }
        guard keyword.count >= 2 else { return [] }

        let matches = emojiData.filter { matchesKeyword($0.name, keyword) }

        return matches.prefix(50).map { item in
            let emoji = item.emoji
            let name = item.name.capitalized
            return SearchResult(
                type: .emoji,
                title: "\(emoji)  \(name)",
                subtitle: "Copy to clipboard",
                icon: nil,
                actions: [
                    ResultAction(name: "Insert") {
                        AppDelegate.shared?.insertTextIntoPreviousApp(emoji)
                    },
                    ResultAction(name: "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(emoji, forType: .string)
                    },
                    ResultAction(name: "Copy name") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(name, forType: .string)
                    },
                ]
            )
        }
    }

    // MARK: - Unicode Search

    func searchUnicode(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()

        // "unicode <name>" or "u+ <hex>" — explicit prefixes return up to 50 results
        // Bare queries (e.g. "arrow", "bullet") also search Unicode but cap at fewer results
        // to avoid drowning out other categories.
        var keyword: String?
        var resultLimit = 50
        if trimmed.hasPrefix("unicode ") {
            keyword = String(trimmed.dropFirst(8))
        } else if trimmed.hasPrefix("u+") {
            // Hex code point lookup
            let hex = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                let char = String(Character(scalar))
                let name = scalar.properties.name ?? "UNKNOWN"
                let displayName = name.capitalized
                return [SearchResult(
                    type: .unicode,
                    title: "\(char)  U+\(hex.uppercased())",
                    subtitle: displayName,
                    icon: nil,
                    actions: [
                        ResultAction(name: "Insert") {
                            AppDelegate.shared?.insertTextIntoPreviousApp(char)
                        },
                        ResultAction(name: "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(char, forType: .string)
                        },
                        ResultAction(name: "Copy name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(displayName, forType: .string)
                        },
                    ]
                )]
            }
            return []
        }

        // Fall back to bare query as a Unicode keyword (limited results to keep results clean)
        if keyword == nil && trimmed.count >= 3 {
            keyword = trimmed
            resultLimit = 12
        }

        guard let kw = keyword, kw.count >= 2 else { return [] }

        // Search all Unicode characters by name (broader than emoji)
        var results: [SearchResult] = []
        // Check a wider range
        let ranges: [ClosedRange<UInt32>] = [
            0x0021...0x007E,   // Basic ASCII symbols
            0x00A0...0x00FF,   // Latin-1 Supplement
            0x0100...0x024F,   // Latin Extended
            0x0370...0x03FF,   // Greek
            0x0400...0x04FF,   // Cyrillic
            0x2000...0x206F,   // General Punctuation
            0x2070...0x209F,   // Superscripts/Subscripts
            0x20A0...0x20CF,   // Currency Symbols
            0x2100...0x214F,   // Letterlike Symbols
            0x2150...0x218F,   // Number Forms
            0x2190...0x21FF,   // Arrows
            0x2200...0x22FF,   // Mathematical Operators
            0x2300...0x23FF,   // Misc Technical
            0x2500...0x257F,   // Box Drawing
            0x2580...0x259F,   // Block Elements
            0x25A0...0x25FF,   // Geometric Shapes
            0x2600...0x26FF,   // Misc Symbols
            0x2700...0x27BF,   // Dingbats
        ]

        for range in ranges {
            for scalar in range {
                guard let unicode = Unicode.Scalar(scalar) else { continue }
                if let name = unicode.properties.name?.lowercased(), matchesKeyword(name, kw) {
                    let char = String(Character(unicode))
                    guard canRender(char) else { continue }
                    let hexCode = String(format: "%04X", scalar)
                    let displayName = name.capitalized
                    results.append(SearchResult(
                        type: .unicode,
                        title: "\(char)  U+\(hexCode)",
                        subtitle: displayName,
                        icon: nil,
                        actions: [
                            ResultAction(name: "Insert") {
                                AppDelegate.shared?.insertTextIntoPreviousApp(char)
                            },
                            ResultAction(name: "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(char, forType: .string)
                            },
                            ResultAction(name: "Copy name") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(displayName, forType: .string)
                            },
                        ]
                    ))
                }
                if results.count >= resultLimit { break }
            }
            if results.count >= resultLimit { break }
        }

        return results
    }

    /// Match keyword against name: exact substring OR any word in name starts with the keyword.
    /// Also tries the singular form (drops trailing 's') so "arrows" matches "ARROW".
    private func matchesKeyword(_ name: String, _ keyword: String) -> Bool {
        if checkKeyword(name, keyword) { return true }
        if keyword.count > 3 && keyword.hasSuffix("s") {
            return checkKeyword(name, String(keyword.dropLast()))
        }
        return false
    }

    private func checkKeyword(_ name: String, _ keyword: String) -> Bool {
        if name.contains(keyword) { return true }
        let words = name.components(separatedBy: .whitespaces)
        return words.contains(where: { $0.hasPrefix(keyword) })
    }

    /// Check if a character can be rendered by the system (not shown as ? in box)
    private func canRender(_ str: String) -> Bool {
        var unichars = Array(str.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
        // Try Apple Color Emoji first (for emoji)
        let emojiFont = CTFontCreateWithName("Apple Color Emoji" as CFString, 12, nil)
        if CTFontGetGlyphsForCharacters(emojiFont, &unichars, &glyphs, unichars.count) { return true }
        // Then system font (for unicode symbols)
        let sysFont = NSFont.systemFont(ofSize: 12) as CTFont
        return CTFontGetGlyphsForCharacters(sysFont, &unichars, &glyphs, unichars.count)
    }
}
