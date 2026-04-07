import Contacts
import AppKit

class ContactSearcher {
    private let store = CNContactStore()
    private(set) var isAuthorized = false

    init() {
        checkAndRequestAccess()
    }

    func checkAndRequestAccess() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if !granted {
                        print("[Beam] Contacts access denied: \(error?.localizedDescription ?? "user denied")")
                    }
                }
            }
        case .limited:
            isAuthorized = true
        default:
            isAuthorized = false
            print("[Beam] Contacts access status: \(status.rawValue) — grant in System Settings > Privacy & Security > Contacts")
        }
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

        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch) else {
            return []
        }

        return contacts.prefix(5).map { contact in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

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
                let dialNum = ph.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
                actions.append(ResultAction(name: "Call \(ph)") {
                    if let url = URL(string: "tel:\(dialNum)") {
                        NSWorkspace.shared.open(url)
                    }
                })
                actions.append(ResultAction(name: "Copy number") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ph, forType: .string)
                })
            }

            // Build detail items for expansion
            var details: [DetailItem] = []
            for pn in contact.phoneNumbers {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: pn.label ?? "")
                let num = pn.value.stringValue
                let dialNum = num.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
                details.append(DetailItem(
                    label: label, value: num, icon: "phone.fill",
                    actions: [
                        ResultAction(name: "Call") { if let url = URL(string: "tel:\(dialNum)") { NSWorkspace.shared.open(url) } },
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(num, forType: .string) },
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
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(addr, forType: .string) },
                    ]
                ))
            }
            if !contact.jobTitle.isEmpty || !contact.organizationName.isEmpty {
                let parts = [contact.jobTitle, contact.organizationName].filter { !$0.isEmpty }
                let text = parts.joined(separator: " at ")
                details.append(DetailItem(
                    label: "Work", value: text, icon: "building.2.fill",
                    actions: [ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }]
                ))
            }
            if let bday = contact.birthday, let date = Calendar.current.date(from: bday) {
                let fmt = DateFormatter(); fmt.dateStyle = .medium
                let text = fmt.string(from: date)
                details.append(DetailItem(
                    label: "Birthday", value: text, icon: "gift.fill",
                    actions: [ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }]
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
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) },
                    ]
                ))
            }
            for urlVal in contact.urlAddresses {
                let text = urlVal.value as String
                details.append(DetailItem(
                    label: "URL", value: text, icon: "link",
                    actions: [
                        ResultAction(name: "Open") { if let url = URL(string: text.hasPrefix("http") ? text : "https://\(text)") { NSWorkspace.shared.open(url) } },
                        ResultAction(name: "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) },
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
