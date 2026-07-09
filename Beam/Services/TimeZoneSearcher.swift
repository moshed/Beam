import AppKit

class TimeZoneSearcher {
    // City -> timezone identifier mapping
    private static let cityTimezones: [(city: String, timezone: String, country: String)] = [
        // Asia
        ("tokyo", "Asia/Tokyo", "Japan"),
        ("osaka", "Asia/Tokyo", "Japan"),
        ("seoul", "Asia/Seoul", "South Korea"),
        ("beijing", "Asia/Shanghai", "China"),
        ("shanghai", "Asia/Shanghai", "China"),
        ("shenzhen", "Asia/Shanghai", "China"),
        ("guangzhou", "Asia/Shanghai", "China"),
        ("hong kong", "Asia/Hong_Kong", "Hong Kong"),
        ("taipei", "Asia/Taipei", "Taiwan"),
        ("singapore", "Asia/Singapore", "Singapore"),
        ("bangkok", "Asia/Bangkok", "Thailand"),
        ("jakarta", "Asia/Jakarta", "Indonesia"),
        ("mumbai", "Asia/Kolkata", "India"),
        ("delhi", "Asia/Kolkata", "India"),
        ("kolkata", "Asia/Kolkata", "India"),
        ("bangalore", "Asia/Kolkata", "India"),
        ("karachi", "Asia/Karachi", "Pakistan"),
        ("dubai", "Asia/Dubai", "UAE"),
        ("abu dhabi", "Asia/Dubai", "UAE"),
        ("riyadh", "Asia/Riyadh", "Saudi Arabia"),
        ("tehran", "Asia/Tehran", "Iran"),
        ("kabul", "Asia/Kabul", "Afghanistan"),
        ("dhaka", "Asia/Dhaka", "Bangladesh"),
        ("kuala lumpur", "Asia/Kuala_Lumpur", "Malaysia"),
        ("manila", "Asia/Manila", "Philippines"),
        ("hanoi", "Asia/Ho_Chi_Minh", "Vietnam"),
        ("ho chi minh", "Asia/Ho_Chi_Minh", "Vietnam"),
        // Europe
        ("london", "Europe/London", "UK"),
        ("paris", "Europe/Paris", "France"),
        ("berlin", "Europe/Berlin", "Germany"),
        ("munich", "Europe/Berlin", "Germany"),
        ("frankfurt", "Europe/Berlin", "Germany"),
        ("amsterdam", "Europe/Amsterdam", "Netherlands"),
        ("brussels", "Europe/Brussels", "Belgium"),
        ("madrid", "Europe/Madrid", "Spain"),
        ("barcelona", "Europe/Madrid", "Spain"),
        ("rome", "Europe/Rome", "Italy"),
        ("milan", "Europe/Rome", "Italy"),
        ("zurich", "Europe/Zurich", "Switzerland"),
        ("geneva", "Europe/Zurich", "Switzerland"),
        ("vienna", "Europe/Vienna", "Austria"),
        ("prague", "Europe/Prague", "Czech Republic"),
        ("warsaw", "Europe/Warsaw", "Poland"),
        ("stockholm", "Europe/Stockholm", "Sweden"),
        ("oslo", "Europe/Oslo", "Norway"),
        ("copenhagen", "Europe/Copenhagen", "Denmark"),
        ("helsinki", "Europe/Helsinki", "Finland"),
        ("moscow", "Europe/Moscow", "Russia"),
        ("istanbul", "Europe/Istanbul", "Turkey"),
        ("athens", "Europe/Athens", "Greece"),
        ("lisbon", "Europe/Lisbon", "Portugal"),
        ("dublin", "Europe/Dublin", "Ireland"),
        ("edinburgh", "Europe/London", "UK"),
        ("bucharest", "Europe/Bucharest", "Romania"),
        ("budapest", "Europe/Budapest", "Hungary"),
        ("kyiv", "Europe/Kyiv", "Ukraine"),
        // Americas
        ("new york", "America/New_York", "USA"),
        ("nyc", "America/New_York", "USA"),
        ("boston", "America/New_York", "USA"),
        ("miami", "America/New_York", "USA"),
        ("atlanta", "America/New_York", "USA"),
        ("washington", "America/New_York", "USA"),
        ("chicago", "America/Chicago", "USA"),
        ("dallas", "America/Chicago", "USA"),
        ("houston", "America/Chicago", "USA"),
        ("denver", "America/Denver", "USA"),
        ("los angeles", "America/Los_Angeles", "USA"),
        ("la", "America/Los_Angeles", "USA"),
        ("san francisco", "America/Los_Angeles", "USA"),
        ("sf", "America/Los_Angeles", "USA"),
        ("seattle", "America/Los_Angeles", "USA"),
        ("las vegas", "America/Los_Angeles", "USA"),
        ("phoenix", "America/Phoenix", "USA"),
        ("honolulu", "Pacific/Honolulu", "USA"),
        ("anchorage", "America/Anchorage", "USA"),
        ("toronto", "America/Toronto", "Canada"),
        ("vancouver", "America/Vancouver", "Canada"),
        ("montreal", "America/Toronto", "Canada"),
        ("mexico city", "America/Mexico_City", "Mexico"),
        ("bogota", "America/Bogota", "Colombia"),
        ("lima", "America/Lima", "Peru"),
        ("santiago", "America/Santiago", "Chile"),
        ("buenos aires", "America/Argentina/Buenos_Aires", "Argentina"),
        ("sao paulo", "America/Sao_Paulo", "Brazil"),
        ("rio", "America/Sao_Paulo", "Brazil"),
        // Africa
        ("cairo", "Africa/Cairo", "Egypt"),
        ("lagos", "Africa/Lagos", "Nigeria"),
        ("nairobi", "Africa/Nairobi", "Kenya"),
        ("johannesburg", "Africa/Johannesburg", "South Africa"),
        ("cape town", "Africa/Johannesburg", "South Africa"),
        ("casablanca", "Africa/Casablanca", "Morocco"),
        // Oceania
        ("sydney", "Australia/Sydney", "Australia"),
        ("melbourne", "Australia/Melbourne", "Australia"),
        ("brisbane", "Australia/Brisbane", "Australia"),
        ("perth", "Australia/Perth", "Australia"),
        ("auckland", "Pacific/Auckland", "New Zealand"),
        // Middle East
        ("tel aviv", "Asia/Jerusalem", "Israel"),
        ("jerusalem", "Asia/Jerusalem", "Israel"),
        ("haifa", "Asia/Jerusalem", "Israel"),
        ("doha", "Asia/Qatar", "Qatar"),
        ("kuwait", "Asia/Kuwait", "Kuwait"),
        ("amman", "Asia/Amman", "Jordan"),
        ("beirut", "Asia/Beirut", "Lebanon"),
    ]

