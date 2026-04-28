import AppKit

class AppSearcher {
    struct AppInfo {
        let name: String
        let url: URL
        let icon: NSImage
    }

    private var apps: [AppInfo] = []

    init() {
        loadApps()
    }

    func loadApps() {
        var results: [AppInfo] = []
        let fm = FileManager.default
        let dirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]

        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(item)
                let url = URL(fileURLWithPath: path)
                let name = (item as NSString).deletingPathExtension
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 32, height: 32)
                results.append(AppInfo(name: name, url: url, icon: icon))
            }
        }

        // Also scan inside /System/Applications subdirs
        if let sysApps = try? fm.contentsOfDirectory(atPath: "/System/Applications") {
            for item in sysApps {
                let subPath = "/System/Applications/\(item)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue, !item.hasSuffix(".app") {
                    if let subItems = try? fm.contentsOfDirectory(atPath: subPath) {
                        for sub in subItems where sub.hasSuffix(".app") {
                            let path = (subPath as NSString).appendingPathComponent(sub)
                            let url = URL(fileURLWithPath: path)
                            let name = (sub as NSString).deletingPathExtension
                            let icon = NSWorkspace.shared.icon(forFile: path)
                            icon.size = NSSize(width: 32, height: 32)
                            results.append(AppInfo(name: name, url: url, icon: icon))
                        }
                    }
                }
            }
        }

        apps = results
    }

    func search(_ query: String) -> [SearchResult] {
        let lower = query.lowercased()
        return apps
            .filter { $0.name.lowercased().contains(lower) }
            .sorted { a, b in
                let aStarts = a.name.lowercased().hasPrefix(lower)
                let bStarts = b.name.lowercased().hasPrefix(lower)
                if aStarts != bStarts { return aStarts }
                return a.name.count < b.name.count
            }
            .prefix(5)
            .map { app in
                let appUrl = app.url
                return SearchResult(
                    type: .app,
                    title: app.name,
                    subtitle: appUrl.path,
                    icon: app.icon,
                    actions: [
                        ResultAction(name: "Open") {
                            AppDelegate.shared?.dismissPanel(skipReactivation: true)
                            NSWorkspace.shared.open(appUrl)
                        },
                        ResultAction(name: "Reveal in Finder") {
                            AppDelegate.shared?.dismissPanel(skipReactivation: true)
                            NSWorkspace.shared.selectFile(appUrl.path, inFileViewerRootedAtPath: "")
                        },
                    ]
                )
            }
    }
}
