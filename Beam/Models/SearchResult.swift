import AppKit

enum SearchResultType: String, CaseIterable {
    case math = "Math"
    case contact = "Contact"
    case app = "App"
    case file = "File"
    case calendar = "Calendar"
    case reminder = "Reminder"
    case shortcut = "Shortcut"
    case definition = "Definition"
    case emoji = "Emoji"
    case unicode = "Unicode"
    case timezone = "Time Zone"
    case ai = "Ask AI"

    var sectionOrder: Int {
        return SettingsManager.shared.sectionIndex(for: self)
    }

    var iconName: String {
        switch self {
        case .math: return "equal.circle.fill"
        case .contact: return "person.circle.fill"
        case .app: return "app.fill"
        case .file: return "doc.fill"
        case .calendar: return "calendar"
        case .reminder: return "checklist"
        case .shortcut: return "arrow.trianglehead.turn.up.right.diamond.fill"
        case .definition: return "book.closed.fill"
        case .emoji: return "face.smiling"
        case .unicode: return "textformat.abc"
        case .timezone: return "clock.fill"
        case .ai: return "sparkles"
        }
    }
}

struct ResultAction {
    let name: String
    let handler: () -> Void
}

struct DetailItem {
    let label: String
    let value: String
    let icon: String?
    let actions: [ResultAction]
}

struct SearchResult: Identifiable {
    let id = UUID()
    let type: SearchResultType
    let title: String
    let subtitle: String
    let icon: NSImage?
    let actions: [ResultAction]
    var details: [DetailItem] = []
    /// Optional styled subtitle (e.g. math with stripped labels struck through).
    var attributedSubtitle: AttributedString? = nil

    var action: () -> Void { actions.first?.handler ?? {} }
    var isExpandable: Bool { !details.isEmpty }
}