    /// US state → timezone identifier. Only includes states that live in a
    /// single timezone (multi-zone states fall back to the majority zone).
    private static let usStateTimezones: [String: String] = [
        "utah": "America/Denver", "colorado": "America/Denver",
        "wyoming": "America/Denver", "montana": "America/Denver",
        "new mexico": "America/Denver", "arizona": "America/Phoenix",
        "nevada": "America/Los_Angeles", "california": "America/Los_Angeles",
        "oregon": "America/Los_Angeles", "washington state": "America/Los_Angeles",
        "washington": "America/New_York",
        "alaska": "America/Anchorage", "hawaii": "Pacific/Honolulu",
        "texas": "America/Chicago", "oklahoma": "America/Chicago",
        "kansas": "America/Chicago", "nebraska": "America/Chicago",
        "arkansas": "America/Chicago", "louisiana": "America/Chicago",
        "mississippi": "America/Chicago", "alabama": "America/Chicago",
        "missouri": "America/Chicago", "iowa": "America/Chicago",
        "minnesota": "America/Chicago", "wisconsin": "America/Chicago",
        "illinois": "America/Chicago", "north dakota": "America/Chicago",
        "south dakota": "America/Chicago",
        "new york": "America/New_York", "new jersey": "America/New_York",
        "pennsylvania": "America/New_York", "connecticut": "America/New_York",
        "massachusetts": "America/New_York", "rhode island": "America/New_York",
        "vermont": "America/New_York", "new hampshire": "America/New_York",
        "maine": "America/New_York", "delaware": "America/New_York",
        "maryland": "America/New_York", "virginia": "America/New_York",
        "west virginia": "America/New_York", "north carolina": "America/New_York",
        "south carolina": "America/New_York", "georgia": "America/New_York",
        "florida": "America/New_York", "ohio": "America/New_York",
        "michigan": "America/New_York", "indiana": "America/New_York",
        "kentucky": "America/New_York", "tennessee": "America/New_York",
        "ny": "America/New_York", "nj": "America/New_York",
        "ca": "America/Los_Angeles", "tx": "America/Chicago",
        "fl": "America/New_York", "wa": "America/Los_Angeles",
        "ut": "America/Denver", "az": "America/Phoenix",
        "co": "America/Denver", "il": "America/Chicago",
        "ma": "America/New_York", "ga": "America/New_York",
    ]

