import AppKit
import SwiftUI
import Contacts

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var panel: BeamPanel?
    private var hotkeyManager: HotkeyManager?
    private(set) var searchCoordinator = SearchCoordinator()
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Hide the empty window
        for window in NSApp.windows where window.title.isEmpty || window.identifier?.rawValue == "hidden" {
            window.orderOut(nil)
        }
        setupStatusItem()
        setupPanel()
        setupHotkey()
        requestContactsAccess()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Beam")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let relaunchItem = NSMenuItem(title: "Relaunch", action: #selector(relaunchApp), keyEquivalent: "r")
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Beam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Panel

    private func setupPanel() {
        let panel = BeamPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 56),
            coordinator: searchCoordinator
        )
        self.panel = panel
    }

    func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let panel = panel else { return }
        searchCoordinator.restorePrevious()
        panel.centerOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFocused()
    }

    func dismissPanel() {
        searchCoordinator.saveAndClear()
        panel?.orderOut(nil)
    }

    // MARK: - Settings

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Show dock icon while settings is open
        NSApp.setActivationPolicy(.regular)

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Beam Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    // Hide dock icon when settings closes
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Relaunch

    @objc func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Permissions

    private func requestContactsAccess() {
        // Delay to ensure app is fully launched
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.activate(ignoringOtherApps: true)
            let store = CNContactStore()
            let status = CNContactStore.authorizationStatus(for: .contacts)
            print("[Beam] Contacts auth status: \(status.rawValue)")

            if status == .notDetermined {
                // Try fetching contacts directly — this triggers the system prompt
                DispatchQueue.global(qos: .userInitiated).async {
                    let keys = [CNContactGivenNameKey as CNKeyDescriptor]
                    let request = CNContactFetchRequest(keysToFetch: keys)
                    request.predicate = CNContact.predicateForContacts(matchingName: "test")
                    do {
                        _ = try store.unifiedContacts(matching: request.predicate!, keysToFetch: keys)
                        print("[Beam] Contacts access granted via fetch")
                    } catch {
                        print("[Beam] Contacts fetch error (expected if denied): \(error.localizedDescription)")
                    }
                }
            } else if status == .denied {
                print("[Beam] Contacts denied — enable in System Settings > Privacy & Security > Contacts")
            } else if status == .authorized {
                print("[Beam] Contacts already authorized")
            }
        }
    }
}
