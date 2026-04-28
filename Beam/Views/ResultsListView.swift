import SwiftUI

struct ResultsListView: View {
    let results: [SearchResult]
    let selectedIndex: Int
    var expandedResultId: UUID? = nil
    var expandedDetailIndex: Int? = nil
    var onSelect: (Int) -> Void

    private var segments: [ResultSegment] {
        buildSegments(from: results)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(segments) { segment in
                        if segment.isEmoji {
                            InlineEmojiGrid(
                                results: results,
                                indices: segment.indices,
                                selectedIndex: selectedIndex,
                                onSelect: onSelect
                            )
                        } else {
                            ForEach(segment.indices, id: \.self) { index in
                                let result = results[index]
                                SearchResultRow(
                                    result: result,
                                    isSelected: index == selectedIndex,
                                    isExpanded: result.id == expandedResultId,
                                    selectedDetailIndex: (index == selectedIndex && result.id == expandedResultId) ? expandedDetailIndex : nil
                                )
                                .id(result.id)
                                .onTapGesture { onSelect(index) }
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

                        if section.type == .emoji || section.type == .unicode {
                            InlineEmojiGrid(
                                results: results,
                                indices: section.items.map { $0.index },
                                selectedIndex: selectedIndex,
                                onSelect: onSelect
                            )
                        } else {
                            ForEach(section.items, id: \.result.id) { item in
                                SearchResultRow(
                                    result: item.result,
                                    isSelected: item.index == selectedIndex,
                                    isExpanded: item.result.id == expandedResultId,
                                    selectedDetailIndex: (item.index == selectedIndex && item.result.id == expandedResultId) ? expandedDetailIndex : nil
                                )
                                .id(item.result.id)
                                .onTapGesture { onSelect(item.index) }
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

// MARK: - Inline Emoji Grid

struct InlineEmojiGrid: View {
    let results: [SearchResult]
    let indices: [Int]
    let selectedIndex: Int
    var onSelect: (Int) -> Void

    private let columns = SearchCoordinator.emojiGridColumns

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 4), count: columns), spacing: 4) {
            ForEach(indices, id: \.self) { index in
                let result = results[index]
                EmojiCell(
                    emoji: emojiChar(from: result),
                    name: emojiName(from: result),
                    isSelected: index == selectedIndex
                )
                .id(result.id)
                .onTapGesture { onSelect(index) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func emojiChar(from result: SearchResult) -> String {
        guard let first = result.title.first else { return "" }
        return String(first)
    }

    private func emojiName(from result: SearchResult) -> String {
        // For unicode results (title: "→  U+2192"), the name is in subtitle
        let afterEmoji = String(result.title.dropFirst()).trimmingCharacters(in: .whitespaces)
        if afterEmoji.hasPrefix("U+") && !result.subtitle.isEmpty {
            return result.subtitle
        }
        return afterEmoji
    }
}

// MARK: - Segment Helpers

struct ResultSegment: Identifiable {
    let id: String
    let isEmoji: Bool
    let indices: [Int]
}

private let gridTypes: Set<SearchResultType> = [.emoji, .unicode]

private func buildSegments(from results: [SearchResult]) -> [ResultSegment] {
    var segments: [ResultSegment] = []
    var currentEmoji: [Int] = []
    var currentOther: [Int] = []

    for (index, result) in results.enumerated() {
        if gridTypes.contains(result.type) {
            if !currentOther.isEmpty {
                segments.append(ResultSegment(id: "other-\(currentOther[0])", isEmoji: false, indices: currentOther))
                currentOther = []
            }
            currentEmoji.append(index)
        } else {
            if !currentEmoji.isEmpty {
                segments.append(ResultSegment(id: "emoji-\(currentEmoji[0])", isEmoji: true, indices: currentEmoji))
                currentEmoji = []
            }
            currentOther.append(index)
        }
    }

    if !currentEmoji.isEmpty {
        segments.append(ResultSegment(id: "emoji-\(currentEmoji[0])", isEmoji: true, indices: currentEmoji))
    }
    if !currentOther.isEmpty {
        segments.append(ResultSegment(id: "other-\(currentOther[0])", isEmoji: false, indices: currentOther))
    }

    return segments
}
