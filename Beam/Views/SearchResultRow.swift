import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            if result.type == .emoji {
                // Use the emoji character itself as the icon
                Text(emojiChar)
                    .font(.system(size: 24))
                    .frame(width: 28, height: 28)
            } else if let icon = result.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: result.type.iconName)
                    .font(.system(size: 20))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }

            // Title / subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if result.type != .emoji, !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

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
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
    }

    /// For emoji: extract the emoji character from "🔥  Fire Name"
    private var emojiChar: String {
        guard result.type == .emoji else { return "" }
        let title = result.title
        // First character(s) are the emoji
        if let first = title.first, first.isEmoji {
            return String(first)
        }
        return ""
    }

    /// For emoji: show just the name without the emoji prefix
    private var displayTitle: String {
        guard result.type == .emoji else { return result.title }
        let title = result.title
        // Strip emoji + spaces from front
        if let first = title.first, first.isEmoji {
            return String(title.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return title
    }
}

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && scalar.value > 0x238C
    }
}
