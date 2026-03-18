import AppKit

class ShortcutSearcher {
    private var shortcuts: [String] = []

    init() {
        loadShortcuts()
    }

    func loadShortcuts() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.launchPath = "/usr/bin/shortcuts"
            task.arguments = ["list"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let names = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                    DispatchQueue.main.async {
                        self?.shortcuts = names
                    }
                }
            } catch {}
        }
    }

    func search(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let lower = trimmed.lowercased()

        return shortcuts
            .filter { $0.lowercased().contains(lower) }
            .sorted { a, b in
                let aStarts = a.lowercased().hasPrefix(lower)
                let bStarts = b.lowercased().hasPrefix(lower)
                if aStarts != bStarts { return aStarts }
                return a.count < b.count
            }
            .prefix(5)
            .map { name in
                let icon = NSImage(systemSymbolName: "arrow.trianglehead.turn.up.right.diamond.fill", accessibilityDescription: nil)
                icon?.size = NSSize(width: 32, height: 32)
                let shortcutName = name
                return SearchResult(
                    type: .shortcut,
                    title: shortcutName,
                    subtitle: "Shortcut",
                    icon: icon,
                    actions: [
                        ResultAction(name: "Run") {
                            let task = Process()
                            task.launchPath = "/usr/bin/shortcuts"
                            task.arguments = ["run", shortcutName]
                            task.standardOutput = Pipe()
                            task.standardError = Pipe()
                            try? task.run()
                        },
                        ResultAction(name: "Open in Shortcuts") {
                            let task = Process()
                            task.launchPath = "/usr/bin/shortcuts"
                            task.arguments = ["view", shortcutName]
                            task.standardOutput = Pipe()
                            task.standardError = Pipe()
                            try? task.run()
                        },
                    ]
                )
            }
    }
}
