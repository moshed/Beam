import EventKit
import AppKit

class CalendarSearcher {
    private let store = EKEventStore()
    private var authorized = false

    init() {
        requestAccess()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
            }
        }
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self?.authorized = true
                }
            }
        }
    }

    func searchEvents(_ query: String) -> [SearchResult] {
        guard authorized else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let endDate = calendar.date(byAdding: .month, value: 3, to: now)!

        let predicate = store.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)

        let lower = trimmed.lowercased()
        let matched = events.filter { event in
            event.title?.lowercased().contains(lower) == true ||
            event.location?.lowercased().contains(lower) == true
        }

        return matched.prefix(5).map { event in
            let title = event.title ?? "Untitled Event"
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let subtitle = dateFormatter.string(from: event.startDate)
                + (event.location.map { " - \($0)" } ?? "")

            let icon = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
            icon?.size = NSSize(width: 32, height: 32)

            let eventID = event.eventIdentifier ?? ""
            return SearchResult(
                type: .calendar,
                title: title,
                subtitle: subtitle,
                icon: icon,
                actions: [
                    ResultAction(name: "Open in Calendar") {
                        if let url = URL(string: "ical://ekevent/\(eventID)") {
                            NSWorkspace.shared.open(url)
                        } else {
                            NSWorkspace.shared.open(URL(string: "x-apple-calevent://")!)
                        }
                    },
                ]
            )
        }
    }

    func searchReminders(_ query: String) -> [SearchResult] {
        guard authorized else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        var results: [SearchResult] = []
        let semaphore = DispatchSemaphore(value: 0)

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        store.fetchReminders(matching: predicate) { reminders in
            let lower = trimmed.lowercased()
            let matched = (reminders ?? []).filter { reminder in
                reminder.title?.lowercased().contains(lower) == true
            }

            results = matched.prefix(5).map { reminder in
                let title = reminder.title ?? "Untitled Reminder"
                var subtitle = ""
                if let dueDate = reminder.dueDateComponents?.date {
                    let fmt = DateFormatter()
                    fmt.dateStyle = .medium
                    fmt.timeStyle = .short
                    subtitle = "Due: \(fmt.string(from: dueDate))"
                }
                if let notes = reminder.notes, !notes.isEmpty {
                    subtitle += subtitle.isEmpty ? notes : " - \(notes)"
                }

                let icon = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
                icon?.size = NSSize(width: 32, height: 32)

                let rem = reminder
                return SearchResult(
                    type: .reminder,
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    actions: [
                        ResultAction(name: "Open in Reminders") {
                            NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
                        },
                        ResultAction(name: "Mark complete") { [weak self] in
                            rem.isCompleted = true
                            try? self?.store.save(rem, commit: true)
                        },
                        ResultAction(name: "Postpone due date") { [weak self] in
                            let offset = SettingsManager.shared.reminderDueDateOffsetMinutes
                            let calendar = Calendar.current
                            let baseDate = rem.dueDateComponents?.date ?? Date()
                            if let newDate = calendar.date(byAdding: .minute, value: offset, to: baseDate) {
                                rem.dueDateComponents = calendar.dateComponents(
                                    [.year, .month, .day, .hour, .minute], from: newDate
                                )
                                try? self?.store.save(rem, commit: true)
                            }
                        },
                    ]
                )
            }
            semaphore.signal()
        }

        // Wait briefly for results (don't block UI too long)
        _ = semaphore.wait(timeout: .now() + 0.5)
        return results
    }
}
