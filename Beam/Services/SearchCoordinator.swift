import AppKit
import Combine
import SwiftUI

struct MathResultInfo: Equatable {
    let expression: String
    let result: String
    let isInfo: Bool
}

@Observable
class SearchCoordinator {
    var query: String = ""
    var results: [SearchResult] = []
    var mathResultInfo: MathResultInfo?
    /// Partial-evaluation result for the currently selected substring of the search bar
    /// (Excel-style: highlight a portion, see just that piece compute).
    var selectionMath: (text: String, result: String)?
    var selectedIndex: Int = 0
    var displayMode: ResultDisplayMode = SettingsManager.shared.resultDisplayMode
    var previousQuery: String = ""

    // Expand
    var expandedResultId: UUID? = nil
    var expandedDetailIndex: Int? = nil

    // Emoji grid
    static let emojiGridColumns = 8

    private static let gridTypes: Set<SearchResultType> = [.emoji, .unicode]

    var hasEmojiResults: Bool {
        results.contains(where: { Self.gridTypes.contains($0.type) })
    }

    /// True when the currently selected result is a grid item (emoji or unicode)
    var isSelectedEmoji: Bool {
        guard selectedIndex >= 0, selectedIndex < results.count else { return false }
        return Self.gridTypes.contains(results[selectedIndex].type)
    }

    /// Indices of grid-type results in the results array
    var emojiIndices: [Int] {
        results.enumerated().compactMap { Self.gridTypes.contains($0.element.type) ? $0.offset : nil }
    }

    /// All results are grid-type (panel height)
    var isEmojiGridMode: Bool {
        !results.isEmpty && results.allSatisfy { Self.gridTypes.contains($0.type) }
    }

