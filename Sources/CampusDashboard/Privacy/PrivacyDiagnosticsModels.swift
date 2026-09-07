import Foundation

enum LocalDataCategory: String, CaseIterable, Identifiable, Sendable {
    case sourceCache = "Source cache"
    case localUserState = "Local completion and read state"
    case syncHistory = "Sync history"
    case aiHistory = "AI suggestions and history"
    case notificationHistory = "Notification delivery history"

    var id: Self { self }

    var explanation: String {
        switch self {
        case .sourceCache: "Removes locally cached source records. Credentials and Apple Calendar events are retained."
        case .localUserState: "Removes local completion, read, hidden, and priority state only."
        case .syncHistory: "Removes completed synchronization and change history only."
        case .aiHistory: "Removes AI parse results, decisions, and audit history only."
        case .notificationHistory: "Removes completed notification delivery records only; scheduled reminders remain managed."
        }
    }
}

struct LocalDataClearResult: Equatable, Sendable {
    let category: LocalDataCategory
    let deletedRows: Int
}

enum SourceHealthCategory: String, Codable, Sendable {
    case ready
    case notConfigured = "not_configured"
    case authorizationRequired = "authorization_required"
    case permissionDenied = "permission_denied"
    case offline
    case rateLimited = "rate_limited"
    case sourceChanged = "source_changed"
    case serviceUnavailable = "service_unavailable"
    case cancelled
    case failed
}

struct DiagnosticSourceHealth: Identifiable, Equatable, Codable, Sendable {
    var id: String { source }
    let source: String
    let category: SourceHealthCategory
    let lastSuccessfulSync: Date?
    let message: String
    let recoveryAction: String
}

struct SubsystemHealth: Identifiable, Equatable, Codable, Sendable {
    var id: String { subsystem }
    let subsystem: String
    let category: String
    let recoveryAction: String
}

struct DiagnosticSnapshot: Equatable, Codable, Sendable {
    let formatVersion: Int
    let generatedAt: Date
    let databaseSchemaVersion: Int
    let sources: [DiagnosticSourceHealth]
    let subsystems: [SubsystemHealth]
    let aggregateCounts: [String: Int]
    let deepSeekDirectHTTPS: Bool
}

struct CalendarCleanupItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let objectType: String
    let objectID: String
    let title: String
    let startsAt: Date
}

enum PrivacyDiagnosticsError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidExportLocation
    case credentialClearFailed
    case diagnosticExportFailed

    var description: String {
        switch self {
        case .invalidExportLocation: "Choose a local file location for the diagnostic export."
        case .credentialClearFailed: "One or more Keychain items could not be cleared. Try again after unlocking Keychain."
        case .diagnosticExportFailed: "The redacted diagnostic report could not be exported."
        }
    }
}
