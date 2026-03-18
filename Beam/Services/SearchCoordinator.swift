import AppKit
import Combine

struct MathResultInfo: Equatable {
    let expression: String
    let result: String
}

@Observable
class SearchCoordinator {
    var query: String = ""
    var results: [SearchResult] = []
    var mathResultInfo: MathResultInfo?
    var selectedIndex: Int = 0
    var displayMode: ResultDisplayMode = SettingsManager.shared.resultDisplayMode
    var previousQuery: String = ""

    private let appSearcher = AppSearcher()
    private let contactSearcher = ContactSearcher()
    private let fileSearcher = FileSearcher()
    private let calendarSearcher = CalendarSearcher()
    private let shortcutSearcher = ShortcutSearcher()
    private let dictionarySearcher = DictionarySearcher()
    private let emojiSearcher = EmojiSearcher()
    private let timezoneSearcher = TimeZoneSearcher()
    private var debounceTimer: Timer?
    private var suppressDidSet = false

    init() {
        MathEvaluator.fetchRates()
    }

    /// Called from SearchBarView when text changes
    func queryChanged(_ newQuery: String) {
        query = newQuery
        scheduleSearch()
    }

    /// Called when panel opens — restore previous query
    func restorePrevious() {
        suppressDidSet = true
        query = previousQuery
        suppressDidSet = false
        if !query.isEmpty {
            let eval = MathEvaluator.evaluate(query)
            mathResultInfo = eval.map { MathResultInfo(expression: $0.expression, result: $0.result) }
            performSearch(query)
        } else {
            mathResultInfo = nil
            results = []
        }
    }

    /// Esc clears input but saves it first
    func clearInput() {
        if !query.isEmpty {
            previousQuery = query
        }
        suppressDidSet = true
        query = ""
        suppressDidSet = false
        results = []
        mathResultInfo = nil
        selectedIndex = 0
        fileSearcher.stop()
    }

    /// Called on dismiss
    func saveAndClear() {
        if !query.isEmpty {
            previousQuery = query
        }
        suppressDidSet = true
        query = ""
        suppressDidSet = false
        results = []
        mathResultInfo = nil
        selectedIndex = 0
        fileSearcher.stop()
        debounceTimer?.invalidate()
    }

    /// Execute action for a given slot (0=Enter, 1=Shift+Enter, 2=Option+Enter)
    func executeAction(slot: Int) {
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        guard !result.actions.isEmpty else { return }
        let actionIdx = SettingsManager.shared.actionIndex(for: result.type, slot: slot)
        let clampedIdx = min(actionIdx, result.actions.count - 1)
        result.actions[max(0, clampedIdx)].handler()
    }

    func executeSelected() { executeAction(slot: 0) }
    func executeShiftEnter() { executeAction(slot: 1) }
    func executeOptionEnter() { executeAction(slot: 2) }

    func toggleDisplayMode() {
        displayMode = displayMode == .relevance ? .grouped : .relevance
        SettingsManager.shared.resultDisplayMode = displayMode
        if displayMode == .grouped {
            let math = results.filter { $0.type == .math }
            let rest = results.filter { $0.type != .math }.sorted { $0.type.sectionOrder < $1.type.sectionOrder }
            results = math + rest
        }
    }

    func moveUp() {
        if selectedIndex > 0 { selectedIndex -= 1 }
    }

    func moveDown() {
        if selectedIndex < results.count - 1 { selectedIndex += 1 }
    }

    private func scheduleSearch() {
        debounceTimer?.invalidate()
        let q = query
        if q.isEmpty {
            results = []
            mathResultInfo = nil
            selectedIndex = 0
            fileSearcher.stop()
            return
        }

        // Math is instant — use proper struct so @Observable tracks it
        let eval = MathEvaluator.evaluate(q)
        mathResultInfo = eval.map { MathResultInfo(expression: $0.expression, result: $0.result) }

        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.performSearch(q)
        }
    }

    private func performSearch(_ q: String) {
        var merged: [SearchResult] = []

        if let math = mathResultInfo {
            let resultText = math.result
            let exprText = math.expression
            merged.append(SearchResult(
                type: .math,
                title: "= \(resultText)",
                subtitle: exprText,
                icon: NSImage(systemSymbolName: "equal.circle.fill", accessibilityDescription: nil),
                actions: [
                    ResultAction(name: "Copy result") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resultText, forType: .string)
                    },
                    ResultAction(name: "Copy query + result") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(exprText) = \(resultText)", forType: .string)
                    },
                ]
            ))
        }

        let timezones = timezoneSearcher.search(q)
        let definitions = dictionarySearcher.search(q)
        let apps = appSearcher.search(q)
        let shortcuts = shortcutSearcher.search(q)
        let contacts = contactSearcher.search(q)
        let events = calendarSearcher.searchEvents(q)
        let reminders = calendarSearcher.searchReminders(q)
        let emoji = emojiSearcher.search(q)
        let unicode = emojiSearcher.searchUnicode(q)

        merged.append(contentsOf: timezones)
        merged.append(contentsOf: definitions)
        merged.append(contentsOf: apps)
        merged.append(contentsOf: shortcuts)
        merged.append(contentsOf: contacts)
        merged.append(contentsOf: events)
        merged.append(contentsOf: reminders)
        merged.append(contentsOf: emoji)
        merged.append(contentsOf: unicode)

        if displayMode == .grouped {
            let mathResults = merged.filter { $0.type == .math }
            let rest = merged.filter { $0.type != .math }.sorted { $0.type.sectionOrder < $1.type.sectionOrder }
            merged = mathResults + rest
        }

        results = merged
        selectedIndex = 0

        fileSearcher.search(q) { [weak self] fileResults in
            guard let self = self, self.query == q else { return }
            let nonFileResults = self.results.filter { $0.type != .file }
            self.results = nonFileResults + fileResults
        }
    }
}
