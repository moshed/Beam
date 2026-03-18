import Carbon

class HotkeyManager {
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var action: () -> Void
    private static var instance: HotkeyManager?
    private let settings = SettingsManager.shared

    init(onToggle: @escaping () -> Void) {
        self.action = onToggle
        HotkeyManager.instance = self
        installHandler()
        registerHotkey(settings.toggleShortcut)

        settings.onToggleShortcutChanged = { [weak self] in
            guard let self = self else { return }
            self.unregisterHotkey()
            self.registerHotkey(self.settings.toggleShortcut)
        }
    }

    deinit {
        unregisterHotkey()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    HotkeyManager.instance?.action()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func registerHotkey(_ combo: KeyCombo) {
        let carbonID = EventHotKeyID(
            signature: OSType(0x4245414D), // "BEAM"
            id: 1
        )
        RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            carbonID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
