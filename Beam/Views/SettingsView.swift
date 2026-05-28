import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecordingShortcut = false
    @State private var isRecordingHistoryShortcut = false
    @State private var isRecordingExpandShortcut = false
    @State private var isRecordingCollapseShortcut = false

    @ObservedObject private var settingsState = SettingsState.shared

    var body: some View {
        TabView(selection: $settingsState.selectedTab) {
            GeneralSettingsTab(settings: settings, isRecordingShortcut: $isRecordingShortcut, isRecordingHistoryShortcut: $isRecordingHistoryShortcut, isRecordingExpandShortcut: $isRecordingExpandShortcut, isRecordingCollapseShortcut: $isRecordingCollapseShortcut)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)
            ActionsSettingsTab(settings: settings)
                .tabItem { Label("Actions", systemImage: "hand.tap") }
                .tag(1)
            UpdatesSettingsTab()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
                .tag(2)
        }
        .frame(width: 480, height: 620)
    }
}

struct GeneralSettingsTab: View {
    @ObservedObject var settings: SettingsManager
    @Binding var isRecordingShortcut: Bool
    @Binding var isRecordingHistoryShortcut: Bool
    @Binding var isRecordingExpandShortcut: Bool
    @Binding var isRecordingCollapseShortcut: Bool
    @State private var ollamaModels: [String] = []
    @State private var loadingModels: Bool = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Beam at login", isOn: $settings.launchAtLogin)
            }

            Section("Shortcuts") {
                HStack {
                    Text("Activate Beam")
                    Spacer()
                    ShortcutRecorderView(
                        combo: $settings.toggleShortcut,
                        isRecording: $isRecordingShortcut,
                        allowBareKeys: false
                    )
                }
                HStack {
                    Text("Show History")
                    Spacer()
                    ShortcutRecorderView(
                        combo: $settings.historyShortcut,
                        isRecording: $isRecordingHistoryShortcut,
                        allowBareKeys: true
                    )
                }
                Text("Triggers when search bar is empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Expand Result")
                    Spacer()
                    ShortcutRecorderView(
                        combo: $settings.expandShortcut,
                        isRecording: $isRecordingExpandShortcut,
                        allowBareKeys: true
                    )
                }
                HStack {
                    Text("Collapse Result")
                    Spacer()
                    ShortcutRecorderView(
                        combo: $settings.collapseShortcut,
                        isRecording: $isRecordingCollapseShortcut,
                        allowBareKeys: true
                    )
                }
            }

            Section("History") {
                HStack {
                    Text("\(HistoryManager.shared.entries.count) entries")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History") {
                        HistoryManager.shared.clearHistory()
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("Ask AI") {
                HStack {
                    Text("Model")
                    Spacer()
                    if loadingModels {
                        ProgressView().controlSize(.small)
                    } else if ollamaModels.isEmpty {
                        Text("No models found").foregroundStyle(.secondary).font(.caption)
                    } else {
                        Picker("", selection: $settings.ollamaModel) {
                            Text("Auto").tag("")
                            ForEach(ollamaModels, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                    }
                    Button(action: refreshModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
                Text("\"Auto\" picks the first model Ollama returns. Refresh after installing new models with `ollama pull`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Picker("Default Result View", selection: $settings.resultDisplayMode) {
                    ForEach(ResultDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Text("Press Tab in search to toggle between views")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.resultDisplayMode == .grouped {
                    Text("Section Order")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.top, 4)

                    List {
                        ForEach(settings.sectionOrder, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                    .font(.system(size: 11))
                                if let type = SearchResultType.allCases.first(where: { $0.rawValue == name }) {
                                    Image(systemName: type.iconName)
                                        .frame(width: 16)
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 11))
                                }
                                Text(name)
                                    .font(.system(size: 12))
                            }
                            .padding(.vertical, 1)
                        }
                        .onMove { from, to in
                            settings.sectionOrder.move(fromOffsets: from, toOffset: to)
                        }
                    }
                    .listStyle(.bordered)
                    .frame(minHeight: 320)

                    Button("Reset to Default") {
                        settings.sectionOrder = SettingsManager.defaultSectionOrder
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshModels() }
    }

    private func refreshModels() {
        loadingModels = true
        Task {
            let models = await OllamaSearcher.shared.listModels()
            await MainActor.run {
                ollamaModels = models
                loadingModels = false
            }
        }
    }
}

struct ActionsSettingsTab: View {
    @ObservedObject var settings: SettingsManager
    private let types: [SearchResultType] = [.math, .app, .contact, .file, .shortcut, .definition, .reminder, .calendar, .emoji, .unicode, .timezone, .ai]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configure what Enter, Shift+Enter, and Option+Enter do for each result type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ForEach(types, id: \.rawValue) { type in
                    let available = CategoryActions.available[type] ?? []
                    if available.count > 1 {
                        CategoryActionSection(type: type, available: available, settings: settings)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
}

struct CategoryActionSection: View {
    let type: SearchResultType
    let available: [String]
    @ObservedObject var settings: SettingsManager

    private let slotLabels = ["↵ Enter", "⇧ Shift+Enter", "⌥ Option+Enter"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.system(size: 12))
                Text(type.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16)

            ForEach(0..<min(available.count, 3), id: \.self) { slot in
                HStack {
                    Text(slotLabels[slot])
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 120, alignment: .leading)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { settings.actionIndex(for: type, slot: slot) },
                        set: { settings.setActionIndex(for: type, slot: slot, actionIdx: $0) }
                    )) {
                        ForEach(0..<available.count, id: \.self) { idx in
                            Text(available[idx]).tag(idx)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
            }

            if type == .reminder {
                HStack {
                    Text("Postpone offset")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Button(action: {
                        settings.reminderDueDateOffsetMinutes = max(1, settings.reminderDueDateOffsetMinutes - 5)
                    }) {
                        Image(systemName: "minus")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.bordered)

                    TextField("", value: $settings.reminderDueDateOffsetMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)

                    Button(action: {
                        settings.reminderDueDateOffsetMinutes = min(10080, settings.reminderDueDateOffsetMinutes + 5)
                    }) {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.bordered)

                    Text(offsetLabel(settings.reminderDueDateOffsetMinutes))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
                .padding(.horizontal, 8)
        )
    }

    private func offsetLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hrs = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return hrs == 1 ? "1 hour" : "\(hrs) hours" }
        return "\(hrs)h \(mins)m"
    }
}

// MARK: - Section Order

struct SectionOrderTab: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag to reorder how result categories appear in grouped mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            List {
                ForEach(settings.sectionOrder, id: \.self) { name in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        if let type = SearchResultType.allCases.first(where: { $0.rawValue == name }) {
                            Image(systemName: type.iconName)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                        }
                        Text(name)
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    settings.sectionOrder.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.bordered)
            .padding(.horizontal, 12)

            HStack {
                Spacer()
                Button("Reset to Default") {
                    settings.sectionOrder = SettingsManager.defaultSectionOrder
                }
                .font(.system(size: 11))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: View {
    @Binding var combo: KeyCombo
    @Binding var isRecording: Bool
    var allowBareKeys: Bool = false

    var body: some View {
        Button(action: { isRecording.toggle() }) {
            Text(isRecording ? "Press shortcut..." : combo.displayString)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .background(
            ShortcutCaptureView(combo: $combo, isRecording: $isRecording, allowBareKeys: allowBareKeys)
                .frame(width: 0, height: 0)
        )
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var combo: KeyCombo
    @Binding var isRecording: Bool
    var allowBareKeys: Bool = false

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.allowBareKeys = allowBareKeys
        view.onCapture = { [self] keyCode, modifiers in
            combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.isCapturing = isRecording
        nsView.allowBareKeys = allowBareKeys
    }
}

class ShortcutCaptureNSView: NSView {
    var isCapturing = false
    var allowBareKeys = false
    var onCapture: ((UInt32, UInt32) -> Void)?
    private var monitor: Any?

    private static let bareKeyAllowList: Set<UInt16> = [
        UInt16(kVK_DownArrow), UInt16(kVK_UpArrow),
        UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
        UInt16(kVK_Space), UInt16(kVK_Tab),
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3),
        UInt16(kVK_F4), UInt16(kVK_F5), UInt16(kVK_F6),
        UInt16(kVK_F7), UInt16(kVK_F8), UInt16(kVK_F9),
        UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
    ]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isCapturing else { return event }

                let flags = event.modifierFlags
                var mods: UInt32 = 0
                if flags.contains(.command) { mods |= UInt32(cmdKey) }
                if flags.contains(.shift) { mods |= UInt32(shiftKey) }
                if flags.contains(.option) { mods |= UInt32(optionKey) }
                if flags.contains(.control) { mods |= UInt32(controlKey) }

                if event.keyCode == UInt16(kVK_Escape) {
                    self.isCapturing = false
                    return nil
                }

                // Accept: modifier+key, Space alone, or bare keys from allowlist
                if mods != 0 || event.keyCode == UInt16(kVK_Space) ||
                   (self.allowBareKeys && Self.bareKeyAllowList.contains(event.keyCode)) {
                    self.onCapture?(UInt32(event.keyCode), mods)
                    return nil
                }

                return event
            }
        }
    }

    override func removeFromSuperview() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        super.removeFromSuperview()
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
