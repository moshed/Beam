#!/usr/bin/env swift

// CLI tool to test Beam's contact search and other logic
// Usage: swift beam-test.swift contacts "john"
//        swift beam-test.swift math "3 x 2"
//        swift beam-test.swift auth

import Contacts
import Foundation

func testContactsAuth() {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    switch status {
    case .notDetermined:
        print("Status: NOT DETERMINED (never asked)")
        print("Requesting access now...")
        let store = CNContactStore()
        let semaphore = DispatchSemaphore(value: 0)
        store.requestAccess(for: .contacts) { granted, error in
            print("  Granted: \(granted)")
            if let error = error {
                print("  Error: \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    case .restricted:
        print("Status: RESTRICTED (parental controls or MDM)")
    case .denied:
        print("Status: DENIED")
        print("Fix: System Settings > Privacy & Security > Contacts > enable Beam")
    case .authorized:
        print("Status: AUTHORIZED")
    case .limited:
        print("Status: LIMITED")
    @unknown default:
        print("Status: UNKNOWN (\(status.rawValue))")
    }
}

func testContactSearch(_ query: String) {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    print("Contacts auth status: \(status.rawValue) ", terminator: "")
    switch status {
    case .authorized: print("(authorized)")
    case .denied: print("(DENIED - go to System Settings > Privacy & Security > Contacts)")
    case .notDetermined: print("(not determined - run 'swift beam-test.swift auth' first)")
    default: print("(\(status))")
    }

    guard status == .authorized else {
        print("Cannot search - not authorized")
        return
    }

    let store = CNContactStore()
    let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    let predicate = CNContact.predicateForContacts(matchingName: query)
    do {
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        print("Found \(contacts.count) contacts for '\(query)':")
        for contact in contacts.prefix(10) {
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            let email = (contact.emailAddresses.first?.value as String?) ?? ""
            print("  \(name) | \(phone) | \(email)")
        }
        if contacts.isEmpty {
            print("  (none)")
        }
    } catch {
        print("Error searching: \(error.localizedDescription)")
    }
}

func testMath(_ input: String) {
    // Quick test of expression evaluation
    let expr = input
        .replacingOccurrences(of: "^", with: "**")
        .replacingOccurrences(of: #"(\d)\s*[xX]\s*(\d)"#, with: "$1*$2", options: .regularExpression)

    if let nsExpr = try? NSExpression(format: expr),
       let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber {
        print("\(input) = \(result)")
    } else {
        print("Could not evaluate: \(input)")
        print("Processed as: \(expr)")
    }
}

// Main
let args = CommandLine.arguments
if args.count < 2 {
    print("Usage:")
    print("  swift beam-test.swift auth              - Check/request contacts permission")
    print("  swift beam-test.swift contacts \"name\"    - Search contacts")
    print("  swift beam-test.swift math \"3 x 2\"       - Test math evaluation")
    exit(0)
}

switch args[1] {
case "auth":
    testContactsAuth()
case "contacts":
    let query = args.count > 2 ? args[2] : "test"
    testContactSearch(query)
case "math":
    let expr = args.count > 2 ? args[2] : "3 x 2"
    testMath(expr)
default:
    print("Unknown command: \(args[1])")
}
