import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    var isExpanded: Bool = false
    var selectedDetailIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                if result.type == .emoji {
                    Text(emojiChar)
                        .font(.system(size: 24))
                        .frame(width: 28, height: 28)
                } else if let icon = result.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: result.type.iconName)
                        .font(.system(size: 20))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if result.type != .emoji, !result.subtitle.isEmpty {
                        Group {
                            if let attributed = result.attributedSubtitle {
                                Text(attributed)
                            } else {
                                Text(result.subtitle)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }

                Spacer()

                if result.isExpandable {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }

                Text(result.type.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected && selectedDetailIndex == nil ? Color.accentColor.opacity(0.25) : Color.clear)
                    .padding(.horizontal, 6)
            )

            // Expanded detail items
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(result.details.enumerated()), id: \.offset) { idx, item in
                        DetailItemRow(item: item, isSelected: selectedDetailIndex == idx)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .contentShape(Rectangle())
    }

    private var emojiChar: String {
        guard result.type == .emoji, let first = result.title.first else { return "" }
        return String(first)
    }

    private var displayTitle: String {
        guard result.type == .emoji else { return result.title }
        return String(result.title.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}

struct DetailItemRow: View {
    let item: DetailItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let iconName = item.icon {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            } else {
                Spacer().frame(width: 14)
            }

            if !item.label.isEmpty {
                Text(item.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .leading)
            }

            Text(item.value)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(item.icon == nil ? 3 : 1)

            Spacer()

            if isSelected, let action = item.actions.first {
                Text(action.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 52)
        .padding(.trailing, 14)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, 10)
        )
    }
}
