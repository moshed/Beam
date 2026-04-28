import AppKit
import Foundation
import SwiftUI

class OllamaSearcher {
    static let shared = OllamaSearcher()

    private let baseURL = URL(string: "http://localhost:11434")!
    private var defaultModel: String = "llama3.2"
    private var streamingTask: URLSessionDataTask?
    private static let ollamaPaths = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama",
    ]

    init() {
        Task { await detectModel() }
    }

    /// Probes /api/tags. If the server is unreachable, spawns `ollama serve` and waits for it.
    /// Returns true once the server responds.
    private func ensureServerRunning() async -> Bool {
        if await isServerUp() { return true }
        guard let path = Self.ollamaPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return false
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["serve"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        // Poll for up to 5s for the server to come up.
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if await isServerUp() { return true }
        }
        return false
    }

    private func isServerUp() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 1.0
        return ((try? await URLSession.shared.data(for: req)) != nil)
    }

    private func detectModel() async {
        guard await ensureServerRunning() else { return }
        let url = baseURL.appendingPathComponent("api/tags")
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]],
              let first = models.first?["name"] as? String else { return }
        defaultModel = first
    }

    var currentModel: String {
        let pref = SettingsManager.shared.ollamaModel
        return pref.isEmpty ? defaultModel : pref
    }

    /// Fetches the list of installed models. Auto-starts the server if needed.
    func listModels() async -> [String] {
        guard await ensureServerRunning() else { return [] }
        let url = baseURL.appendingPathComponent("api/tags")
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    func search(_ query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return [] }
        return [SearchResult(
            type: .ai,
            title: "Ask AI",
            subtitle: q,
            icon: nil,
            actions: [
                ResultAction(name: "Ask") {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        AppDelegate.shared?.searchCoordinator.enterChatMode(prompt: q)
                    }
                },
                ResultAction(name: "Copy answer") { [weak self] in
                    self?.askAndCopy(q)
                },
            ]
        )]
    }

    /// Multi-turn chat using /api/chat. Auto-starts the server if needed.
    func chat(messages: [(role: String, content: String)], onToken: @escaping (String) -> Void, completion: @escaping () -> Void) {
        Task {
            guard await ensureServerRunning() else {
                await MainActor.run {
                    onToken("[Could not start Ollama. Install it from ollama.com.]")
                    completion()
                }
                return
            }
            await MainActor.run { self.streamChat(messages: messages, onToken: onToken, completion: completion) }
        }
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func streamChat(messages: [(role: String, content: String)], onToken: @escaping (String) -> Void, completion: @escaping () -> Void) {
        let url = baseURL.appendingPathComponent("api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let msgArray = messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": currentModel, "messages": msgArray, "stream": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        streamingTask?.cancel()

        let delegate = ChatStreamDelegate(onToken: onToken, completion: completion)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: req)
        streamingTask = task
        task.resume()
    }

    private class ChatStreamDelegate: NSObject, URLSessionDataDelegate {
        let onToken: (String) -> Void
        let completion: () -> Void
        var buffer = Data()
        var done = false

        init(onToken: @escaping (String) -> Void, completion: @escaping () -> Void) {
            self.onToken = onToken
            self.completion = completion
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                guard !line.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let msg = json["message"] as? [String: Any], let content = msg["content"] as? String, !content.isEmpty {
                    DispatchQueue.main.async { self.onToken(content) }
                }
                if let isDone = json["done"] as? Bool, isDone, !done {
                    done = true
                    DispatchQueue.main.async { self.completion() }
                }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard !done else { return }
            done = true
            if let error = error, (error as NSError).code != NSURLErrorCancelled {
                DispatchQueue.main.async {
                    self.onToken("\n\n[Error: \(error.localizedDescription)]")
                }
            }
            DispatchQueue.main.async { self.completion() }
        }
    }

    func askAndCopy(_ prompt: String) {
        Task {
            let up = await ensureServerRunning()
            guard up else { return }
            var collected = ""
            await MainActor.run {
                self.stream(prompt: prompt) { token in
                    collected += token
                } completion: {
                    DispatchQueue.main.async {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(collected, forType: .string)
                    }
                }
            }
        }
    }

    private func stream(prompt: String, onToken: @escaping (String) -> Void, completion: @escaping () -> Void) {
        let url = baseURL.appendingPathComponent("api/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": currentModel, "prompt": prompt, "stream": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        streamingTask?.cancel()

        let delegate = StreamDelegate(onToken: onToken, completion: completion)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: req)
        streamingTask = task
        task.resume()
    }

    private class StreamDelegate: NSObject, URLSessionDataDelegate {
        let onToken: (String) -> Void
        let completion: () -> Void
        var buffer = Data()

        init(onToken: @escaping (String) -> Void, completion: @escaping () -> Void) {
            self.onToken = onToken
            self.completion = completion
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                guard !line.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let response = json["response"] as? String, !response.isEmpty {
                    DispatchQueue.main.async { self.onToken(response) }
                }
                if let done = json["done"] as? Bool, done {
                    DispatchQueue.main.async { self.completion() }
                }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                DispatchQueue.main.async {
                    self.onToken("\n\n[Error: \(error.localizedDescription)]")
                    self.completion()
                }
            }
        }
    }
}

