import SwiftUI

struct EmojiGridView: View {
    let results: [SearchResult]
    let selectedIndex: Int
    var onSelect: (Int) -> Void

    private let columns = 8

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 4), count: columns), spacing: 4) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        EmojiCell(
                            emoji: emojiChar(from: result),
                            name: emojiName(from: result),
                            isSelected: index == selectedIndex
                        )
                        .id(result.id)
                        .onTapGesture {
                            onSelect(index)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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

    private func emojiChar(from result: SearchResult) -> String {
        guard let first = result.title.first else { return "" }
        return String(first)
    }

    private func emojiName(from result: SearchResult) -> String {
        String(result.title.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}

struct EmojiCell: View {
    let emoji: String
    let name: String
    let isSelected: Bool

    var body: some View {
        Text(emoji)
            .font(.system(size: 28))
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
            )
            .help(name)
    }
}
