import Foundation

enum NotificationAuthorizationState: String, Equatable, Sendable {
    case notDetermined = "not_determined"
    case authorized
    case denied
}

enum CampusNotificationType: String, CaseIterable, Sendable {
    case newAssignment = "new_assignment"
    case newQuiz = "new_quiz"
    case newAnnouncement = "new_announcement"
    case deadlineReminder = "deadline_reminder"
    case classReminder = "class_reminder"
    case syncFailure = "sync_failure"
    case syncRecovery = "sync_recovery"
}

struct NotificationPreferences: Equatable, Sendable {
    var enabled: Bool = false
    var deadlineOffsetsMinutes: [Int] = [1_440, 180, 60]
    var classLeadMinutes: Int = 15
    var quietStartMinutes: Int = 22 * 60
    var quietEndMinutes: Int = 8 * 60
    var policyVersion: Int = 1
}

struct LocalNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

struct NotificationCourseSetting: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool
}

enum NotificationKey {
    static func make(
        objectType: String,
        objectID: String,
        type: CampusNotificationType,
        slot: String,
        policyVersion: Int
    ) -> String {
        let escaped = [objectType, objectID, type.rawValue, slot, "v\(policyVersion)"]
            .map { $0.replacingOccurrences(of: ":", with: "%3A") }
            .joined(separator: ":")
        return "campus:\(escaped)"
    }

    static func dateSlot(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000).rounded()))
    }
}

enum NotificationSchedulingError: Error, Equatable {
    case unavailable
    case invalidPreference
}

protocol UserNotificationCenterClient: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func add(_ request: LocalNotificationRequest) async throws
    func removePending(identifiers: [String]) async
}
