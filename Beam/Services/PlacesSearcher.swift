import Foundation
import AppKit
import MapKit
import CoreLocation

/// Address / place-name search via Apple Maps (`MKLocalSearch`). Free, no key,
/// bundled with the OS. Biased to the United States by constraining the
/// search `region` to a US-covering bounding box — same pattern used in the
/// Shopify address-autocomplete flow (US regionCode + resultTypes.address).
///
/// Fires the query async; results come back on the main queue via a callback
/// so the caller can splice them into the merged results list.
final class PlacesSearcher {
    private var currentSearch: MKLocalSearch?
    private var currentToken: UUID?

    /// US-covering region — center ≈ Wichita, KS with a wide enough span to
    /// cover CONUS + AK + HI corners. MapKit uses this as a "hint" to prefer
    /// US results but will still return the closest matches elsewhere if
    /// nothing local matches.
    private static let usRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 60)
    )

    /// Kick off a place search for `query`. Cancels any in-flight request so
    /// only the latest response reaches the caller. `completion` fires on the
    /// main queue with 0…5 results.
    func search(_ query: String, completion: @escaping (String, [SearchResult]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // Cheap — but skip until we have enough to be place-y, otherwise
        // every keystroke would hit the network.
        guard trimmed.count >= 5, Self.looksLikePlaceQuery(trimmed) else {
            completion(query, [])
            return
        }
        currentSearch?.cancel()

        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        req.resultTypes = [.address, .pointOfInterest]
        req.region = Self.usRegion

        let token = UUID()
        currentToken = token
        let search = MKLocalSearch(request: req)
        currentSearch = search
        search.start { [weak self] response, _ in
            guard let self, self.currentToken == token else { return }
            let items = response?.mapItems ?? []
            let results = Array(items.prefix(5)).map(Self.result(from:))
            DispatchQueue.main.async { completion(query, results) }
        }
    }

    /// Heuristic gate — only trigger a MapKit call when the query has any of:
    ///   • a street-number pattern ("155 Water St")
    ///   • a US ZIP anywhere ("… 10001")
    ///   • an obvious venue-y word ("hospital", "airport", …) that's already
    ///     in `CalendarSearcher.venueKeywords` (kept in sync by hand — small
    ///     list, not worth cross-file coupling).
    private static let venueGate: Set<String> = [
        "airport", "terminal", "hotel", "restaurant", "cafe", "café",
        "hospital", "clinic", "school", "university", "college",
        "church", "temple", "synagogue", "mosque", "station", "park",
        "square", "tower", "street", "st", "ave", "avenue", "rd", "road",
        "blvd", "boulevard", "highway", "hwy", "pkwy", "parkway",
        "stadium", "arena", "museum", "library", "plaza", "center", "centre",
        "starbucks", "walmart", "target", "costco", "cvs", "walgreens",
    ]

    private static func looksLikePlaceQuery(_ text: String) -> Bool {
        if text.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"^\d+\s+\S"#, options: .regularExpression) != nil { return true }
        let lower = text.lowercased()
        for w in lower.split(whereSeparator: { !$0.isLetter }) {
            if venueGate.contains(String(w)) { return true }
        }
        return false
    }

    private static func result(from item: MKMapItem) -> SearchResult {
        let placemark = item.placemark
        let name = item.name ?? placemark.name ?? "Place"
        let address = Self.formatAddress(placemark)
        let subtitle = address.isEmpty ? "" : address
        let icon = NSImage(systemSymbolName: "mappin.and.ellipse", accessibilityDescription: nil)
        icon?.size = NSSize(width: 32, height: 32)

        // Multi-line: title (place name), then address. Consumer of subtitle
        // renders newlines when present.
        return SearchResult(
            type: .place,
            title: name,
            subtitle: subtitle,
            icon: icon,
            actions: [
                ResultAction(name: "Open in Maps") {
                    item.openInMaps(launchOptions: nil)
                },
                ResultAction(name: "Copy address") {
                    NSPasteboard.general.clearContents()
                    let full = name.isEmpty || address.hasPrefix(name)
                        ? address
                        : "\(name)\n\(address)"
                    NSPasteboard.general.beamSet(full)
                },
                ResultAction(name: "Use as event location") {
                    let combined = name.isEmpty || address.hasPrefix(name)
                        ? address
                        : "\(name), \(address)"
                    AppDelegate.shared?.searchCoordinator.queryChanged(combined)
                },
            ]
        )
    }

    /// Assemble a one-line, US-formatted street/city/state/zip string.
    private static func formatAddress(_ placemark: MKPlacemark) -> String {
        var line1Parts: [String] = []
        if let sub = placemark.subThoroughfare { line1Parts.append(sub) }
        if let street = placemark.thoroughfare { line1Parts.append(street) }
        let line1 = line1Parts.joined(separator: " ")

        var line2Parts: [String] = []
        if let city = placemark.locality { line2Parts.append(city) }
        if let state = placemark.administrativeArea {
            if let zip = placemark.postalCode {
                line2Parts.append("\(state) \(zip)")
            } else {
                line2Parts.append(state)
            }
        } else if let zip = placemark.postalCode {
            line2Parts.append(zip)
        }
        let line2 = line2Parts.joined(separator: ", ")

        return [line1, line2].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
