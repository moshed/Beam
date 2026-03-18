import AppKit
import SwiftUI

class BeamPanel: NSPanel {
    private var coordinator: SearchCoordinator

    init(contentRect: NSRect, coordinator: SearchCoordinator) {
        self.coordinator = coordinator
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .utilityWindow
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true

        // Container clips everything to rounded rect
        let container = NSView(frame: contentRect)
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = true

        // Visual effect for frosted glass
        let visualEffect = NSVisualEffectView(frame: container.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]

        container.addSubview(visualEffect)

        let hostingView = NSHostingView(
            rootView: BeamContentView(coordinator: coordinator, panel: self)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.contentView = container
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if !coordinator.query.isEmpty {
            coordinator.clearInput()
        } else {
            AppDelegate.shared?.dismissPanel()
        }
    }

    override func resignKey() {
        super.resignKey()
        // Don't dismiss if settings window is active
        if let settingsWindow = AppDelegate.shared?.settingsWindow, settingsWindow.isVisible {
            return
        }
        AppDelegate.shared?.dismissPanel()
    }

    func centerOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = activeScreen else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 680
        let panelHeight = frame.height
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.midY + screenFrame.height * 0.15
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    func updateHeight(_ newHeight: CGFloat) {
        let currentFrame = frame
        let y = currentFrame.origin.y + currentFrame.height - newHeight
        let newFrame = NSRect(x: currentFrame.origin.x, y: y, width: currentFrame.width, height: newHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }
    }

    func makeFocused() {
        // Will be called after makeKeyAndOrderFront
        DispatchQueue.main.async {
            if let textField = self.findTextField(in: self.contentView) {
                self.makeFirstResponder(textField)
            }
        }
    }

    private func findTextField(in view: NSView?) -> NSView? {
        guard let view = view else { return nil }
        if view is NSTextField {
            return view
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }
}
