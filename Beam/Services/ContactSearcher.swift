import Contacts
import AppKit

class ContactSearcher {
    private let store = CNContactStore()
    private(set) var isAuthorized = false

    /// (identifier, lowercased organizationName) — cached at startup and refreshed
    /// on CNContactStore change notifications so per-keystroke org lookup is O(N)
    /// over an in-memory array rather than a fresh CNContactFetchRequest.
    private var orgIndex: [(id: String, org: String)] = []
    private var orgIndexLoaded = false

    init() {
        checkAndRequestAccess()
        NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildOrgIndex() }
    }

    private func rebuildOrgIndex() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let req = CNContactFetchRequest(keysToFetch: [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
            ])
            req.unifyResults = true
            var index: [(String, String)] = []
            _ = try? self.store.enumerateContacts(with: req) { contact, _ in
                let org = contact.organizationName
                if !org.isEmpty {
                    index.append((contact.identifier, org.lowercased()))
                }
            }
            DispatchQueue.main.async {
                self.orgIndex = index
                self.orgIndexLoaded = true
            }
        }
    }

    func checkAndRequestAccess() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            isAuthorized = true
            rebuildOrgIndex()
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.rebuildOrgIndex() }
                    if !granted {
                        print("[Beam] Contacts access denied: \(error?.localizedDescription ?? "user denied")")
                    }
                }
            }
        case .limited:
            isAuthorized = true
            rebuildOrgIndex()
        default:
            isAuthorized = false
            print("[Beam] Contacts access status: \(status.rawValue) — grant in System Settings > Privacy & Security > Contacts")
        }
    }

    /// Normalise a phone-number string to E.164 (+1XXXXXXXXXX for bare US 10-digit).
    private static func e164(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
            return "+\(digits)"
        }
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return "+\(digits)"
    }

    func search(_ query: String) -> [SearchResult] {
        guard isAuthorized || CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return []
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
        ]

        // Match by name (given/family/composite) AND by organization name so
        // business contacts with no first/last (e.g. "Fesco") still surface.
        // Org lookup is served from a cached in-memory index built once at
        // launch — cheap per keystroke.
        let namePred = CNContact.predicateForContacts(matchingName: trimmed)
        let nameHits = (try? store.unifiedContacts(matching: namePred, keysToFetch: keysToFetch)) ?? []

        let lowerQ = trimmed.lowercased()
        let nameHitIDs = Set(nameHits.map(\.identifier))
        let orgIDs = orgIndex
            .lazy
            .filter { $0.org.contains(lowerQ) && !nameHitIDs.contains($0.id) }
            .prefix(5)
            .map(\.id)
        let orgHits: [CNContact]
        if orgIDs.isEmpty {
            orgHits = []
        } else {
            let orgPred = CNContact.predicateForContacts(withIdentifiers: Array(orgIDs))
            orgHits = (try? store.unifiedContacts(matching: orgPred, keysToFetch: keysToFetch)) ?? []
        }
        let contacts = nameHits + orgHits

        return contacts.prefix(5).map { contact in
            var name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if name.isEmpty { name = contact.organizationName }
            if name.isEmpty { name = contact.emailAddresses.first?.value as String? ?? "" }

            let phone = contact.phoneNumbers.first?.value.stringValue
            let email = contact.emailAddresses.first?.value as String?
            let subtitle = phone ?? email ?? ""

            var icon: NSImage?
            if let data = contact.thumbnailImageData {
                icon = NSImage(data: data)
            }
            if icon == nil {
                icon = NSImage(systemSymbolName: "person.circle.fill", accessibilityDescription: nil)
            }
            icon?.size = NSSize(width: 32, height: 32)

            let identifier = contact.identifier
            var actions: [ResultAction] = []
            actions.append(ResultAction(name: "Open in Contacts") {
                if let url = URL(string: "addressbook://\(identifier)") {
                    NSWorkspace.shared.open(url)
                }
            })
            if let ph = phone {
                let dialNum = Self.e164(ph)
                actions.append(ResultAction(name: "Call \(ph)") {
                    if !ContinuityDialer.dial(dialNum), let url = URL(string: "tel:\(dialNum)") {
                        NSWorkspace.shared.open(url)
                    }
                })
                actions.append(ResultAction(name: "Copy number") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.beamSet(ph)
                })
            }

            // Build detail items for expansion
            var details: [DetailItem] = []
            for pn in contact.phoneNumbers {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: pn.label ?? "")
                let num = pn.value.stringValue
                let dialNum = Self.e164(num)
                details.append(DetailItem(
                    label: label, value: num, icon: "phone.fill",
                    actions: [
                        ResultAction(name: "Call") {
                            if !ContinuityDialer.dial(dialNum), let url = URL(string: "tel:\(dialNum)") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.beamSet(num) },
                        ResultAction(name: "Message") { if let url = URL(string: "sms:\(dialNum)") { NSWorkspace.shared.open(url) } },
                    ]
                ))
            }
            for em in contact.emailAddresses {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: em.label ?? "")
                let addr = em.value as String
                details.append(DetailItem(
                    label: label, value: addr, icon: "envelope.fill",
                    actions: [
                        ResultAction(name: "Compose") { if let url = URL(string: "mailto:\(addr)") { NSWorkspace.shared.open(url) } },
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.beamSet(addr) },
                    ]
                ))
            }
            if !contact.jobTitle.isEmpty || !contact.organizationName.isEmpty {
                let parts = [contact.jobTitle, contact.organizationName].filter { !$0.isEmpty }
                let text = parts.joined(separator: " at ")
                details.append(DetailItem(
                    label: "Work", value: text, icon: "building.2.fill",
                    actions: [ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.beamSet(text) }]
                ))
            }
            if let bday = contact.birthday, let date = Calendar.current.date(from: bday) {
                let fmt = DateFormatter(); fmt.dateStyle = .medium
                let text = fmt.string(from: date)
                details.append(DetailItem(
                    label: "Birthday", value: text, icon: "gift.fill",
                    actions: [ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.beamSet(text) }]
                ))
            }
            for addr in contact.postalAddresses {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: addr.label ?? "")
                let v = addr.value
                let parts = [v.street, v.city, v.state, v.postalCode, v.country].filter { !$0.isEmpty }
                let text = parts.joined(separator: ", ")
                let mapQuery = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                details.append(DetailItem(
                    label: label, value: text, icon: "map.fill",
                    actions: [
                        ResultAction(name: "Open in Maps") { if let url = URL(string: "maps://?q=\(mapQuery)") { NSWorkspace.shared.open(url) } },
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.beamSet(text) },
                    ]
                ))
            }
            for urlVal in contact.urlAddresses {
                let text = urlVal.value as String
                details.append(DetailItem(
                    label: "URL", value: text, icon: "link",
                    actions: [
                        ResultAction(name: "Open") { if let url = URL(string: text.hasPrefix("http") ? text : "https://\(text)") { NSWorkspace.shared.open(url) } },
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.beamSet(text) },
                    ]
                ))
            }

            return SearchResult(
                type: .contact,
                title: name,
                subtitle: subtitle,
                icon: icon,
                actions: actions,
                details: details
            )
        }
    }
}
