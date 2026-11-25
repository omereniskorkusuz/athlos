import Foundation

/// Where the app data lives on disk: ~/Library/Application Support/Athlos/
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static var standard: AppPaths {
        // The data folder can be changed for testing: ATHLOS_DATA_DIR=/tmp/x
        if let custom = ProcessInfo.processInfo.environment["ATHLOS_DATA_DIR"], !custom.isEmpty {
            return AppPaths(root: URL(fileURLWithPath: custom, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AppPaths(root: base.appendingPathComponent("Athlos", isDirectory: true))
    }

    public var dataFile: URL { root.appendingPathComponent("data.json") }
    public var imagesDir: URL { root.appendingPathComponent("Images", isDirectory: true) }
    public var backupsDir: URL { root.appendingPathComponent("Backups", isDirectory: true) }

    public func ensureDirectories() {
        for dir in [root, imagesDir, backupsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// JSON encoder/decoder (ISO-8601 dates, readable output).
public enum AthlosJSON {
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        // ISO-8601 with milliseconds (the standard .iso8601 drops fractions of a second).
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(style))
        }
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = try? style.parse(s) { return d }
            if let d = try? Date.ISO8601FormatStyle().parse(s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
        }
        return d
    }
}

/// Writes data to disk atomically (an interrupted write leaves the old file intact).
public protocol DataPersisting: AnyObject {
    func load() throws -> AppData?
    func save(_ data: AppData) throws
}

public final class JSONFilePersistence: DataPersisting {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> AppData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let raw = try Data(contentsOf: url)
        return try AthlosJSON.decoder().decode(AppData.self, from: raw)
    }

    public func save(_ data: AppData) throws {
        let raw = try AthlosJSON.encoder().encode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try raw.write(to: url, options: [.atomic])
    }
}
