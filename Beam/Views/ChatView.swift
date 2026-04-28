import SwiftUI

struct ChatView: View {
    @Bindable var coordinator: SearchCoordinator
    let transitionNs: Namespace.ID
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(Array(coordinator.chatMessages.enumerated()), id: \.element.id) { idx, msg in
                            ChatBubble(message: msg, isStreaming: coordinator.chatStreaming && msg.id == coordinator.chatMessages.last?.id && msg.role == "assistant")
                                .id(msg.id)
                                .matchedGeometryEffect(
                                    id: idx == 0 && msg.role == "user" ? "chatQueryBubble" : "msg-\(msg.id)",
                                    in: transitionNs,
                                    isSource: !(idx == 0 && msg.role == "user")
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: coordinator.chatMessages.last?.content) { _, _ in
                    if let lastId = coordinator.chatMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                TextField("Reply…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { send() }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { inputFocused = true }
    }

    private var canSend: Bool {
        !coordinator.chatStreaming && !input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let text = input
        input = ""
        coordinator.sendChatMessage(text)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("Ask AI")
                .font(.system(size: 13, weight: .semibold))
            Text(coordinator.chatModel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())

            Spacer()

            if coordinator.chatStreaming {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Button(action: { coordinator.exitChatMode() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Exit chat (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ChatBubble: View {
    let message: SearchCoordinator.ChatMessage
    let isStreaming: Bool

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 40)
                bubble
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            } else {
                bubble
                    .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.primary)
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let isPlaceholder = message.content.isEmpty && isStreaming
        let body: AnyView = {
            if isPlaceholder {
                return AnyView(Text("…").font(.system(size: 13)))
            }
            if message.role == "assistant" {
                return AnyView(MarkdownText(markdown: message.content))
            }
            return AnyView(Text(message.content).font(.system(size: 13)))
        }()
        body
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MarkdownText: View {
    let markdown: String

    var body: some View {
        let lines = markdown.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
        .font(.system(size: 13))
    }

    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 4)
        } else if trimmed.hasPrefix("### ") {
            Text(parseInline(String(trimmed.dropFirst(4))))
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 2)
        } else if trimmed.hasPrefix("## ") {
            Text(parseInline(String(trimmed.dropFirst(3))))
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 3)
        } else if trimmed.hasPrefix("# ") {
            Text(parseInline(String(trimmed.dropFirst(2))))
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(parseInline(String(trimmed.dropFirst(2))))
            }
        } else if let r = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            HStack(alignment: .top, spacing: 6) {
                Text(String(trimmed[trimmed.startIndex..<r.upperBound]).trimmingCharacters(in: .whitespaces))
                    .foregroundStyle(.secondary)
                Text(parseInline(String(trimmed[r.upperBound...])))
            }
        } else if trimmed.hasPrefix("> ") {
            Text(parseInline(String(trimmed.dropFirst(2))))
                .italic()
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        } else {
            Text(parseInline(line))
        }
    }

    private func parseInline(_ s: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(s)
    }
}
