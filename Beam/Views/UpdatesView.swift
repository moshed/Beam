import SwiftUI

/// Shared selection so code can switch the Settings window to a specific tab.
final class SettingsState: ObservableObject {
    static let shared = SettingsState()
    @Published var selectedTab: Int = 0
}

/// Fetches and parses the Sparkle appcast for display in the Updates tab.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Entry: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let notes: String
    }

    @Published var entries: [Entry] = []
    @Published var isChecking = false
    @Published var lastError: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var latestVersion: String? { entries.first?.version }

    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return latest.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    private var feedURL: URL? {
        (Bundle.main.infoDictionary?["SUFeedURL"] as? String).flatMap(URL.init(string:))
    }

    func check(completion: (() -> Void)? = nil) {
        guard let url = feedURL else { completion?(); return }
        DispatchQueue.main.async { self.isChecking = true; self.lastError = nil }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            let parsed = data.map { AppcastParser.parse($0) } ?? []
            DispatchQueue.main.async {
                self.isChecking = false
                if let error = error { self.lastError = error.localizedDescription }
                if !parsed.isEmpty { self.entries = parsed }
                completion?()
            }
        }.resume()
    }
}

/// Minimal XMLParser for the Sparkle appcast RSS.
enum AppcastParser {
    final class Delegate: NSObject, XMLParserDelegate {
        var entries: [UpdateChecker.Entry] = []
        private var element = ""
        private var version = "", date = "", notes = ""
        private var inItem = false

        func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            element = el
            if el == "item" { inItem = true; version = ""; date = ""; notes = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inItem else { return }
            switch element {
            case "sparkle:shortVersionString": version += string
            case "pubDate": date += string
            case "description": notes += string
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard inItem, element == "description", let s = String(data: CDATABlock, encoding: .utf8) else { return }
            notes += s
        }
        func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
            if el == "item" {
                inItem = false
                entries.append(.init(
                    version: version.trimmingCharacters(in: .whitespacesAndNewlines),
                    date: shortDate(date.trimmingCharacters(in: .whitespacesAndNewlines)),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            element = ""
        }

        private func shortDate(_ rfc: String) -> String {
            let inFmt = DateFormatter()
            inFmt.locale = Locale(identifier: "en_US_POSIX")
            inFmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            guard let d = inFmt.date(from: rfc) else { return rfc }
            let out = DateFormatter()
            out.dateStyle = .medium
            return out.string(from: d)
        }
    }

    static func parse(_ data: Data) -> [UpdateChecker.Entry] {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.parse()
        // Newest first (appcast lists newest at top already, but sort defensively).
        return delegate.entries.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}

struct UpdatesSettingsTab: View {
    @ObservedObject var checker = UpdateChecker.shared
    @State private var autoCheck = AppDelegate.shared?.updaterController.updater.automaticallyChecksForUpdates ?? true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Toggle("Automatically check for updates", isOn: $autoCheck)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: autoCheck) { _, newValue in
                    AppDelegate.shared?.updaterController.updater.automaticallyChecksForUpdates = newValue
                }
            Text("Updates are never installed without your confirmation.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            Divider()
            if checker.entries.isEmpty {
                VStack(spacing: 8) {
                    if checker.isChecking { ProgressView() }
                    Text(checker.lastError ?? "No release information yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(checker.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Version \(entry.version)")
                                        .font(.system(size: 13, weight: .semibold))
                                    if entry.version == checker.currentVersion {
                                        Text("current")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.15), in: Capsule())
                                    }
                                    Spacer()
                                    Text(entry.date)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                                if !entry.notes.isEmpty {
                                    Text(entry.notes)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { checker.check() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: checker.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(checker.updateAvailable ? Color.accentColor : .green)
            VStack(alignment: .leading, spacing: 1) {
                if checker.updateAvailable, let latest = checker.latestVersion {
                    Text("Update available — \(latest)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("You have \(checker.currentVersion)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("You're up to date")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Version \(checker.currentVersion)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if checker.updateAvailable {
                Button("Download & Install") {
                    AppDelegate.shared?.updaterController.checkForUpdates(nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: { checker.check() }) {
                    if checker.isChecking { ProgressView().controlSize(.small) }
                    else { Text("Check Again") }
                }
            }
        }
        .padding(16)
    }
}
