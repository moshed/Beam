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

    /// EKCalendars the user can save events to. Exposed so Settings can render
    /// them in the default-calendar picker.
    func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    /// Parse the query as a natural-language event ("dinner with Sarah 8pm
    /// Friday at Balthazar") and, if a date is detected, offer to create it.
    /// Uses NSDataDetector for the date plus a keyword sweep for venues so
    /// multi-part locations ("JFK International Airport, Terminal 4, …")
    /// land in the location field rather than the title.
    func quickAddEvent(_ query: String) -> [SearchResult] {
        guard authorized else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5 else { return [] }

        let types: NSTextCheckingResult.CheckingType = [.date, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = detector.matches(in: trimmed, options: [], range: full)

        // Need at least a date; without one this is just noise.
        guard let dateMatch = matches.first(where: { $0.resultType == .date }),
              let startDate = dateMatch.date else { return [] }

        // Split the query into pre-date and post-date.
        let dateStart = dateMatch.range.location
        let dateEnd = dateStart + dateMatch.range.length
        let preRange = NSRange(location: 0, length: dateStart)
        let pre = ns.substring(with: preRange).trimmingCharacters(in: .whitespacesAndNewlines)
        let post: String
        if dateEnd < ns.length {
            post = ns.substring(with: NSRange(location: dateEnd, length: ns.length - dateEnd))
                     .trimmingCharacters(in: .whitespacesAndNewlines)
        } else { post = "" }

        // 1) Extract location by locating the earliest venue keyword — expand
        //    backward through capitalized proper-noun words and numeric
        //    ordinals so "JFK International Airport" or "5th Avenue" are
        //    captured whole.
        //
        //    Prefer the post-date half because that's where an explicit "at
        //    <venue>" almost always lives; the pre-date half only wins when
        //    the post-date half has no venue keyword. This avoids false
        //    positives from title words that happen to be venue keywords —
        //    e.g. "school pickup 3pm at Main St Elementary" should keep the
        //    title "school pickup" and take the location from the post half.
        var locationText: String?
        var titleBase: String = pre
        let (locFromPost, titleFromPost) = Self.splitLocation(post)
        if let l = locFromPost {
            locationText = l
            // Any pre-date content is the title; the post-date remainder
            // (usually just "at") is appended if non-empty.
            if !titleFromPost.isEmpty && titleFromPost.lowercased() != "at" {
                titleBase = titleBase.isEmpty ? titleFromPost : "\(titleBase) \(titleFromPost)"
            }
        } else {
            let (locFromPre, titleFromPre) = Self.splitLocation(pre)
            locationText = locFromPre
            titleBase = titleFromPre
        }
        // 2) If the keyword sweep didn't find anything, fall back to
        //    NSDataDetector's own .address match.
        if locationText == nil,
           let addr = matches.first(where: { $0.resultType == .address }) {
            locationText = ns.substring(with: addr.range).trimmingCharacters(in: .whitespaces)
            titleBase = titleBase
                .replacingOccurrences(of: locationText ?? "", with: "")
                .trimmingCharacters(in: .whitespaces)
        }

        // 3) Clean the title of leftover glue words.
        var titleStr = titleBase
        titleStr = titleStr.replacingOccurrences(
            of: #"\s+(at|on|in|from)\s*$"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        titleStr = titleStr.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        titleStr = titleStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if titleStr.isEmpty { titleStr = "New Event" }

        // If NSDataDetector didn't include a time (all-day event), default
        // duration to 24h — otherwise 1h.
        let comps = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        let hasTime = !(comps.hour == 0 && comps.minute == 0)
        let endDate: Date
        if dateMatch.duration > 0 {
            endDate = startDate.addingTimeInterval(dateMatch.duration)
        } else {
            endDate = startDate.addingTimeInterval(hasTime ? 3600 : 86_400)
        }

        // Subtitle preview
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .medium
        df.timeStyle = hasTime ? .short : .none
        var subtitle = df.string(from: startDate)
        if let loc = locationText { subtitle += "\n\(loc)" }

        let icon = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: nil)
        icon?.size = NSSize(width: 32, height: 32)

        // Capture-by-value for the closures.
        let capturedStore = store
        let capturedTitle = titleStr
        let capturedStart = startDate
        let capturedEnd = endDate
        let capturedLoc = locationText
        let capturedHasTime = hasTime

        func makeEvent(in calendar: EKCalendar?) -> EKEvent {
            let ev = EKEvent(eventStore: capturedStore)
            ev.title = capturedTitle
            ev.startDate = capturedStart
            ev.endDate = capturedEnd
            ev.location = capturedLoc
            ev.isAllDay = !capturedHasTime
            ev.calendar = calendar ?? capturedStore.defaultCalendarForNewEvents
            return ev
        }

        func save(in calendar: EKCalendar?, openAfter: Bool = false) {
            let ev = makeEvent(in: calendar)
            do {
                try capturedStore.save(ev, span: .thisEvent, commit: true)
                if openAfter,
                   let id = ev.eventIdentifier,
                   let url = URL(string: "ical://ekevent/\(id)") {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                NSLog("[Beam] quick-add save failed: %@", "\(error)")
            }
        }

        // Resolve the "Enter" calendar from user setting (fall back to default).
        let defaultCalID = SettingsManager.shared.defaultQuickAddCalendarID
        let writable = writableCalendars()
        let enterCalendar = writable.first(where: { $0.calendarIdentifier == defaultCalID })
            ?? store.defaultCalendarForNewEvents

        // Build calendar-picker details so Shift+Enter expands the row to
        // let the user pick a target calendar.
        let details: [DetailItem] = writable.map { cal in
            let calRef = cal
            let sym = "\(cal.title)"
            return DetailItem(
                label: cal.source.title, value: sym, icon: "calendar",
                actions: [
                    ResultAction(name: "Create in \(cal.title)") { save(in: calRef) },
                    ResultAction(name: "Create & open in Calendar") { save(in: calRef, openAfter: true) },
                ]
            )
        }

        let enterLabel: String
        if let c = enterCalendar { enterLabel = "Create in \(c.title)" } else { enterLabel = "Create Event" }

        return [SearchResult(
            type: .calendar,
            title: "Create: \(titleStr)",
            subtitle: subtitle,
            icon: icon,
            actions: [
                ResultAction(name: enterLabel) { save(in: enterCalendar) },
                ResultAction(name: "Pick calendar…", dismissesPanel: false) {
                    AppDelegate.shared?.searchCoordinator.expandSelected()
                },
                ResultAction(name: "Create & open in Calendar") { save(in: enterCalendar, openAfter: true) },
            ],
            details: details
        )]
    }

    // MARK: - Location extraction

    /// Words that mark a venue and expand the location capture backward.
    private static let venueKeywords: Set<String> = [
        "airport", "terminal", "gate", "floor", "level", "suite", "building",
        "center", "centre", "plaza", "hotel", "restaurant", "cafe", "café",
        "room", "hall", "arena", "stadium", "theater", "theatre", "museum",
        "library", "school", "college", "university", "hospital", "clinic",
        "church", "temple", "synagogue", "mosque", "chapel", "station", "park",
        "square", "tower", "street", "st", "ave", "avenue", "rd", "road",
        "blvd", "boulevard", "ln", "lane", "way", "dr", "drive", "court", "ct",
        "highway", "hwy", "pkwy", "parkway",
    ]

    /// Given a phrase, find the earliest venue keyword and return
    /// (location, remaining title) — location expands backward through
    /// preceding capitalized words (max 3) so "JFK International Airport" is
    /// captured intact.
    private static func splitLocation(_ text: String) -> (location: String?, title: String) {
        guard !text.isEmpty else { return (nil, "") }
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                        .map(String.init)
        guard !words.isEmpty else { return (nil, text) }

        // Find first venue keyword.
        var keywordIdx: Int?
        for (i, w) in words.enumerated() {
            let clean = w.trimmingCharacters(in: CharacterSet.punctuationCharacters).lowercased()
            if venueKeywords.contains(clean) {
                keywordIdx = i
                break
            }
        }
        guard let ki = keywordIdx else { return (nil, text) }

        // Walk backward at most 2 words if they are capitalized (proper noun
        // sequence), all-caps abbreviations ("JFK"), pure digits ("200"), or
        // numeric ordinals ("5th", "42nd") — those cover street numbers and
        // named-venue components. Two is the sweet spot: three grabs preceding
        // title words like "Interview" too often.
        var startIdx = ki
        var stepsBack = 0
        var i = ki - 1
        while i >= 0, stepsBack < 2 {
            let w = words[i]
            let clean = w.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            let isAllCaps = !clean.isEmpty && clean == clean.uppercased() && clean.count <= 4
            let isCapitalized = clean.first.map { $0.isUppercase } ?? false
            let isNumericOrdinal = clean.range(
                of: #"^\d+(st|nd|rd|th)?$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            if isAllCaps || isCapitalized || isNumericOrdinal {
                startIdx = i
                stepsBack += 1
                i -= 1
            } else { break }
        }

        let title = words[..<startIdx].joined(separator: " ")
        let location = words[startIdx...].joined(separator: " ")
        // Trim trailing prepositions from title.
        var trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        trimmedTitle = trimmedTitle.replacingOccurrences(
            of: #"\s+(at|on|in)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]
        )
        return (location.isEmpty ? nil : location.trimmingCharacters(in: .whitespaces),
                trimmedTitle)
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
