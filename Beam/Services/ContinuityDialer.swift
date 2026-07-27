import Foundation
import Darwin
import AppKit
import os.log

/// Triggers macOS Continuity Cellular Calling.
///
/// Third-party apps can't hit `callservicesd` directly — the daemon rejects
/// any XPC client that doesn't hold Apple's private `access-calls`
/// entitlement (verified: private `TelephonyUtilities` path is silently
/// dropped). Apple's own dialer-capable apps *do* hold that entitlement,
/// so we tell one of them to open the `tel:` URL:
///
/// * **Contacts.app** (primary) — dials IMMEDIATELY via Continuity, no
///   popup, no visible UI. Log evidence: callservicesd emits
///   `sendDialCallMessageToHostForCall` + `Dialed call` right after the
///   Contacts open-location event. This is the best UX because the user
///   already expressed intent by hitting Enter on the Call action.
/// * **Mail.app** / **Safari.app** (fallback) — same entitlement, but they
///   present a confirmation dialog and steal focus. We fall through to
///   them if Contacts isn't installed for some reason.
enum ContinuityDialer {
    private static let log = Logger(subsystem: "com.DNZ.beam", category: "dialer")

    @discardableResult
    static func dial(_ e164Number: String) -> Bool {
        log.notice("[dialer] dial() \(e164Number, privacy: .public)")
        // Only Contacts: it dials silently via Continuity. Fewer trampolines
        // = fewer TCC automation prompts to grant. If Contacts is unavailable
        // for some reason the caller falls back to a raw tel: URL.
        if openTelViaApp("Contacts", number: e164Number) {
            log.info("[dialer] dial dispatched via Contacts")
            return true
        }
        log.error("[dialer] Contacts trampoline failed")
        return false
    }

    /// Ask `appName` to open location `tel:<number>` via AppleScript. Returns
    /// `true` iff the AppleEvent was accepted (not confirmation the call
    /// actually placed — that's async and depends on iPhone Continuity
    /// being set up).
    private static func openTelViaApp(_ appName: String, number: String) -> Bool {
        let source = """
        tell application "\(appName)" to open location "tel:\(number)"
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var errInfo: NSDictionary?
        _ = script.executeAndReturnError(&errInfo)
        if let errInfo, let msg = errInfo[NSAppleScript.errorMessage] as? String {
            log.error("[dialer] \(appName, privacy: .public) trampoline failed: \(msg, privacy: .public)")
            return false
        }
        return true
    }
}
