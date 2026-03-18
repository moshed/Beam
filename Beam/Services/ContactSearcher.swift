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
            CNContactIdentifierKey as CNKeyDescriptor
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

            return SearchResult(
                type: .contact,
                title: name,
                subtitle: subtitle,
                icon: icon,
                actions: actions
            )
        }
    }
}
