import SwiftUI

struct SearchBarView: NSViewRepresentable {
    @Binding var text: String
    var mathResult: String?

    func makeNSView(context: Context) -> BeamSearchField {
        let field = BeamSearchField()
        field.placeholderString = "Search apps, contacts, files, or calculate..."
        field.font = .systemFont(ofSize: 20, weight: .light)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        field.delegate = context.coordinator
        field.coordinator = context.coordinator
        return field
    }

    func updateNSView(_ nsView: BeamSearchField, context: Context) {
        context.coordinator.textBinding = $text
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var textBinding: Binding<String>

        init(text: Binding<String>) {
            self.textBinding = text
        }

        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                sync(tf.stringValue)
            }
        }

        func sync(_ value: String) {
            if textBinding.wrappedValue != value {
                textBinding.wrappedValue = value
            }
        }
    }
}

/// Custom NSTextField that uses a custom field editor to detect paste
class BeamSearchField: NSTextField {
    weak var coordinator: SearchBarView.Coordinator?
    private var selectionObserver: NSObjectProtocol?
    private lazy var customEditor: BeamFieldEditor = {
        let editor = BeamFieldEditor()
        editor.isFieldEditor = true
        editor.searchField = self
        return editor
    }()

    deinit {
        if let obs = selectionObserver { NotificationCenter.default.removeObserver(obs) }
    }

    override func resignFirstResponder() -> Bool {
        MathTooltipPanel.shared.hide()
        return super.resignFirstResponder()
    }

    // Provide custom field editor that detects paste
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // Observe selection changes in the field editor so we can show the partial
        // evaluation of whatever substring the user has highlighted.
        if result, selectionObserver == nil {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let self = self,
                      let tv = note.object as? NSTextView,
                      tv === self.currentEditor() else { return }
                let r = tv.selectedRange()
                if r.length > 0, r.location + r.length <= (tv.string as NSString).length {
                    let sel = (tv.string as NSString).substring(with: r)
                    AppDelegate.shared?.searchCoordinator.updateSelection(sel)
                    if let m = AppDelegate.shared?.searchCoordinator.selectionMath {
                        let rect = tv.firstRect(forCharacterRange: r, actualRange: nil)
                        MathTooltipPanel.shared.show(text: "\(m.text)  =  \(m.result)", anchor: rect)
                    } else {
                        MathTooltipPanel.shared.hide()
                    }
                } else {
                    AppDelegate.shared?.searchCoordinator.updateSelection("")
                    MathTooltipPanel.shared.hide()
                }
            }
        }
        return result
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        // This fires for typing AND paste in the field editor
        coordinator?.sync(self.stringValue)
    }

    // Also intercept performKeyEquivalent to catch Cmd+V before the field editor
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let result = super.performKeyEquivalent(with: event)
        // After the key equivalent is handled (e.g. paste), sync
        if event.modifierFlags.contains(.command) && event.keyCode == 9 { // Cmd+V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                // Read from field editor
                if let editor = self.currentEditor() {
                    let value = editor.string
                    self.coordinator?.sync(value)
                }
            }
        }
        return result
    }
}

/// Custom field editor that notifies on paste
class BeamFieldEditor: NSTextView {
    weak var searchField: BeamSearchField?

    override func paste(_ sender: Any?) {
        super.paste(sender)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.searchField?.coordinator?.sync(self.string)
        }
    }
}

/// Floating tooltip anchored to a text selection — shows the partial-evaluation
/// result directly above (or below if no room) the highlighted substring.
class MathTooltipPanel: NSPanel {
    static let shared = MathTooltipPanel()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        bubble.layer?.cornerRadius = 7
        bubble.layer?.masksToBounds = true
        bubble.translatesAutoresizingMaskIntoConstraints = false

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(bubble)
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: container.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -9),
        ])
        contentView = container
    }

    /// `anchor` is the selection rect in screen coordinates.
    func show(text: String, anchor: NSRect) {
        guard !text.isEmpty else { hide(); return }
        label.stringValue = text
        label.sizeToFit()
        let w = max(label.frame.width + 20, 60)
        let h = label.frame.height + 8

        // Default: above the selection. If it'd go off the top of the screen, drop below.
        var y = anchor.maxY + 6
        let screenTop = NSScreen.screens.first { $0.frame.contains(anchor.origin) }?.visibleFrame.maxY
            ?? NSScreen.main?.visibleFrame.maxY ?? CGFloat.greatestFiniteMagnitude
        if y + h > screenTop {
            y = anchor.minY - h - 6
        }
        let x = anchor.midX - w / 2
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}
