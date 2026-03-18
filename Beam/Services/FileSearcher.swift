import AppKit

class FileSearcher {
    private var query: NSMetadataQuery?
    private var onResults: (([SearchResult]) -> Void)?

    init() {}

    func search(_ text: String, onResults: @escaping ([SearchResult]) -> Void) {
        self.onResults = onResults
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            onResults([])
            return
        }

        let mdQuery = NSMetadataQuery()
        mdQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        mdQuery.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]

        // Search by display name
        mdQuery.predicate = NSPredicate(
            format: "kMDItemDisplayName contains[cd] %@ && kMDItemContentType != 'com.apple.application-bundle'",
            trimmed
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinish(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: mdQuery
        )

        self.query = mdQuery
        mdQuery.start()
    }

    func stop() {
        query?.stop()
        if let q = query {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        }
        query = nil
    }

    @objc private func queryDidFinish(_ notification: Notification) {
        guard let mdQuery = notification.object as? NSMetadataQuery else { return }
        mdQuery.disableUpdates()

        var results: [SearchResult] = []
        let count = min(mdQuery.resultCount, 10)

        for i in 0..<count {
            guard let item = mdQuery.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
            else { continue }

            // Skip system/library paths
            if path.contains("/Library/") && !path.contains(NSHomeDirectory()) { continue }

            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 32, height: 32)

            let displayPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")

            let filePath = path
            results.append(SearchResult(
                type: .file,
                title: name,
                subtitle: displayPath,
                icon: icon,
                actions: [
                    ResultAction(name: "Open") { NSWorkspace.shared.open(URL(fileURLWithPath: filePath)) },
                    ResultAction(name: "Reveal in Finder") {
                        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                    },
                    ResultAction(name: "Open With...") {
                        // Reveal and let user right-click
                        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                    },
                ]
            ))
        }

        mdQuery.enableUpdates()
        DispatchQueue.main.async { [weak self] in
            self?.onResults?(results)
        }
    }
}
