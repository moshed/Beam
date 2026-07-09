import Foundation
import Darwin
import AppKit
import os.log

/// Triggers macOS Continuity Cellular Calling ("Call using iPhone?" popup).
///
/// Third-party apps can't hit `callservicesd` directly — the daemon rejects
/// any XPC client that doesn't hold Apple's private `access-calls`
/// entitlement (verified: private `TelephonyUtilities` path is silently
/// dropped). Safari.app *does* hold that entitlement and its
/// `open location "tel:..."` command triggers the standard Continuity popup.
/// So we tell Safari to open the tel: URL — Safari brings itself forward
/// briefly to show the popup, user hits Return, the call routes to iPhone.
enum ContinuityDialer {
    private static let log = Logger(subsystem: "com.DNZ.beam", category: "dialer")

    /// Trigger the "Call using iPhone?" popup by asking Safari to open the
    /// `tel:` URL. Returns `true` if the AppleScript event was successfully
    /// posted (not confirmation the user hit Call — that's async).
    @discardableResult
    static func dial(_ e164Number: String) -> Bool {
        log.notice("[dialer] dial() \(e164Number, privacy: .public) via Safari trampoline")

        // Safari accepts tel: via -openURL AppleEvent (open location "tel:...")
        // and, holding the private access-calls entitlement, presents the
        // Continuity call prompt instead of routing to FaceTime.
        let source = """
        tell application "Safari" to open location "tel:\(e164Number)"
        """
        var errInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            log.error("[dialer] failed to build NSAppleScript")
            return false
        }
        _ = script.executeAndReturnError(&errInfo)
        if let errInfo, let msg = errInfo[NSAppleScript.errorMessage] as? String {
            log.error("[dialer] Safari trampoline failed: \(msg, privacy: .public)")
            return false
        }
        return true
    }
}
