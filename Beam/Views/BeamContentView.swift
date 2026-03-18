import SwiftUI

struct BeamContentView: View {
    @Bindable var coordinator: SearchCoordinator
    weak var panel: BeamPanel?

    var body: some View {
        VStack(spacing: 0) {
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
                    Text("= \(math.result)")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Results
            if !coordinator.results.isEmpty {
                // Toggle bar
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

                Divider()
                    .padding(.horizontal, 8)

                if coordinator.displayMode == .grouped {
                    GroupedResultsListView(
                        results: coordinator.results,
                        selectedIndex: coordinator.selectedIndex,
                        onSelect: { index in
                            coordinator.selectedIndex = index
                            coordinator.executeSelected()
                            AppDelegate.shared?.dismissPanel()
                        }
                    )
                } else {
                    ResultsListView(
                        results: coordinator.results,
                        selectedIndex: coordinator.selectedIndex,
                        onSelect: { index in
                            coordinator.selectedIndex = index
                            coordinator.executeSelected()
                            AppDelegate.shared?.dismissPanel()
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
        .background(KeyEventHandlerView(coordinator: coordinator, panel: panel))
    }

    private var hintText: String {
        let idx = coordinator.selectedIndex
        guard idx >= 0, idx < coordinator.results.count else { return "" }
        let result = coordinator.results[idx]
        let actions = result.actions
        guard !actions.isEmpty else { return "" }
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
        let searchBarHeight: CGFloat = 56
        let rowHeight: CGFloat = 44
        let toggleBarHeight: CGFloat = count > 0 ? 24.0 : 0
        let dividerPadding: CGFloat = count > 0 ? 13.0 : 0
        let rows = CGFloat(min(count, 15))

        // In grouped mode, count section headers
        var sectionHeaderHeight: CGFloat = 0
        if coordinator.displayMode == .grouped && count > 0 {
            let types = Set(coordinator.results.map { $0.type })
            sectionHeaderHeight = CGFloat(types.count) * 26
        }

        let listPadding: CGFloat = count > 0 ? 8.0 : 0
        let totalHeight = searchBarHeight + toggleBarHeight + dividerPadding + rows * rowHeight + sectionHeaderHeight + listPadding
        panel?.updateHeight(totalHeight)
    }
}
