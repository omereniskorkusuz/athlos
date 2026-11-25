import SwiftUI
import AthlosCore

/// Plan editor request. `presetID == nil` → new template.
struct PlanEditorRequest: Identifiable {
    let id = UUID()
    var presetID: UUID?
    /// Make this plan active when saving.
    var activateOnSave = false
}

/// Daily break plan editor: work/break blocks applied in order.
/// E.g. work 75 min · 15 min break → 60/10 → work 50 min · 60 min lunch break.
struct PlanEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: PlanEditorRequest

    @State private var draft = BreakPreset(name: "", blocks: [PlanBlock(workMinutes: 50, breakMinutes: 10)])
    @State private var loaded = false
    @State private var saveAsName = ""
    @State private var showSaveAs = false
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

    private var isNew: Bool { request.presetID == nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach($draft.blocks) { $block in
                        BlockRow(number: (draft.blocks.firstIndex { $0.id == block.id } ?? 0) + 1,
                                 block: $block,
                                 isLast: block.id == draft.blocks.last?.id,
                                 canDelete: draft.blocks.count > 1,
                                 onDelete: { withAnimation { draft.blocks.removeAll { $0.id == block.id } } },
                                 onMove: { move(block.id, by: $0) })
                    }
                    Button {
                        let last = draft.blocks.last ?? PlanBlock(workMinutes: 50, breakMinutes: 10)
                        withAnimation { draft.blocks.append(PlanBlock(workMinutes: last.workMinutes, breakMinutes: last.breakMinutes)) }
                    } label: {
                        Label("Add block", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)

                    Divider().padding(.vertical, 6)

                    Picker("After the last block", selection: $draft.afterLast) {
                        Text("Repeat the last block").tag(PlanRepeat.repeatLast)
                        Text("Start over").tag(PlanRepeat.cycle)
                    }
                    .pickerStyle(.segmented)
                    .disabled(draft.blocks.count < 2)

                    timeline
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 600)
        .onAppear(perform: load)
        .alert("Save as template", isPresented: $showSaveAs) {
            TextField("Template name", text: $saveAsName)
            Button("Save") { saveAsTemplate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This plan is added to your templates under this name and becomes active.")
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.isCustom ? "Custom plan (no template)" : isNew ? "New template" : "Edit template")
                .font(.title2.bold())
            if draft.isCustom {
                Text("Set up today's durations however you like; no need to save a template.")
                    .foregroundStyle(.secondary)
            } else {
                TextField("Template name", text: $draft.name, prompt: Text("e.g. My workday"))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }
            Text("Blocks run in order: in each block you work first, then take a break. If you stop and start again later the same day, you continue from the block you were on; the next day starts from the first block.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Totals + a sample timeline from the chosen start time.
    private var timeline: some View {
        let totalWork = draft.blocks.reduce(0) { $0 + $1.workMinutes }
        let totalBreak = draft.blocks.reduce(0) { $0 + $1.breakMinutes }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text("\(Fmt.hm(TimeInterval(totalWork * 60))) work · \(Fmt.hm(TimeInterval(totalBreak * 60))) break")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Sample day, starting at:")
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
            }
            .font(.callout)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(schedule.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Circle().fill(item.isBreak ? Color.orange : Color.accentColor).frame(width: 7, height: 7)
                        Text("\(Fmt.time(item.start)) – \(Fmt.time(item.end))").monospacedDigit()
                        Text(item.isBreak ? "Break" : "Work (block \(item.block))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var schedule: [(start: Date, end: Date, isBreak: Bool, block: Int)] {
        var t = startTime
        var out: [(Date, Date, Bool, Int)] = []
        for (i, b) in draft.blocks.enumerated() {
            let w = t.addingTimeInterval(TimeInterval(b.workMinutes * 60))
            out.append((t, w, false, i + 1))
            let br = w.addingTimeInterval(TimeInterval(b.breakMinutes * 60))
            if b.breakMinutes > 0 { out.append((w, br, true, i + 1)) }
            t = br
        }
        return out.map { (start: $0.0, end: $0.1, isBreak: $0.2, block: $0.3) }
    }

    private var footer: some View {
        HStack {
            if draft.isCustom {
                Button("Save as template…") {
                    saveAsName = ""
                    showSaveAs = true
                }
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(request.activateOnSave ? "Save and use" : "Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isCustom && draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        let s = model.store.settings
        if let id = request.presetID, let p = s.allPresets.first(where: { $0.id == id }) {
            draft = p
        } else {
            draft = BreakPreset(name: "", blocks: [PlanBlock(workMinutes: 50, breakMinutes: 10)])
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = draft.blocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < draft.blocks.count else { return }
        withAnimation { draft.blocks.swapAt(i, j) }
    }

    private func sanitized(_ p: BreakPreset) -> BreakPreset {
        var p = p
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.blocks = p.blocks.map { PlanBlock(id: $0.id, workMinutes: min(max($0.workMinutes, 1), 600), breakMinutes: min(max($0.breakMinutes, 0), 480)) }
        if p.blocks.isEmpty { p.blocks = [PlanBlock(workMinutes: 50, breakMinutes: 10)] }
        return p
    }

    private func save() {
        let p = sanitized(draft)
        let wasActive = model.store.settings.activePreset.id == p.id
        model.store.updateSettings {
            $0.upsertPreset(p)
            if request.activateOnSave { $0.activePresetID = p.id }
        }
        // A newly chosen plan starts from its first block; if the active plan itself was edited, progress is kept.
        if request.activateOnSave && !wasActive { model.timer.restartPlan() }
        dismiss()
    }

    private func saveAsTemplate() {
        let name = saveAsName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var p = sanitized(draft)
        p.id = UUID()
        p.name = name
        p.blocks = p.blocks.map { PlanBlock(workMinutes: $0.workMinutes, breakMinutes: $0.breakMinutes) }
        model.store.updateSettings {
            $0.upsertPreset(p)
            $0.activePresetID = p.id
        }
        model.timer.restartPlan()
        dismiss()
    }
}

/// One block row: work and break length (typed or with the arrows).
private struct BlockRow: View {
    let number: Int
    @Binding var block: PlanBlock
    let isLast: Bool
    let canDelete: Bool
    let onDelete: () -> Void
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.18), in: Circle())
            MinutesField(title: "Work", symbol: "hammer", value: $block.workMinutes, range: 1...600)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            MinutesField(title: "Break", symbol: "cup.and.saucer", value: $block.breakMinutes, range: 0...480)
            Spacer(minLength: 0)
            Menu {
                Button("Move up") { onMove(-1) }.disabled(number == 1)
                Button("Move down") { onMove(1) }.disabled(isLast)
                Divider()
                Button("Delete", role: .destructive, action: onDelete).disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text("Block \(number) options"))
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Minutes input: a field you can type into + arrows in 5-minute steps.
struct MinutesField: View {
    let title: LocalizedStringKey
    let symbol: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .accessibilityLabel(Text(title))
            Stepper("", value: $value, in: range, step: 5)
                .labelsHidden()
            Text("min").foregroundStyle(.secondary).font(.callout)
        }
    }
}
