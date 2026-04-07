import Foundation
import Carbon
import ServiceManagement

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    static let defaultToggle = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let defaultHistory = KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: 0)
    static let defaultExpand = KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(cmdKey))
    static let defaultCollapse = KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey))

    func matches(keyCode kc: UInt32, modifiers mods: UInt32) -> Bool {
        self.keyCode == kc && self.modifiers == mods
    }
}

func keyCodeToString(_ keyCode: UInt32) -> String {
    let map: [UInt32: String] = [
        UInt32(kVK_Return): "↵", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓", UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
    ]
    return map[keyCode] ?? "Key\(keyCode)"
}

enum ResultDisplayMode: String, CaseIterable {
    case relevance = "Relevance"
    case grouped = "Grouped"
}

/// Available actions per result type (names must match what searchers provide)
struct CategoryActions {
    static let available: [SearchResultType: [String]] = [
        .math: ["Copy result", "Copy query + result"],
        .contact: ["Open in Contacts", "Call", "Copy number"],
        .app: ["Open", "Reveal in Finder"],
        .file: ["Open", "Reveal in Finder", "Open With..."],
        .calendar: ["Open in Calendar"],
        .reminder: ["Open in Reminders", "Mark complete", "Postpone due date"],
        .shortcut: ["Run", "Open in Shortcuts"],
        .definition: ["Copy definition", "Copy word"],
        .emoji: ["Copy"],
        .timezone: ["Copy time"],
    ]
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var toggleShortcut: KeyCombo {
        didSet { saveKeyCombo(toggleShortcut, forKey: "toggleShortcut") }
    }

    @Published var historyShortcut: KeyCombo {
        didSet { saveKeyCombo(historyShortcut, forKey: "historyShortcut") }
    }

    @Published var expandShortcut: KeyCombo {
        didSet { saveKeyCombo(expandShortcut, forKey: "expandShortcut") }
    }

    @Published var collapseShortcut: KeyCombo {
        didSet { saveKeyCombo(collapseShortcut, forKey: "collapseShortcut") }
    }

    @Published var resultDisplayMode: ResultDisplayMode {
        didSet { UserDefaults.standard.set(resultDisplayMode.rawValue, forKey: "resultDisplayMode") }
    }

    /// Per-category action order: maps type -> [action indices] for Enter, Shift+Enter, Option+Enter
    @Published var actionOrder: [String: [Int]] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(actionOrder) {
                UserDefaults.standard.set(data, forKey: "actionOrder")
            }
        }
    }

    /// Reminder due date offset in minutes (default 30)
    @Published var reminderDueDateOffsetMinutes: Int {
        didSet { UserDefaults.standard.set(reminderDueDateOffsetMinutes, forKey: "reminderDueDateOffsetMinutes") }
    }

    /// Section ordering for grouped mode
    @Published var sectionOrder: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(sectionOrder) {
                UserDefaults.standard.set(data, forKey: "sectionOrder")
            }
        }
    }

    static let defaultSectionOrder: [String] = [
        "Math", "Time Zone", "Definition", "App", "Shortcut",
        "Contact", "Calendar", "Reminder", "Emoji", "File"
    ]

    func sectionIndex(for type: SearchResultType) -> Int {
        if let idx = sectionOrder.firstIndex(of: type.rawValue) {
            return idx
        }
        return 999
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }

    var onToggleShortcutChanged: (() -> Void)?

    private init() {
        self.toggleShortcut = SettingsManager.loadKeyCombo(forKey: "toggleShortcut") ?? .defaultToggle
        self.historyShortcut = SettingsManager.loadKeyCombo(forKey: "historyShortcut") ?? .defaultHistory
        self.expandShortcut = SettingsManager.loadKeyCombo(forKey: "expandShortcut") ?? .defaultExpand
        self.collapseShortcut = SettingsManager.loadKeyCombo(forKey: "collapseShortcut") ?? .defaultCollapse

        let modeStr = UserDefaults.standard.string(forKey: "resultDisplayMode") ?? ResultDisplayMode.relevance.rawValue
        self.resultDisplayMode = ResultDisplayMode(rawValue: modeStr) ?? .relevance

        if let data = UserDefaults.standard.data(forKey: "actionOrder"),
           let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            self.actionOrder = decoded
        }

        self.reminderDueDateOffsetMinutes = UserDefaults.standard.object(forKey: "reminderDueDateOffsetMinutes") as? Int ?? 30

        if let data = UserDefaults.standard.data(forKey: "sectionOrder"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.sectionOrder = decoded
        } else {
            self.sectionOrder = SettingsManager.defaultSectionOrder
        }
    }

    /// Get the action index for a given slot (0=Enter, 1=Shift+Enter, 2=Option+Enter) and type
    func actionIndex(for type: SearchResultType, slot: Int) -> Int {
        if let order = actionOrder[type.rawValue], slot < order.count {
            return order[slot]
        }
        // Default: slot 0 -> action 0, slot 1 -> action 1, etc.
        return slot
    }

    /// Set the action index for a slot
    func setActionIndex(for type: SearchResultType, slot: Int, actionIdx: Int) {
        var order = actionOrder[type.rawValue] ?? [0, 1, 2]
        while order.count <= slot { order.append(order.count) }
        order[slot] = actionIdx
        actionOrder[type.rawValue] = order
    }

    private func saveKeyCombo(_ combo: KeyCombo, forKey key: String) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: key)
        }
        onToggleShortcutChanged?()
    }

    private static func loadKeyCombo(forKey key: String) -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }
}
