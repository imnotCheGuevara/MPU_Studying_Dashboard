import Foundation

enum BackgroundRunReason: String, Equatable, Sendable {
    case manual
    case scheduled
    case launchRecovery = "launch_recovery"
    case wakeRecovery = "wake_recovery"
    case networkRecovery = "network_recovery"
    case development
}

enum BackgroundItemState: String, Equatable, Sendable {
    case enabled
    case requiresApproval = "requires_approval"
    case disabled
    case unavailable
}

struct BackgroundScheduleConfiguration: Equatable, Sendable {
    var enabled: Bool
    var targetInterval: TimeInterval
    var lastAttemptAt: Date?
    var lastCompletedAt: Date?
    var lastTrigger: String?
    var lastResult: String?
    var lastErrorCategory: String?
}

struct ScheduledSourceResult: Equatable, Sendable {
    let sourceAccountID: String
    let sourceName: String
    let errorCategory: String?
}

protocol ScheduledSyncRunner: Sendable {
    func run(trigger: SyncTrigger) async -> [ScheduledSourceResult]
}

protocol SourceScopedScheduledSyncRunner: ScheduledSyncRunner {
    func run(trigger: SyncTrigger, source: SourceKind) async -> [ScheduledSourceResult]
}

protocol BackgroundItemControlling: Sendable {
    func state() -> BackgroundItemState
    func setEnabled(_ enabled: Bool) throws
}
