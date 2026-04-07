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

        // Check for history shortcut
        let historyCombo = SettingsManager.shared.historyShortcut
        if historyCombo.matches(keyCode: UInt32(keyCode), modifiers: carbonModifiers(from: flags)),
           !coordinator.isHistoryMode,
           coordinator.query.isEmpty,
           coordinator.results.isEmpty {
            coordinator.showHistory()
            return true
        }

        // Check expand/collapse shortcuts
        let mods = carbonModifiers(from: flags)
        let expandCombo = SettingsManager.shared.expandShortcut
        let collapseCombo = SettingsManager.shared.collapseShortcut

        if expandCombo.matches(keyCode: UInt32(keyCode), modifiers: mods) {
            if coordinator.isHistoryMode {
                coordinator.cycleHistoryFilter(forward: true)
                return true
            } else if coordinator.selectedIndex >= 0,
                      coordinator.selectedIndex < coordinator.results.count,
                      coordinator.results[coordinator.selectedIndex].isExpandable {
                coordinator.expandSelected()
                return true
            }
        }
        if collapseCombo.matches(keyCode: UInt32(keyCode), modifiers: mods) {
            if coordinator.isHistoryMode {
                coordinator.cycleHistoryFilter(forward: false)
                return true
            } else if coordinator.expandedResultId != nil {
                coordinator.collapseExpanded()
                return true
            }
        }

        switch Int(keyCode) {
        case kVK_DownArrow:
            coordinator.moveDown()
            return true
        case kVK_UpArrow:
            coordinator.moveUp()
            return true
        case kVK_Return:
            if !coordinator.results.isEmpty {
                let wasHistoryMode = coordinator.isHistoryMode && coordinator.expandedDetailIndex == nil
                let slot = flags.contains(.option) ? 2 : flags.contains(.shift) ? 1 : 0
                let shouldDismiss = coordinator.executeFocusedAction(slot: slot)
                if shouldDismiss {
                    AppDelegate.shared?.dismissPanel()
                } else if wasHistoryMode {
                    // History entry selected — query was filled, update text field
                    panel?.makeFocused()
                    if let editor = panel?.firstResponder as? NSTextView {
                        editor.string = coordinator.query
                        editor.setSelectedRange(NSRange(location: coordinator.query.count, length: 0))
                    }
                }
            }
            return true
        case kVK_Escape:
            if coordinator.isHistoryMode {
                coordinator.exitHistoryMode()
                panel?.makeFocused()
            } else if !coordinator.query.isEmpty {
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
            // In history mode, any typed character exits history and starts a search
            if coordinator.isHistoryMode,
               let chars = event.characters, !chars.isEmpty,
               !flags.contains(.command), !flags.contains(.control) {
                coordinator.exitHistoryMode()
                coordinator.queryChanged(chars)
                // Focus the text field and set the typed character
                DispatchQueue.main.async { [weak self] in
                    self?.panel?.makeFocused()
                    if let editor = self?.panel?.firstResponder as? NSTextView {
                        editor.string = chars
                        editor.setSelectedRange(NSRange(location: chars.count, length: 0))
                    }
                }
                return true
            }
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

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    deinit {
        removeMonitor()
    }
}