    // Chat (Ask AI)
    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        let role: String // "user" or "assistant"
        var content: String
    }
    var isChatMode: Bool = false
    var chatMessages: [ChatMessage] = []
    var chatModel: String = ""
    var chatStreaming: Bool = false

    func enterChatMode(prompt: String) {
        let model = OllamaSearcher.shared.currentModel
        chatMessages = [ChatMessage(role: "user", content: prompt)]
        chatModel = model
        chatStreaming = true
        isChatMode = true
        appendAssistantPlaceholder()
        OllamaSearcher.shared.chat(messages: chatMessages.dropLast().map { ($0.role, $0.content) }) { [weak self] token in
            self?.appendAssistantToken(token)
        } completion: { [weak self] in
            self?.chatStreaming = false
        }
    }

    func sendChatMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !chatStreaming else { return }
        chatMessages.append(ChatMessage(role: "user", content: trimmed))
        chatStreaming = true
        appendAssistantPlaceholder()
        let history = chatMessages.dropLast().map { ($0.role, $0.content) }
        OllamaSearcher.shared.chat(messages: history) { [weak self] token in
            self?.appendAssistantToken(token)
        } completion: { [weak self] in
            self?.chatStreaming = false
        }
    }

    func exitChatMode() {
        OllamaSearcher.shared.cancelStreaming()
        isChatMode = false
        chatMessages = []
        chatStreaming = false
    }

    private func appendAssistantPlaceholder() {
        chatMessages.append(ChatMessage(role: "assistant", content: ""))
    }

    private func appendAssistantToken(_ token: String) {
        guard let last = chatMessages.indices.last, chatMessages[last].role == "assistant" else { return }
        chatMessages[last].content += token
    }

    // History
    var isHistoryMode = false
    var historyFilter: SearchResultType? = nil
    private var historyQueries: [String] = []

    // Auto-save history: idle timer + session tracking
    private var historyIdleTimer: Timer?
    private var pendingHistoryId: UUID?
    private static let historyIdleDelay: TimeInterval = 1.5

    private let appSearcher = AppSearcher()
    private let contactSearcher = ContactSearcher()
    private let fileSearcher = FileSearcher()
    private let placesSearcher = PlacesSearcher()
    let calendarSearcher = CalendarSearcher()
    private let shortcutSearcher = ShortcutSearcher()
    private let dictionarySearcher = DictionarySearcher()
    private let emojiSearcher = EmojiSearcher()
    private let timezoneSearcher = TimeZoneSearcher()
    private let ollamaSearcher = OllamaSearcher.shared
    private var debounceTimer: Timer?
    private var suppressDidSet = false

    init() {
        MathEvaluator.fetchRates()
    }

    /// Called when the search-bar selection changes — evaluates the selected substring
    /// and stores the partial result for inline display.
    func updateSelection(_ selected: String) {
        let trimmed = selected.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != query.trimmingCharacters(in: .whitespaces) else {
            selectionMath = nil
            return
        }
        if let r = MathEvaluator.evaluate(trimmed) {
            selectionMath = (trimmed, r.result)
        } else {
            selectionMath = nil
        }
    }

    /// Called from SearchBarView when text changes
    func queryChanged(_ newQuery: String) {
        query = newQuery
        if isHistoryMode && !newQuery.isEmpty {
            exitHistoryMode()
            query = newQuery
            scheduleSearch()
        } else if !isHistoryMode {
            scheduleSearch()
        }
        restartHistoryIdleTimer()
    }

    /// Called when panel opens — restore previous query
    func restorePrevious() {
        pendingHistoryId = nil
        suppressDidSet = true
        query = previousQuery
        suppressDidSet = false
        if !query.isEmpty {
            let eval = MathEvaluator.evaluate(query)
            mathResultInfo = eval.map { MathResultInfo(expression: $0.expression, result: $0.result, isInfo: $0.isInfo) }
            performSearch(query)
        } else {
            mathResultInfo = nil
            results = []
        }
    }

    /// Esc clears input but saves it first
    func clearInput() {
        if isHistoryMode {
            exitHistoryMode()
            return
        }
        flushHistoryIfNeeded()
        pendingHistoryId = nil
        if !query.isEmpty {
            previousQuery = query
        }
        suppressDidSet = true
        query = ""
        suppressDidSet = false
        results = []
        mathResultInfo = nil
        selectionMath = nil
        selectedIndex = 0
        fileSearcher.stop()
    }

    /// Called on dismiss
    func saveAndClear() {
        if isHistoryMode { exitHistoryMode() }
        flushHistoryIfNeeded()
        pendingHistoryId = nil
        previousQuery = query
        suppressDidSet = true
        query = ""
        suppressDidSet = false
        results = []
        mathResultInfo = nil
        selectionMath = nil
        selectedIndex = 0
        fileSearcher.stop()
        debounceTimer?.invalidate()
    }

    /// Execute action for a given slot (0=Enter, 1=Shift+Enter, 2=Option+Enter)
    /// Returns true if the panel should dismiss
    @discardableResult
    func executeAction(slot: Int) -> Bool {
        guard selectedIndex >= 0, selectedIndex < results.count else { return false }

        if isHistoryMode {
            guard selectedIndex < historyQueries.count else { return false }
            let originalQuery = historyQueries[selectedIndex]
            exitHistoryMode()
            query = originalQuery
            let eval = MathEvaluator.evaluate(query)
            mathResultInfo = eval.map { MathResultInfo(expression: $0.expression, result: $0.result, isInfo: $0.isInfo) }
            performSearch(query)
            return false
        }

        let result = results[selectedIndex]

        // Save/update history with the executed result
        historyIdleTimer?.invalidate()
        pendingHistoryId = HistoryManager.shared.upsert(
            id: pendingHistoryId,
            query: query,
            title: result.title,
            subtitle: result.subtitle,
            typeName: result.type.rawValue
        )
        pendingHistoryId = nil // session complete

        guard !result.actions.isEmpty else { return true }
        let actionIdx = SettingsManager.shared.actionIndex(for: result.type, slot: slot)
        let clampedIdx = min(actionIdx, result.actions.count - 1)
        let action = result.actions[max(0, clampedIdx)]
        NSLog("[BEAM-DIAL] executeAction slot=%d resultType=%@ title=%@ action=%@",
              slot, result.type.rawValue, result.title, action.name)
        action.handler()
        if isChatMode { return false }
        return action.dismissesPanel
    }

    /// Drop a math result into the search bar so the user can keep computing.
    func useAsInput(_ text: String) {
        queryChanged(text)
    }

    func executeSelected() -> Bool { executeAction(slot: 0) }
    func executeShiftEnter() -> Bool { executeAction(slot: 1) }
    func executeOptionEnter() -> Bool { executeAction(slot: 2) }

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
        if isSelectedEmoji {
            let indices = emojiIndices
            let cols = Self.emojiGridColumns
            if let pos = indices.firstIndex(of: selectedIndex) {
                if pos >= cols {
                    selectedIndex = indices[pos - cols]
                } else {
                    // At top row of grid — move to result before the emoji block
                    let firstEmoji = indices[0]
                    if firstEmoji > 0 { selectedIndex = firstEmoji - 1 }
                }
            }
            return
        }
        // If inside expanded details, navigate up through them
        if let detailIdx = expandedDetailIndex {
            if detailIdx > 0 {
                expandedDetailIndex = detailIdx - 1
            } else {
                expandedDetailIndex = nil
            }
            return
        }
        if selectedIndex > 0 {
            collapseExpanded()
            selectedIndex -= 1
        }
    }

    func moveDown() {
        if isSelectedEmoji {
            let indices = emojiIndices
            let cols = Self.emojiGridColumns
            if let pos = indices.firstIndex(of: selectedIndex) {
                if pos + cols < indices.count {
                    selectedIndex = indices[pos + cols]
                } else {
                    // At bottom row of grid — move to result after the emoji block
                    let lastEmoji = indices.last!
                    if lastEmoji < results.count - 1 {
                        selectedIndex = lastEmoji + 1
                    }
                }
            }
            return
        }
        // If expanded and on main row (no detail selected), enter details
        if expandedResultId != nil, expandedDetailIndex == nil {
            let result = results[selectedIndex]
            if !result.details.isEmpty {
                expandedDetailIndex = 0
                return
            }
        }
        // If inside details, navigate down
        if let detailIdx = expandedDetailIndex {
            let result = results[selectedIndex]
            if detailIdx < result.details.count - 1 {
                expandedDetailIndex = detailIdx + 1
            } else {
                collapseExpanded()
                if selectedIndex < results.count - 1 {
                    selectedIndex += 1
                }
            }
            return
        }
        if selectedIndex < results.count - 1 {
            collapseExpanded()
            selectedIndex += 1
        }
    }

    func moveLeft() {
        if isSelectedEmoji {
            // Move to previous emoji in the grid
            let indices = emojiIndices
            if let pos = indices.firstIndex(of: selectedIndex), pos > 0 {
                selectedIndex = indices[pos - 1]
            }
        }
    }

    func moveRight() {
        if isSelectedEmoji {
            // Move to next emoji in the grid
            let indices = emojiIndices
            if let pos = indices.firstIndex(of: selectedIndex), pos < indices.count - 1 {
                selectedIndex = indices[pos + 1]
            }
        }
    }

    func expandSelected() {
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        guard result.isExpandable else { return }
        if expandedResultId == result.id {
            collapseExpanded()
        } else {
            expandedResultId = result.id
            expandedDetailIndex = nil
        }
    }

    func collapseExpanded() {
        expandedResultId = nil
        expandedDetailIndex = nil
    }

    /// Get the actions for the currently focused item (detail or main result)
    var focusedActions: [ResultAction] {
        guard selectedIndex >= 0, selectedIndex < results.count else { return [] }
        if let detailIdx = expandedDetailIndex,
           expandedResultId == results[selectedIndex].id,
           detailIdx < results[selectedIndex].details.count {
            return results[selectedIndex].details[detailIdx].actions
        }
        return results[selectedIndex].actions
    }

    /// Execute action on the currently focused item
    func executeFocusedAction(slot: Int) -> Bool {
        let actions = focusedActions
        NSLog("[BEAM-DIAL] executeFocusedAction slot=%d actionsCount=%d expandedDetail=%@ query=%@",
              slot, actions.count,
              expandedDetailIndex.map(String.init) ?? "nil",
              query)
        guard !actions.isEmpty else { return false }

        // If on a detail item, execute its action directly
        if expandedDetailIndex != nil {
            let idx = min(slot, actions.count - 1)
            let picked = actions[max(0, idx)]
            NSLog("[BEAM-DIAL] detail action=%@", picked.name)
            picked.handler()
            return true
        }

        // Normal result execution
        return executeAction(slot: slot)
    }

    // MARK: - History Auto-Save

    private func restartHistoryIdleTimer() {
        historyIdleTimer?.invalidate()
        guard !query.isEmpty, !isHistoryMode else { return }
        historyIdleTimer = Timer.scheduledTimer(withTimeInterval: Self.historyIdleDelay, repeats: false) { [weak self] _ in
            self?.autoSaveHistory()
        }
    }

    private func autoSaveHistory() {
        guard !query.isEmpty, !isHistoryMode else { return }

        let topResult = results.first
        let title = topResult?.title ?? query
        let subtitle = topResult?.subtitle ?? ""
        let typeName = topResult?.type.rawValue ?? SearchResultType.math.rawValue

        pendingHistoryId = HistoryManager.shared.upsert(
            id: pendingHistoryId,
            query: query,
            title: title,
            subtitle: subtitle,
            typeName: typeName
        )
    }

    /// Flush any pending idle save (e.g. on dismiss/clear before timer fires)
    private func flushHistoryIfNeeded() {
        historyIdleTimer?.invalidate()
        guard !query.isEmpty, !isHistoryMode else { return }
        autoSaveHistory()
    }

    // MARK: - History Display

    func showHistory() {
        isHistoryMode = true
        historyFilter = nil
        mathResultInfo = nil
        populateHistoryResults()
    }

    func setHistoryFilter(_ type: SearchResultType?) {
        historyFilter = type
        populateHistoryResults()
    }

    func cycleHistoryFilter(forward: Bool) {
        let types = HistoryManager.shared.availableTypes
        guard !types.isEmpty else { return }

        // Options: nil (All), then each type
        let options: [SearchResultType?] = [nil] + types.map { $0 as SearchResultType? }
        let currentIdx = options.firstIndex(where: { $0 == historyFilter }) ?? 0

        let nextIdx: Int
        if forward {
            nextIdx = (currentIdx + 1) % options.count
        } else {
            nextIdx = (currentIdx - 1 + options.count) % options.count
        }
        setHistoryFilter(options[nextIdx])
    }

    func exitHistoryMode() {
        isHistoryMode = false
        historyFilter = nil
        historyQueries = []
        results = []
        mathResultInfo = nil
        selectedIndex = 0
        suppressDidSet = true
        query = ""
        suppressDidSet = false
    }

    private func populateHistoryResults() {
        let entries = HistoryManager.shared.filteredEntries(type: historyFilter)

        historyQueries = []
        results = entries.prefix(15).map { entry in
            historyQueries.append(entry.query)
            let icon: NSImage?
            if let type = entry.type {
                icon = NSImage(systemSymbolName: type.iconName, accessibilityDescription: nil)
            } else {
                icon = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
            }
            return SearchResult(
                type: entry.type ?? .math,
                title: entry.title,
                subtitle: relativeTime(entry.timestamp) + "  ·  " + entry.query,
                icon: icon,
                actions: [ResultAction(name: "Search again") {}]
            )
        }
        selectedIndex = 0
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "Just now" }
        if seconds < 3600 {
            let m = Int(seconds / 60)
            return m == 1 ? "1 min ago" : "\(m) min ago"
        }
        if seconds < 86400 {
            let h = Int(seconds / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        if seconds < 604800 {
            let d = Int(seconds / 86400)
            return d == 1 ? "Yesterday" : "\(d) days ago"
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    // MARK: - Search

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

        let eval = MathEvaluator.evaluate(q)
        mathResultInfo = eval.map { MathResultInfo(expression: $0.expression, result: $0.result, isInfo: $0.isInfo) }

        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.performSearch(q)
        }
    }

    private func performSearch(_ q: String) {
        var merged: [SearchResult] = []

        // If the query looks like a phone number, don't show a math result — parens
        // and dashes would otherwise be parsed as grouping/subtraction.
        let phone = Self.phoneNumberResult(for: q).map { [$0] } ?? []
        if !phone.isEmpty {
            mathResultInfo = nil
        }

        if let math = mathResultInfo {
            let resultText = math.result
            let exprText = math.expression
            let isInfo = math.isInfo
            // Visually drop the "=" — the icon already conveys it. Copy actions
            // (which use exprText + " = " + resultText) still produce the full string.
            let title = resultText
            let icon = isInfo ? "calendar.circle.fill" : "equal.circle.fill"
            let separator = isInfo ? " is " : " = "
            var mathRow = SearchResult(
                type: .math,
                title: title,
                subtitle: exprText,
                icon: NSImage(systemSymbolName: icon, accessibilityDescription: nil),
                actions: [
                    ResultAction(name: "Copy result") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.beamSet(resultText)
                    },
                    ResultAction(name: "Copy query + result") {
                        let lhs = isInfo ? exprText
                            : MathEvaluator.normalizeExpression(exprText, expectedResult: resultText)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.beamSet("\(lhs)\(separator)\(resultText)")
                    },
                    ResultAction(name: "Use as input", dismissesPanel: false) {
                        // Extract just the numeric portion (strip currency/unit suffix
                        // and thousands commas) so it can be used in further math.
                        let m = resultText.range(of: #"-?[\d,]+(?:\.\d+)?"#, options: .regularExpression)
                        let numeric = m.map { String(resultText[$0]) } ?? resultText
                        let clean = numeric.replacingOccurrences(of: ",", with: "")
                        AppDelegate.shared?.searchCoordinator.useAsInput(clean)
                    },
                ]
            )
            // Strike through any stripped label tokens so it's clear what was calculated.
            if !isInfo {
                mathRow.attributedSubtitle = MathEvaluator.labelHighlightedExpression(exprText)
            }
            merged.append(mathRow)

            // Second row for ambiguous dimension input: per-axis conversion
            // (the primary row above is the multiply+convert volume).
            if let secondary = MathEvaluator.secondaryResult(q) {
                let secText = secondary.result
                merged.append(SearchResult(
                    type: .math,
                    title: secText,
                    subtitle: "\(secondary.expression) (per axis)",
                    icon: NSImage(systemSymbolName: "ruler", accessibilityDescription: nil),
                    actions: [
                        ResultAction(name: "Copy result") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.beamSet(secText)
                        },
                        ResultAction(name: "Copy query + result") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.beamSet("\(secondary.expression) = \(secText)")
                        },
                        ResultAction(name: "Use as input", dismissesPanel: false) {
                            AppDelegate.shared?.searchCoordinator.useAsInput(secText)
                        },
                    ]
                ))
            }

            // Volume in the SOURCE unit — raw product, no conversion (e.g.
            // "375 * 285 * 1,065mm" → "113,821,875 mm³"). Skipped when source == target
            // (the primary row already shows that).
            if let srcVol = MathEvaluator.dimensionsSourceVolume(q) {
                let sText = srcVol.result
                merged.append(SearchResult(
                    type: .math,
                    title: sText,
                    subtitle: "\(srcVol.expression) (source units)",
                    icon: NSImage(systemSymbolName: "cube", accessibilityDescription: nil),
                    actions: [
                        ResultAction(name: "Copy result") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.beamSet(sText)
                        },
                        ResultAction(name: "Copy query + result") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.beamSet("\(srcVol.expression) = \(sText)")
                        },
                        ResultAction(name: "Use as input", dismissesPanel: false) {
                            let m = sText.range(of: #"-?[\d,]+(?:\.\d+)?"#, options: .regularExpression)
                            let numeric = m.map { String(sText[$0]) } ?? sText
                            AppDelegate.shared?.searchCoordinator.useAsInput(numeric.replacingOccurrences(of: ",", with: ""))
                        },
                    ]
                ))
            }

            // Pure-arithmetic interpretation when a bare "m" makes the input ambiguous
            // (metres vs million): "1m x 1000" → 1,000,000,000.
            if let arith = MathEvaluator.dimensionArithmetic(q) {
                let aResult = arith.result
                let aExpr = arith.expression
                merged.append(SearchResult(
                    type: .math,
                    title: "= \(aResult)",
                    subtitle: "\(aExpr)  (m = million)",
                    icon: NSImage(systemSymbolName: "function", accessibilityDescription: nil),
                    actions: [
                        ResultAction(name: "Copy result") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.beamSet(aResult)
                        },
                        ResultAction(name: "Copy query + result") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.beamSet("\(aExpr) = \(aResult)")
                        },
                        ResultAction(name: "Use as input", dismissesPanel: false) {
                            let m = aResult.range(of: #"-?[\d,]+(?:\.\d+)?"#, options: .regularExpression)
                            let numeric = m.map { String(aResult[$0]) } ?? aResult
                            AppDelegate.shared?.searchCoordinator.useAsInput(numeric.replacingOccurrences(of: ",", with: ""))
                        },
                    ]
                ))
            }
        }

        let timezones = timezoneSearcher.search(q)
        let definitions = dictionarySearcher.search(q)
        let apps = appSearcher.search(q)
        let shortcuts = shortcutSearcher.search(q)
        let contacts = contactSearcher.search(q)
        let events = calendarSearcher.searchEvents(q)
        let reminders = calendarSearcher.searchReminders(q)
        let quickAdd = calendarSearcher.quickAddEvent(q)
        let emoji = emojiSearcher.search(q)
        let unicode = emojiSearcher.searchUnicode(q)
        let ai = ollamaSearcher.search(q)

        merged.append(contentsOf: timezones)
        merged.append(contentsOf: definitions)
        merged.append(contentsOf: apps)
        merged.append(contentsOf: shortcuts)
        merged.append(contentsOf: phone)
        merged.append(contentsOf: contacts)
        merged.append(contentsOf: quickAdd)
        merged.append(contentsOf: events)
        merged.append(contentsOf: reminders)
        merged.append(contentsOf: emoji)
        merged.append(contentsOf: unicode)
        merged.append(contentsOf: ai)

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

        placesSearcher.search(q) { [weak self] queryUsed, placeResults in
            guard let self = self, self.query == queryUsed else { return }
            let existing = self.results.filter { $0.type != .place }
            self.results = existing + placeResults
        }
    }

    /// Recognise a query that looks like a phone number and return a callable result.
    /// Accepts `+1 (555) 555-5555`, `555-555-5555`, `5555555555`, etc. — 7–15 digits,
    /// only phone punctuation allowed.
    private static func phoneNumberResult(for query: String) -> SearchResult? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Reject anything with letters — a phone number has none.
        guard trimmed.range(of: "[A-Za-z]", options: .regularExpression) == nil else { return nil }
        let digits = trimmed.filter { $0.isNumber }
        guard (7...15).contains(digits.count) else { return nil }
        // Every char must be a digit or standard phone punctuation.
        let allowed = CharacterSet(charactersIn: "+-()., ").union(.decimalDigits)
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        // Normalise to E.164 — FaceTime only triggers the Continuity cellular call
        // when it receives a properly-formatted international number.
        let dial: String
        if trimmed.hasPrefix("+") {
            dial = "+\(digits)"
        } else if digits.count == 10 {
            dial = "+1\(digits)"           // assume NANP if bare 10-digit
        } else if digits.count == 11, digits.hasPrefix("1") {
            dial = "+\(digits)"
        } else {
            dial = "+\(digits)"
        }
        let display = formatUSPhone(digits) ?? dial

        let call = URL(string: "tel:\(dial)")
        let sms = URL(string: "sms:\(dial)")
        let ft = URL(string: "facetime:\(dial)")

        return SearchResult(
            type: .contact,
            title: display,
            subtitle: "Phone number",
            icon: NSImage(systemSymbolName: "phone.circle.fill", accessibilityDescription: nil),
            actions: [
                ResultAction(name: "Call") {
                    if !ContinuityDialer.dial(dial), let url = call {
                        NSWorkspace.shared.open(url)
                    }
                },
                ResultAction(name: "Message") { sms.map { NSWorkspace.shared.open($0) } },
                ResultAction(name: "FaceTime") { ft.map { NSWorkspace.shared.open($0) } },
            ]
        )
    }

    /// Format 10- or 11-digit numbers as US-style; return nil for other lengths.
    private static func formatUSPhone(_ digits: String) -> String? {
        let d = Array(digits)
        switch d.count {
        case 10:
            return "(\(String(d[0..<3]))) \(String(d[3..<6]))-\(String(d[6..<10]))"
        case 11 where d[0] == "1":
            return "+1 (\(String(d[1..<4]))) \(String(d[4..<7]))-\(String(d[7..<11]))"
        default:
            return nil
        }
    }
}

/// Open a URL via its default handler WITHOUT bringing the handler app to the
/// foreground. For `tel:` URLs on macOS this triggers the compact
/// "Call [number] using iPhone?" prompt (Safari-style) instead of switching to
/// the full FaceTime window.
private func openWithoutActivating(_ url: URL) {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.addsToRecentItems = false
    NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
}
