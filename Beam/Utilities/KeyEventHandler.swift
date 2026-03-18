import SwiftUI
import Carbon
import os.log

private let logger = Logger(subsystem: "com.DNZ.beam", category: "KeyEvents")

struct KeyEventHandlerView: NSViewRepresentable {
    var coordinator: SearchCoordinator
    weak var panel: BeamPanel?

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.coordinator = coordinator
        view.panel = panel
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.coordinator = coordinator
        nsView.panel = panel
    }
}

class KeyCaptureView: NSView {
    var coordinator: SearchCoordinator?
    weak var panel: BeamPanel?
    private var localMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupMonitor()
        } else {
            removeMonitor()
        }
    }

    private func setupMonitor() {
        removeMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow == true else { return event }
            // Log all key events to debug paste
            let kc = event.keyCode
            let mods = event.modifierFlags
            let hasCmd = mods.contains(.command)
            if hasCmd {
                logger.info("Key event: keyCode=\(kc) hasCmd=\(hasCmd)")
            }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let coordinator = coordinator else { return false }
        let keyCode = event.keyCode
        let flags = event.modifierFlags

        switch Int(keyCode) {
        case kVK_DownArrow:
            coordinator.moveDown()
            return true
        case kVK_UpArrow:
            coordinator.moveUp()
            return true
        case kVK_Return:
            if !coordinator.results.isEmpty {
                if flags.contains(.option) {
                    coordinator.executeOptionEnter()
                } else if flags.contains(.shift) {
                    coordinator.executeShiftEnter()
                } else {
                    coordinator.executeSelected()
                }
                AppDelegate.shared?.dismissPanel()
            }
            return true
        case kVK_Escape:
            if !coordinator.query.isEmpty {
                coordinator.clearInput()
                panel?.makeFocused()
            } else {
                AppDelegate.shared?.dismissPanel()
            }
            return true
        case kVK_Tab:
            coordinator.toggleDisplayMode()
            return true
        case kVK_ANSI_Comma:
            if flags.contains(.command) {
                AppDelegate.shared?.openSettings()
                return true
            }
            return false
        case kVK_ANSI_V:
            if flags.contains(.command) {
                logger.info("Cmd+V detected, will sync after delay")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.syncFieldToCoordinator()
                }
                return false // pass through to text field
            }
            return false
        default:
            return false
        }
    }

    private func syncFieldToCoordinator() {
        guard let coordinator = coordinator, let window = self.window else {
            logger.error("syncField: no coordinator or window")
            return
        }
        let fr = window.firstResponder
        logger.info("syncField: firstResponder type = \(String(describing: type(of: fr)))")

        if let textView = fr as? NSTextView {
            let value = textView.string
            logger.info("syncField: field editor value = '\(value)', current query = '\(coordinator.query)'")
            if coordinator.query != value {
                coordinator.queryChanged(value)
                logger.info("syncField: updated query to '\(value)'")
            }
        } else {
            // Try to find any NSTextField in the window
            logger.info("syncField: firstResponder is not NSTextView, trying to find text field")
            if let tf = findTextField(in: window.contentView) {
                let value = tf.stringValue
                logger.info("syncField: found textField value = '\(value)'")
                if coordinator.query != value {
                    coordinator.queryChanged(value)
                }
            }
        }
    }

    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view = view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable { return tf }
        for sub in view.subviews {
            if let found = findTextField(in: sub) { return found }
        }
        return nil
    }

    deinit {
        removeMonitor()
    }
}
