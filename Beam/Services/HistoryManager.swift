import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: UUID
    var query: String
    var title: String
    var subtitle: String
    var typeName: String
    var timestamp: Date

    var type: SearchResultType? {
        SearchResultType(rawValue: typeName)
    }
}

class HistoryManager {
    static let shared = HistoryManager()

    private(set) var entries: [HistoryEntry] = []
    private let maxEntries = 500
    private let storageKey = "beamHistory"

    private init() {
        load()
    }

    /// Insert a new entry or update an existing one by ID. Returns the entry's ID.
    @discardableResult
    func upsert(id: UUID?, query: String, title: String, subtitle: String, typeName: String) -> UUID {
        if let id = id, let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].query = query
            entries[index].title = title
            entries[index].subtitle = subtitle
            entries[index].typeName = typeName
            entries[index].timestamp = Date()
            // Move to top if not already
            if index != 0 {
                let entry = entries.remove(at: index)
                entries.insert(entry, at: 0)
            }
            save()
            return id
        }

        // Skip if identical to the most recent entry
        if let last = entries.first, last.query == query, last.title == title, last.typeName == typeName {
            return last.id
        }

        let entry = HistoryEntry(
            id: id ?? UUID(),
            query: query,
            title: title,
            subtitle: subtitle,
            typeName: typeName,
            timestamp: Date()
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        return entry.id
    }

    func filteredEntries(type: SearchResultType? = nil) -> [HistoryEntry] {
        var result = entries
        if let type = type {
            result = result.filter { $0.typeName == type.rawValue }
        }
        return result
    }

    /// All distinct types that have history entries
    var availableTypes: [SearchResultType] {
        let typeNames = Set(entries.compactMap { $0.typeName })
        return SearchResultType.allCases.filter { typeNames.contains($0.rawValue) }
    }

    func clearHistory() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }
}
