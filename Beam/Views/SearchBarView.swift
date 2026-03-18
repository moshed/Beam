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
    private lazy var customEditor: BeamFieldEditor = {
        let editor = BeamFieldEditor()
        editor.isFieldEditor = true
        editor.searchField = self
        return editor
    }()

    // Provide custom field editor that detects paste
    override func becomeFirstResponder() -> Bool {
        // Install our custom field editor
        let result = super.becomeFirstResponder()
        if result, let editor = self.currentEditor() as? NSTextView {
            // We can't replace the field editor, but we can observe it
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
