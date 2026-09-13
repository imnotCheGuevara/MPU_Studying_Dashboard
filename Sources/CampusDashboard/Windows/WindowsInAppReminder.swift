#if os(Windows)
import Foundation

enum WindowsReminderUrgency: Equatable, Sendable {
    case overdue
    case dueWithinHour
    case dueToday
    case upcoming
}

struct WindowsInAppReminder: Identifiable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let title: String
    let dueAt: Date
    let urgency: WindowsReminderUrgency
    let usesConfirmedSuggestion: Bool
}

/// A foreground-only reminder view for the first Windows beta.
///
/// It never schedules an operating-system notification or runs a polling loop.
/// Official due dates win; inferred dates are eligible only after explicit
/// confirmation, preserving the shared product safety boundary.
struct WindowsInAppReminderEngine: Sendable {
    var upcomingWindow: TimeInterval = 7 * 24 * 60 * 60
    var overdueWindow: TimeInterval = 7 * 24 * 60 * 60

    func reminders(in snapshot: DashboardSnapshot, now: Date = Date()) -> [WindowsInAppReminder] {
        snapshot.tasks.compactMap { task in
            guard !task.isLocallyComplete, task.appearsInNormalTaskList else { return nil }

            let dueAt: Date
            let usesConfirmedSuggestion: Bool
            if let officialDueAt = task.officialDueAt {
                dueAt = officialDueAt
                usesConfirmedSuggestion = false
            } else if task.suggestedDateConfirmed, let suggestedCompleteAt = task.suggestedCompleteAt {
                dueAt = suggestedCompleteAt
                usesConfirmedSuggestion = true
            } else {
                return nil
            }

            let interval = dueAt.timeIntervalSince(now)
            guard interval <= upcomingWindow, interval >= -overdueWindow else { return nil }

            let urgency: WindowsReminderUrgency
            if interval < 0 {
                urgency = .overdue
            } else if interval <= 60 * 60 {
                urgency = .dueWithinHour
            } else if interval <= 24 * 60 * 60 {
                urgency = .dueToday
            } else {
                urgency = .upcoming
            }

            return WindowsInAppReminder(
                id: task.id,
                taskID: task.id,
                title: task.title,
                dueAt: dueAt,
                urgency: urgency,
                usesConfirmedSuggestion: usesConfirmedSuggestion
            )
        }
        .sorted { lhs, rhs in
            if lhs.urgency == .overdue, rhs.urgency != .overdue { return true }
            if lhs.urgency != .overdue, rhs.urgency == .overdue { return false }
            return lhs.dueAt < rhs.dueAt
        }
    }
}
#endif
