import SwiftUI

struct BeamContentView: View {
    @Bindable var coordinator: SearchCoordinator
    weak var panel: BeamPanel?
    @Namespace private var chatTransitionNs

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.isChatMode {
                ChatView(coordinator: coordinator, transitionNs: chatTransitionNs)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.05)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    ))
            } else if coordinator.isHistoryMode {
                // History header — no text field
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)

                    Text("History")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("Start typing to search")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)

                    SearchBarView(
                        text: Binding(
                            get: { coordinator.query },
                            set: { coordinator.queryChanged($0) }
                        ),
                        mathResult: coordinator.mathResultInfo?.result
                    )
                    .frame(height: 28)

                    if let math = coordinator.mathResultInfo {
                        if math.isInfo {
                            Text(math.result)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        } else {
                            Text("= \(math.result)")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .matchedGeometryEffect(id: "chatQueryBubble", in: chatTransitionNs, anchor: .center, isSource: true)
            }

            // History filter bar
            if !coordinator.isChatMode && coordinator.isHistoryMode && !coordinator.results.isEmpty {
                historyFilterBar
            }

            // Results
            if !coordinator.isChatMode && !coordinator.results.isEmpty {
                if !coordinator.isHistoryMode {
                    // Toggle bar (normal mode only)
                    HStack {
                        Divider()
                            .frame(height: 12)

                        Button(action: { coordinator.toggleDisplayMode() }) {
                            HStack(spacing: 4) {
                                Image(systemName: coordinator.displayMode == .grouped ? "rectangle.3.group" : "list.bullet")
                                    .font(.system(size: 10))
                                Text(coordinator.displayMode.rawValue)
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(hintText)
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }

                Divider()
                    .padding(.horizontal, 8)

                if !coordinator.isHistoryMode && coordinator.displayMode == .grouped {
                    GroupedResultsListView(
                        results: coordinator.results,
                        selectedIndex: coordinator.selectedIndex,
                        expandedResultId: coordinator.expandedResultId,
                        expandedDetailIndex: coordinator.expandedDetailIndex,
                        onSelect: { index in
                            coordinator.selectedIndex = index
                            let shouldDismiss = coordinator.executeFocusedAction(slot: 0)
                            if shouldDismiss {
                                AppDelegate.shared?.dismissPanel()
                            }
                        }
                    )
                } else {
                    ResultsListView(
                        results: coordinator.results,
                        selectedIndex: coordinator.selectedIndex,
                        expandedResultId: coordinator.expandedResultId,
                        expandedDetailIndex: coordinator.expandedDetailIndex,
                        onSelect: { index in
                            coordinator.selectedIndex = index
                            if coordinator.executeFocusedAction(slot: 0) {
                                AppDelegate.shared?.dismissPanel()
                            } else {
                                panel?.makeFocused()
                                if let editor = panel?.firstResponder as? NSTextView {
                                    editor.string = coordinator.query
                                    editor.setSelectedRange(NSRange(location: coordinator.query.count, length: 0))
                                }
                            }
                        }
                    )
                }
            }
        }
        .onChange(of: coordinator.results.count) { _, count in
            updatePanelHeight(count)
        }
        .onChange(of: coordinator.mathResultInfo) { _, _ in
            updatePanelHeight(coordinator.results.count)
        }
        .onChange(of: coordinator.isHistoryMode) { _, _ in
            updatePanelHeight(coordinator.results.count)
        }
        .onChange(of: coordinator.historyFilter) { _, _ in
            updatePanelHeight(coordinator.results.count)
        }
        .onChange(of: coordinator.expandedResultId) { _, _ in
            updatePanelHeight(coordinator.results.count)
        }
        .onChange(of: coordinator.isChatMode) { _, _ in
            updatePanelHeight(coordinator.results.count)
        }
        .background(KeyEventHandlerView(coordinator: coordinator, panel: panel))
    }

    private var historyFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                historyFilterPill(label: "All", type: nil)
                ForEach(HistoryManager.shared.availableTypes, id: \.rawValue) { type in
                    historyFilterPill(label: type.rawValue, type: type, icon: type.iconName)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }

    private func historyFilterPill(label: String, type: SearchResultType?, icon: String? = nil) -> some View {
        let isSelected = coordinator.historyFilter == type
        return Button(action: { coordinator.setHistoryFilter(type) }) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var hintText: String {
        let actions = coordinator.focusedActions
        guard !actions.isEmpty else { return "" }

        let idx = coordinator.selectedIndex
        guard idx >= 0, idx < coordinator.results.count else { return "" }
        let result = coordinator.results[idx]

        // Emoji/unicode grid: show name + action hints
        if coordinator.isSelectedEmoji {
            let afterChar = String(result.title.dropFirst()).trimmingCharacters(in: .whitespaces)
            let name = afterChar.hasPrefix("U+") && !result.subtitle.isEmpty ? result.subtitle : afterChar
            return "\(name)   ↵ Copy   ⇧↵ Copy name"
        }

        // For detail items, use actions directly (no per-type customization)
        if coordinator.expandedDetailIndex != nil {
            let keys = ["↵", "⇧↵", "⌥↵"]
            return (0..<min(3, actions.count)).map { "\(keys[$0]) \(actions[$0].name)" }.joined(separator: "   ")
        }
        let settings = SettingsManager.shared
        let keys = ["↵", "⇧↵", "⌥↵"]
        var parts: [String] = []
        for slot in 0..<min(3, actions.count) {
            let ai = settings.actionIndex(for: result.type, slot: slot)
            let clamped = min(ai, actions.count - 1)
            parts.append("\(keys[slot]) \(actions[max(0, clamped)].name)")
        }
        return parts.joined(separator: "   ")
    }

    private func updatePanelHeight(_ count: Int) {
        if coordinator.isChatMode {
            panel?.updateHeight(520)
            return
        }
        let searchBarHeight: CGFloat = 56
        let hasResults = count > 0
        let rowHeight: CGFloat = 44
        let detailRowHeight: CGFloat = 22

        // History filter bar height
        let historyFilterHeight: CGFloat = (coordinator.isHistoryMode && hasResults) ? 30 : 0

        let toggleBarHeight: CGFloat = (!coordinator.isHistoryMode && hasResults) ? 24.0 : 0
        let dividerPadding: CGFloat = hasResults ? 13.0 : 0

        // Count non-grid rows and grid rows separately
        let gridTypes: Set<SearchResultType> = [.emoji, .unicode]
        let emojiCount = coordinator.results.filter { gridTypes.contains($0.type) }.count
        let nonEmojiCount = coordinator.results.filter { !gridTypes.contains($0.type) }.count
        let nonEmojiRows = CGFloat(min(nonEmojiCount, 15))

        var emojiGridHeight: CGFloat = 0
        if emojiCount > 0 {
            let cols = SearchCoordinator.emojiGridColumns
            let gridRows = ceil(CGFloat(emojiCount) / CGFloat(cols))
            emojiGridHeight = min(gridRows * 60 + 8, 320)
        }

        let rows = nonEmojiRows

        // In grouped mode (non-history), count section headers
        var sectionHeaderHeight: CGFloat = 0
        if !coordinator.isHistoryMode && coordinator.displayMode == .grouped && count > 0 {
            let types = Set(coordinator.results.map { $0.type })
            sectionHeaderHeight = CGFloat(types.count) * 26
        }

        // Expanded detail items height
        var expandedHeight: CGFloat = 0
        if let expandedId = coordinator.expandedResultId,
           let result = coordinator.results.first(where: { $0.id == expandedId }),
           !result.details.isEmpty {
            expandedHeight = CGFloat(result.details.count) * detailRowHeight + 4
        }

        let listPadding: CGFloat = hasResults ? 8.0 : 0
        let totalHeight = searchBarHeight + historyFilterHeight + toggleBarHeight + dividerPadding + rows * rowHeight + sectionHeaderHeight + expandedHeight + emojiGridHeight + listPadding
        panel?.updateHeight(totalHeight)
    }
}