    /// Match `<time>` (via NSDataDetector or common h:mm/hpm shorthand) plus
    /// two locations separated by "to" — e.g. `12:30pm ny to utah`,
    /// `3pm in London to Tokyo`, `noon to sydney`.
    private static func convertPattern(_ text: String) -> SearchResult? {
        let ranges = text.range(of: " to ", options: .caseInsensitive)
        guard let toRange = ranges else { return nil }
        let leftRaw = String(text[..<toRange.lowerBound])
        let rightRaw = String(text[toRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !leftRaw.isEmpty, !rightRaw.isEmpty else { return nil }

        // Right side is expected to be a bare location.
        guard let toTZ = resolveTimezone(rightRaw) else { return nil }

        // Left side has time + optional "in <location>" — split the time.
        let (timeOnLeft, fromLoc) = splitTimeAndLocation(leftRaw)
        guard let timeOnLeft = timeOnLeft else { return nil }
        // Default "from" tz to local if user didn't specify a source.
        let fromTZ = fromLoc.flatMap(resolveTimezone) ?? TimeZone.current

        // Anchor the time to today in the source zone.
        var srcCal = Calendar(identifier: .gregorian); srcCal.timeZone = fromTZ
        let today = srcCal.dateComponents([.year, .month, .day], from: Date())
        var comps = DateComponents()
        comps.year = today.year; comps.month = today.month; comps.day = today.day
        comps.hour = timeOnLeft.hour; comps.minute = timeOnLeft.minute
        comps.timeZone = fromTZ
        guard let sourceDate = srcCal.date(from: comps) else { return nil }

        // Format in the target zone.
        let outFmt = DateFormatter()
        outFmt.timeZone = toTZ
        outFmt.dateFormat = "h:mm a"
        let outTime = outFmt.string(from: sourceDate)
        let dayFmt = DateFormatter()
        dayFmt.timeZone = toTZ
        dayFmt.dateFormat = "EEE, MMM d"
        let outDay = dayFmt.string(from: sourceDate)

        let srcFmt = DateFormatter()
        srcFmt.timeZone = fromTZ
        srcFmt.dateFormat = "h:mm a"
        let srcTime = srcFmt.string(from: sourceDate)

        let fromName = friendlyName(for: fromTZ)
        let toName = friendlyName(for: toTZ)

        let icon = NSImage(systemSymbolName: "clock.arrow.2.circlepath", accessibilityDescription: nil)
        icon?.size = NSSize(width: 32, height: 32)

        let title = "\(srcTime) \(fromName) → \(outTime) \(toName)"
        let subtitle = "\(outDay) · \(toTZ.identifier)"
        let copyStr = title
        return SearchResult(
            type: .timezone,
            title: title,
            subtitle: subtitle,
            icon: icon,
            actions: [ResultAction(name: "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.beamSet(copyStr)
            }]
        )
    }

    /// Look up a place name in the city map first, then US-state map, then
    /// fall back to a case-insensitive TimeZone.knownTimeZoneIdentifiers scan
    /// so "berlin", "utah", or "Asia/Tokyo" all resolve.
    private static func resolveTimezone(_ raw: String) -> TimeZone? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                       .replacingOccurrences(of: #"^(in|at)\s+"#,
                                             with: "",
                                             options: [.regularExpression, .caseInsensitive])
                       .lowercased()
        if let match = cityTimezones.first(where: { $0.city == clean }) {
            return TimeZone(identifier: match.timezone)
        }
        if let tzID = usStateTimezones[clean] { return TimeZone(identifier: tzID) }
        if let tz = TimeZone(identifier: raw) { return tz }
        if let tz = TimeZone(abbreviation: raw.uppercased()) { return tz }
        return nil
    }

    /// Split `"12:30pm in ny"` → (hour=12, minute=30, "ny").
    private static func splitTimeAndLocation(_ text: String) -> ((hour: Int, minute: Int)?, String?) {
        // Regex-scan for h:mm(am|pm)? or h(am|pm) or "noon"/"midnight"
        let patterns = [
            #"(\d{1,2}):(\d{2})\s*(am|pm)?"#,
            #"(\d{1,2})\s*(am|pm)"#,
            #"\b(noon|midnight)\b"#,
        ]
        var hour: Int?
        var minute = 0
        var matchRange: Range<String.Index>?
        for pat in patterns {
            guard let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { continue }
            let nsText = text as NSString
            let hits = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            guard let hit = hits.first else { continue }
            let whole = nsText.substring(with: hit.range).lowercased()
            if whole == "noon" { hour = 12; minute = 0 }
            else if whole == "midnight" { hour = 0; minute = 0 }
            else {
                var groups: [String] = []
                for i in 1..<hit.numberOfRanges {
                    let r = hit.range(at: i)
                    if r.location == NSNotFound { groups.append(""); continue }
                    groups.append(nsText.substring(with: r))
                }
                var h = Int(groups[0]) ?? 0
                if groups.count > 2 {
                    minute = Int(groups[1]) ?? 0
                    let ampm = groups[2].lowercased()
                    if ampm == "pm", h < 12 { h += 12 }
                    if ampm == "am", h == 12 { h = 0 }
                } else if groups.count > 1 {
                    let ampm = groups[1].lowercased()
                    if ampm == "pm", h < 12 { h += 12 }
                    if ampm == "am", h == 12 { h = 0 }
                }
                hour = h
            }
            if let r = Range(hit.range, in: text) { matchRange = r }
            break
        }
        guard let h = hour else { return (nil, nil) }
        // Remaining text (minus the matched time) is the location hint.
        var remaining = text
        if let mr = matchRange { remaining.removeSubrange(mr) }
        remaining = remaining.trimmingCharacters(in: .whitespaces)
        return ((h, minute), remaining.isEmpty ? nil : remaining)
    }

    private static func friendlyName(for tz: TimeZone) -> String {
        // Return the last path component titlecased (e.g. "America/New_York" → "New York").
        let last = tz.identifier.split(separator: "/").last.map(String.init) ?? tz.identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    func search(_ query: String) -> [SearchResult] {
        let lower = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.count >= 2 else { return [] }

        // 1) Cross-zone conversion: "12:30pm ny to utah", "3pm to sydney", etc.
        if lower.contains(" to "), let converted = Self.convertPattern(lower) {
            return [converted]
        }

        // Strip "time in" / "time " prefix
        var searchTerm = lower
        if searchTerm.hasPrefix("time in ") {
            searchTerm = String(searchTerm.dropFirst(8))
        } else if searchTerm.hasPrefix("time ") {
            searchTerm = String(searchTerm.dropFirst(5))
        }

        let matches = Self.cityTimezones.filter { entry in
            entry.city.contains(searchTerm) || entry.country.lowercased().contains(searchTerm)
        }

        guard !matches.isEmpty else { return [] }

        let localTZ = TimeZone.current
        let now = Date()

        return matches.prefix(5).map { entry in
            guard let tz = TimeZone(identifier: entry.timezone) else {
                return nil
            }

            let fmt = DateFormatter()
            fmt.timeZone = tz
            fmt.dateFormat = "h:mm:ss a"
            let timeStr = fmt.string(from: now)

            let dateFmt = DateFormatter()
            dateFmt.timeZone = tz
            dateFmt.dateFormat = "EEE, MMM d"
            let dateStr = dateFmt.string(from: now)

            // Calculate offset from local
            let localOffset = localTZ.secondsFromGMT(for: now)
            let remoteOffset = tz.secondsFromGMT(for: now)
            let diffSeconds = remoteOffset - localOffset
            let diffHours = diffSeconds / 3600
            let diffMins = abs(diffSeconds % 3600) / 60
            var offsetStr: String
            if diffSeconds == 0 {
                offsetStr = "same time"
            } else {
                let sign = diffHours >= 0 ? "+" : ""
                if diffMins == 0 {
                    offsetStr = "\(sign)\(diffHours) hrs"
                } else {
                    offsetStr = "\(sign)\(diffHours):\(String(format: "%02d", diffMins)) hrs"
                }
            }

            let icon = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)
            icon?.size = NSSize(width: 32, height: 32)

            let cityName = entry.city.capitalized
            let fullTime = "\(timeStr) (\(offsetStr))"
            return SearchResult(
                type: .timezone,
                title: "\(cityName) — \(fullTime)",
                subtitle: "\(dateStr) · \(entry.country) · \(entry.timezone)",
                icon: icon,
                actions: [ResultAction(name: "Copy time") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.beamSet("\(cityName): \(timeStr) (\(offsetStr))")
                }]
            )
        }.compactMap { $0 }
    }
}
