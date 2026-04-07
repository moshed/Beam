import SwiftUI

struct ResultsListView: View {
    let results: [SearchResult]
    let selectedIndex: Int
    var expandedResultId: UUID? = nil
    var expandedDetailIndex: Int? = nil
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        SearchResultRow(
                            result: result,
                            isSelected: index == selectedIndex,
                            isExpanded: result.id == expandedResultId,
                            selectedDetailIndex: (index == selectedIndex && result.id == expandedResultId) ? expandedDetailIndex : nil
                        )
                        .id(result.id)
                        .onTapGesture {
                            onSelect(index)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 0, newIndex < results.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(results[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }
}

struct GroupedResultsListView: View {
    let results: [SearchResult]
    let selectedIndex: Int
    var expandedResultId: UUID? = nil
    var expandedDetailIndex: Int? = nil
    var onSelect: (Int) -> Void

    private var sections: [(type: SearchResultType, items: [(index: Int, result: SearchResult)])] {
        var grouped: [SearchResultType: [(index: Int, result: SearchResult)]] = [:]
        for (index, result) in results.enumerated() {
            grouped[result.type, default: []].append((index: index, result: result))
        }
        return grouped
            .sorted { $0.key.sectionOrder < $1.key.sectionOrder }
            .map { (type: $0.key, items: $0.value) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections, id: \.type.rawValue) { section in
                        HStack {
                            Image(systemName: section.type.iconName)
                                .font(.system(size: 10))
                            Text(section.type.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                        ForEach(section.items, id: \.result.id) { item in
                            SearchResultRow(
                                result: item.result,
                                isSelected: item.index == selectedIndex,
                                isExpanded: item.result.id == expandedResultId,
                                selectedDetailIndex: (item.index == selectedIndex && item.result.id == expandedResultId) ? expandedDetailIndex : nil
                            )
                            .id(item.result.id)
                            .onTapGesture {
                                onSelect(item.index)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 0, newIndex < results.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(results[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }
}
