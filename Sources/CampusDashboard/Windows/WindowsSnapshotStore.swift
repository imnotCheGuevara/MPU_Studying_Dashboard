#if os(Windows)
import Foundation

enum WindowsSnapshotStoreError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case unreadableArchive
    case unavailableStorage

    var description: String {
        switch self {
        case .unsupportedSchema:
            "The saved data was created by an incompatible app version"
        case .unreadableArchive:
            "The saved data could not be read safely"
        case .unavailableStorage:
            "The local data folder is unavailable"
        }
    }
}

struct WindowsSnapshotStore: Sendable {
    static let schemaVersion = 1

    private struct Archive: Codable {
        let schemaVersion: Int
        let savedAt: Date
        let snapshot: DashboardSnapshot
    }

    let fileURL: URL

    init(fileURL: URL = WindowsSnapshotStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> DashboardSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let archive = try decoder.decode(Archive.self, from: data)
            guard archive.schemaVersion == Self.schemaVersion else {
                throw WindowsSnapshotStoreError.unsupportedSchema(archive.schemaVersion)
            }
            return archive.snapshot
        } catch let error as WindowsSnapshotStoreError {
            throw error
        } catch {
            throw WindowsSnapshotStoreError.unreadableArchive
        }
    }

    func save(_ snapshot: DashboardSnapshot, now: Date = Date()) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let archive = Archive(schemaVersion: Self.schemaVersion, savedAt: now, snapshot: snapshot)
            try encoder.encode(archive).write(to: fileURL, options: .atomic)
        } catch {
            throw WindowsSnapshotStoreError.unavailableStorage
        }
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw WindowsSnapshotStoreError.unavailableStorage
        }
    }

    static func defaultFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let root: URL
        if let localAppData = environment["LOCALAPPDATA"], !localAppData.isEmpty {
            root = URL(fileURLWithPath: localAppData, isDirectory: true)
        } else if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            root = applicationSupport
        } else {
            root = FileManager.default.temporaryDirectory
        }
        return root
            .appendingPathComponent("CampusDashboard", isDirectory: true)
            .appendingPathComponent("snapshot-v1.json", isDirectory: false)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
#endif
