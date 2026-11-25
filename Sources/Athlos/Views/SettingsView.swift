import SwiftUI
import UniformTypeIdentifiers
import AthlosCore

/// Settings: goal, break templates, idle, sleep, shortcuts, notifications, backup.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: BackupFile?
    @State private var message: String?
    @State private var planEditor: PlanEditorRequest?
    @State private var language = AppLanguage.selected
    @State private var showRestart = false

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.store.settings[keyPath: keyPath] },
                set: { v in model.store.updateSettings { $0[keyPath: keyPath] = v } })
    }

    var body: some View {
        let s = model.store.settings
        Form {
            Section {
                Picker("Appearance", selection: Binding(get: { s.appearance }, set: { v in
                    model.store.updateSettings { $0.appearance = v }
                    Theme.apply(v)
                })) {
                    ForEach(AppearanceMode.allCases, id: \.self) { m in
                        Label(m.title, systemImage: m.symbol).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Light is the marble theme, Dark the night theme. “System” follows your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.displayName).tag($0) }
                }
                .onChange(of: language) { _, new in
                    showRestart = AppLanguage.select(new)
                }
            } header: {
                Text("Language")
            } footer: {
                Text("English is the default. Turkish is included; “System” follows your Mac's language.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Daily goal") {
                Stepper(value: binding(\.dailyGoalHours), in: 0.5...16, step: 0.5) {
                    LabeledContent("Goal time", value: Fmt.hm(s.dailyGoalSeconds))
                }
                Text("The bar fills with work time only; breaks don't count.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Automatic breaks", isOn: binding(\.breaksEnabled))
                Picker("Active plan", selection: Binding(get: { s.activePreset.id }, set: { id in model.selectPreset(id) })) {
                    ForEach(s.allPresets, id: \.id) { p in Text("\(p.name) · \(p.summary)").tag(p.id) }
                }
                ForEach(s.presets, id: \.id) { p in
                    PresetRow(preset: p, isActive: p.id == s.activePreset.id, canDelete: s.presets.count > 1,
                              onEdit: { planEditor = PlanEditorRequest(presetID: p.id) })
                }
                PresetRow(preset: s.customPreset, isActive: s.customPreset.id == s.activePreset.id, canDelete: false,
                          onEdit: { planEditor = PlanEditorRequest(presetID: BreakPreset.customID) })
                Button { planEditor = PlanEditorRequest(presetID: nil) } label: {
                    Label("New template", systemImage: "plus")
                }
                Stepper(value: binding(\.snoozeMinutes), in: 1...30) {
                    LabeledContent("Snooze length", value: "\(s.snoozeMinutes) dk")
                }
            } header: {
                Text("Break plan")
            } footer: {
                Text("Each template is a series of work/break blocks applied in order (e.g. 75/15 → 60/10 → 50/60). To work without a template, edit the “Custom plan”.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Idle and sleep") {
                Toggle("Idle detection", isOn: binding(\.idleDetectionEnabled))
                if s.idleDetectionEnabled {
                    Stepper(value: binding(\.idleMinutes), in: 1...120) {
                        LabeledContent("Inactivity time", value: "\(s.idleMinutes) dk")
                    }
                }
                Picker("On sleep / screen lock", selection: binding(\.sleepBehavior)) {
                    Text("Pause the timer").tag(SleepBehavior.pause)
                    Text("Keep counting").tag(SleepBehavior.keepRunning)
                }
            }

            Section("Shortcuts and notifications") {
                Toggle("Global shortcut: ⌃⌥Space (start / pause)", isOn: Binding(get: { s.globalHotKeyEnabled }, set: { v in
                    model.store.updateSettings { $0.globalHotKeyEnabled = v }
                    model.applyHotKeySetting()
                }))
                Toggle("Desktop widget (timer + start/stop)", isOn: Binding(get: { model.desktopWidgetVisible },
                                                                         set: { model.setDesktopWidget(visible: $0) }))
                if model.desktopWidgetVisible {
                    Picker("Widget size", selection: Binding(get: { model.desktopWidgetSize }, set: { model.desktopWidgetSize = $0 })) {
                        ForEach(DesktopWidgetSize.allCases) { Text($0.title).tag($0) }
                    }
                    Text("The widget sits on your desktop behind your windows; drag it by its title to move it. Right-click for size and hide options.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Notifications", isOn: binding(\.notificationsEnabled))
                Toggle("Ask “What did you do?” when stopping", isOn: binding(\.askNoteOnStop))
                LabeledContent("Other shortcuts") {
                    Text("Space start/pause · ⌘K choose topic · ⇧⌘E stop · ⇧⌘B break · ⌘N project · ⇧⌘N subtopic · ⌘1–5 pages")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }

            Section("Backup") {
                Toggle("Daily automatic backup (last 7 days kept)", isOn: binding(\.autoBackupEnabled))
                if let last = model.store.runtime.lastAutoBackupDay {
                    LabeledContent("Last automatic backup", value: Fmt.date(last))
                }
                HStack {
                    Button("Export as JSON…") {
                        if let data = try? BackupService.encode(BackupService.makeBackup(store: model.store, includeImages: true)) {
                            exportDoc = BackupDocument(data: data)
                            showExporter = true
                        }
                    }
                    Button("Import…") { showImporter = true }
                    Spacer()
                    Button("Open backups folder") { NSWorkspace.shared.open(model.paths.backupsDir) }
                    Button("Data folder") { NSWorkspace.shared.open(model.paths.root) }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if let err = model.store.lastSaveError { Text(err).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .athlosPage()
        .navigationTitle("Settings")
        .sheet(item: $planEditor) { req in PlanEditorView(request: req).athlosPage().tint(Theme.accent) }
        .alert("Restart Athlos to change the language", isPresented: $showRestart) {
            Button("Restart now") { AppLanguage.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("A running timer is kept: after the restart choose “Continue”.")
        }
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                      defaultFilename: "Athlos-yedek-\(Date().formatted(.iso8601.year().month().day()))") { result in
            if case .success(let url) = result { message = String(localized: "Exported: \(url.lastPathComponent)") }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try BackupService.decode(Data(contentsOf: url))
            } catch {
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Import this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("Replace current data", role: .destructive) {
                if let b = pendingImport {
                    // A safety backup of the current state is made first.
                    let safety = model.paths.backupsDir.appendingPathComponent("athlos-ice-aktarma-oncesi-\(Int(Date().timeIntervalSince1970)).json")
                    try? BackupService.encode(BackupService.makeBackup(store: model.store, includeImages: false)).write(to: safety)
                    if model.timer.phase != .idle { model.timer.stop() }
                    BackupService.restore(b, into: model.store)
                    model.recovery = model.timer.pendingRecovery()
                    message = String(localized: "Imported: \(b.data.projects.count) projects, \(b.data.entries.count) entries.")
                }
                pendingImport = nil
            }
        } message: {
            if let b = pendingImport {
                Text("Backup from \(Fmt.dateTime(b.exportedAt)): \(b.data.projects.count) projects, \(b.data.entries.count) entries. Your current data will be replaced (a safety backup is made first).")
            }
        }
    }
}

private struct PresetRow: View {
    @Environment(AppModel.self) private var model
    let preset: BreakPreset
    let isActive: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : (preset.isCustom ? "slider.horizontal.3" : "circle"))
                .foregroundStyle(isActive ? Theme.goldText : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.isCustom ? "Custom plan (no template)" : preset.name).fontWeight(isActive ? .semibold : .regular)
                Text(preset.summary + " · " + (preset.blocks.count > 1 ? (preset.afterLast == .cycle ? String(localized: "cycles") : String(localized: "then last block")) : String(localized: "repeats")))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isActive {
                Button("Use") { model.selectPreset(preset.id) }
                    .buttonStyle(.borderless)
            }
            Button("Edit", action: onEdit)
            if !preset.isCustom {
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(!canDelete)
                    .accessibilityLabel("Delete template")
            }
        }
        .confirmationDialog("Delete template “\(preset.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let wasActive = isActive
                model.store.updateSettings { s in
                    s.presets.removeAll { $0.id == preset.id }
                    if s.activePresetID == preset.id { s.activePresetID = s.presets.first?.id }
                }
                if wasActive { model.timer.restartPlan() }
            }
        }
    }
}

/// File document for export.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
