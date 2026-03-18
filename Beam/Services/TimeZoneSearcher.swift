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

    func search(_ query: String) -> [SearchResult] {
        let lower = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.count >= 2 else { return [] }

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
                    NSPasteboard.general.setString("\(cityName): \(timeStr) (\(offsetStr))", forType: .string)
                }]
            )
        }.compactMap { $0 }
    }
}
