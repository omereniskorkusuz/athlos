import Foundation

/// Copies project logos into the app folder and manages them.
public final class ImageStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    /// Copies the file and returns the new file name.
    public func importFile(at source: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: url(for: name))
        return name
    }

    /// Saves raw data (e.g. a PNG from drag and drop).
    public func importData(_ data: Data, ext: String = "png") throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    public func data(for name: String) -> Data? { try? Data(contentsOf: url(for: name)) }

    public func delete(_ name: String) { try? FileManager.default.removeItem(at: url(for: name)) }
}

/// An exported backup file: all data + (optionally) the logo images.
public struct BackupFile: Codable, Sendable {
    public var app = "Athlos"
    public var exportedAt: Date
    public var data: AppData
    /// file name → image data (base64 in JSON).
    public var images: [String: Data]

    public init(exportedAt: Date, data: AppData, images: [String: Data] = [:]) {
        self.exportedAt = exportedAt
        self.data = data
        self.images = images
    }
}

public enum BackupError: LocalizedError {
    case invalidFile

    public var errorDescription: String? {
        switch self {
        case .invalidFile: "This file is not a valid Athlos backup."
        }
    }
}

/// JSON export/import and a daily automatic backup (the last 7 are kept).
@MainActor
public enum BackupService {
    public static let keepCount = 7

    public static func makeBackup(store: AppStore, includeImages: Bool, now: Date = Date()) -> BackupFile {
        var images: [String: Data] = [:]
        if includeImages, let imageStore = store.images {
            for p in store.projects {
                if case .image(let name) = p.icon, let d = imageStore.data(for: name) { images[name] = d }
            }
        }
        return BackupFile(exportedAt: now, data: store.snapshot, images: images)
    }

    public static func encode(_ backup: BackupFile) throws -> Data {
        try AthlosJSON.encoder(pretty: true).encode(backup)
    }

    /// Decodes a backup file. Also accepts raw files that only contain `AppData`.
    public static func decode(_ raw: Data) throws -> BackupFile {
        let decoder = AthlosJSON.decoder()
        if let b = try? decoder.decode(BackupFile.self, from: raw) { return b }
        if let d = try? decoder.decode(AppData.self, from: raw) { return BackupFile(exportedAt: Date(), data: d) }
        throw BackupError.invalidFile
    }

    /// Import: the current data is fully replaced by the backup. Images are written back to the folder.
    public static func restore(_ backup: BackupFile, into store: AppStore) {
        if let imageStore = store.images {
            for (name, data) in backup.images where !FileManager.default.fileExists(atPath: imageStore.url(for: name).path) {
                try? data.write(to: imageStore.url(for: name), options: .atomic)
            }
        }
        var data = backup.data
        // If the imported data has a running entry, its state is kept (the recovery screen asks).
        data.runtime.lastAutoBackupDay = store.runtime.lastAutoBackupDay
        store.replaceAll(with: data)
    }

    /// Makes one automatic backup a day and deletes all but the newest `keepCount` files.
    /// - Returns: the file written (nil if today's backup already exists).
    @discardableResult
    public static func autoBackupIfNeeded(store: AppStore, directory: URL, now: Date = Date(),
                                          calendar: Calendar = .current) -> URL? {
        guard store.settings.autoBackupEnabled else { return nil }
        let today = calendar.startOfDay(for: now)
        if let last = store.runtime.lastAutoBackupDay, calendar.isDate(last, inSameDayAs: today) { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateFormat = "yyyy-MM-dd"
            let url = directory.appendingPathComponent("athlos-\(f.string(from: now)).json")
            try encode(makeBackup(store: store, includeImages: false, now: now)).write(to: url, options: .atomic)
            store.updateRuntime { $0.lastAutoBackupDay = today }
            prune(directory: directory)
            return url
        } catch {
            return nil
        }
    }

    /// Keeps the newest `keepCount` backups in the folder.
    public static func prune(directory: URL, keep: Int = keepCount) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let backups = files.filter { $0.lastPathComponent.hasPrefix("athlos-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // sorted by name because the name contains the date
        for old in backups.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }
}
