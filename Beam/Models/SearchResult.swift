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
    case timezone = "Time Zone"

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
        case .timezone: return "clock.fill"
        }
    }
}

struct ResultAction {
    let name: String
    let handler: () -> Void
}

struct SearchResult: Identifiable {
    let id = UUID()
    let type: SearchResultType
    let title: String
    let subtitle: String
    let icon: NSImage?
    let actions: [ResultAction]

    /// Convenience for backward compat — primary action
    var action: () -> Void { actions.first?.handler ?? {} }
}
