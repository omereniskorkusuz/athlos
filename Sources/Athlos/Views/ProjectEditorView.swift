import SwiftUI
import UniformTypeIdentifiers
import AthlosCore

/// Create / edit a project. Time and dates can be entered by hand for projects you already finished.
struct ProjectEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ProjectEditorRequest

    enum IconKind: String, CaseIterable { case symbol, emoji, image }

    @State private var name = ""
    @State private var iconKind: IconKind = .symbol
    @State private var emoji = "🚀"
    @State private var symbol = "folder.fill"
    @State private var imageName: String?
    @State private var color = Color(hex: Palette.colors[0])
    @State private var manualHours = 0
    @State private var manualMinutes = 0
    @State private var completed = false
    @State private var createdAt = Date()
    @State private var completedAt = Date()
    @State private var showImporter = false
    @State private var dropTargeted = false
    @State private var error: String?

    private let symbols = ["folder.fill", "hammer.fill", "server.rack", "terminal.fill", "book.fill", "paintbrush.fill",
                           "cpu.fill", "globe", "graduationcap.fill", "briefcase.fill", "music.note", "camera.fill",
                           "gamecontroller.fill", "leaf.fill", "heart.fill", "star.fill", "bolt.fill", "chevron.left.forwardslash.chevron.right"]

    private var isNew: Bool { request.project == nil }

    private var currentIcon: ProjectIcon {
        switch iconKind {
        case .emoji: .emoji(emoji.isEmpty ? "🚀" : String(emoji.prefix(2)))
        case .symbol: .symbol(symbol)
        case .image: imageName.map { .image($0) } ?? .symbol(symbol)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ProjectIconView(icon: currentIcon, color: color, size: 56, images: model.store.images)
                        TextField("Project name", text: $name, prompt: Text("e.g. Kenshell"))
                            .font(.title3)
                    }
                }
                Section("Icon") {
                    Picker("Type", selection: $iconKind) {
                        Text("SF Symbol").tag(IconKind.symbol)
                        Text("Emoji").tag(IconKind.emoji)
                        Text("Image / Logo").tag(IconKind.image)
                    }
                    .pickerStyle(.segmented)
                    switch iconKind {
                    case .symbol:
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 9), spacing: 8) {
                            ForEach(symbols, id: \.self) { s in
                                Button { symbol = s } label: {
                                    Image(systemName: s)
                                        .frame(width: 30, height: 30)
                                        .background(symbol == s ? color.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(s)
                            }
                        }
                        TextField("Symbol name", text: $symbol).font(.caption.monospaced())
                    case .emoji:
                        TextField("Emoji", text: $emoji)
                        Text("Tip: press ⌃⌘Space to open the emoji picker.").font(.caption).foregroundStyle(.secondary)
                    case .image:
                        imageDropZone
                    }
                    ColorPickerRow(color: $color)
                }
                Section {
                    Toggle("Finished", isOn: $completed)
                    DatePicker("Start date", selection: $createdAt, displayedComponents: .date)
                    if completed {
                        DatePicker("Completion date", selection: $completedAt, in: createdAt..., displayedComponents: .date)
                    }
                    HStack {
                        Text("Past time outside the app")
                        Spacer()
                        TextField("", value: $manualHours, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
                        Text("h")
                        TextField("", value: $manualMinutes, format: .number).frame(width: 44).multilineTextAlignment(.trailing)
                        Text("min")
                    }
                } header: {
                    Text("Status and history")
                } footer: {
                    Text("When adding a project you finished earlier, enter the total time you spent on it here (e.g. 19 h); it is added to the totals.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 520, height: 640)
        .onAppear(perform: load)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { importImage(url) }
        }
    }

    private var imageDropZone: some View {
        VStack(spacing: 10) {
            if let imageName {
                ProjectIconView(icon: .image(imageName), color: color, size: 96, images: model.store.images)
            } else {
                Image(systemName: "photo.badge.plus").font(.system(size: 36)).foregroundStyle(.secondary)
            }
            Text("Drop a logo here").font(.callout)
            Button("Choose file…") { showImporter = true }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4)))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            importImage(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private func importImage(_ url: URL) {
        guard let images = model.store.images else { return }
        do {
            // The image is scaled down to 512 px and copied as PNG (so big files don't bloat the folder).
            if let data = ImageResizer.pngData(from: url, maxSide: 512) {
                imageName = try images.importData(data, ext: "png")
            } else {
                imageName = try images.importFile(at: url)
            }
            iconKind = .image
            error = nil
        } catch {
            self.error = String(localized: "Could not copy the image: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let p = request.project else {
            completed = request.startCompleted
            color = Color(hex: Palette.colors[model.store.projects.count % Palette.colors.count])
            return
        }
        name = p.name
        color = p.color
        switch p.icon {
        case .emoji(let e): iconKind = .emoji; emoji = e
        case .symbol(let s): iconKind = .symbol; symbol = s
        case .image(let n): iconKind = .image; imageName = n
        }
        manualHours = Int(p.manualSeconds) / 3600
        manualMinutes = (Int(p.manualSeconds) % 3600) / 60
        completed = p.status == .completed
        createdAt = p.createdAt
        completedAt = p.completedAt ?? Date()
    }

    private func save() {
        let manual = TimeInterval(max(0, manualHours) * 3600 + max(0, manualMinutes) * 60)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var p = request.project {
            p.name = trimmed
            p.icon = currentIcon
            p.colorHex = color.hexString
            p.manualSeconds = manual
            p.createdAt = createdAt
            p.status = completed ? .completed : .active
            p.completedAt = completed ? completedAt : nil
            model.store.updateProject(p)
        } else {
            var p = model.store.addProject(name: trimmed, icon: currentIcon, colorHex: color.hexString, manualSeconds: manual,
                                           status: completed ? .completed : .active, createdAt: createdAt)
            if completed {
                p.completedAt = completedAt
                model.store.updateProject(p)
            } else {
                model.expandedNodes.insert(p.id)
                model.treeSelection = .project(p.id)
                if model.route == .settings || model.route == .stats { model.route = .projects }
            }
        }
        dismiss()
    }
}

struct ColorPickerRow: View {
    @Binding var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("Color")
            Spacer()
            ForEach(Palette.colors, id: \.self) { hex in
                Button { color = Color(hex: hex) } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.primary, lineWidth: color.hexString == hex ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Color \(hex)"))
            }
            ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
        }
    }
}

/// Scales images down and converts them to PNG (AppKit).
enum ImageResizer {
    static func pngData(from url: URL, maxSide: CGFloat) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
