import Foundation

final class CampusNotificationService: NotificationService, @unchecked Sendable {
    private let database: SQLiteDatabase
    private let center: any UserNotificationCenterClient
    private let clock: any Clock
    private let calendar: Calendar
    private let persistence: NotificationPersistence

    init(
        database: SQLiteDatabase,
        center: any UserNotificationCenterClient,
        clock: any Clock = SystemClock(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.database = database
        self.center = center
        self.clock = clock
        self.calendar = calendar
        persistence = NotificationPersistence(database: database)
    }

    func authorizationState() async -> NotificationAuthorizationState {
        await center.authorizationState()
    }

    /// This is the only production path that may display the notification permission prompt.
    func requestAccessFromUserAction() async throws -> Bool {
        if await center.authorizationState() == .notDetermined {
            _ = try await center.requestAuthorization()
        }
        return await center.authorizationState() == .authorized
    }

    func preferences() throws -> NotificationPreferences { try persistence.preferences() }

    func courseSettings() throws -> [NotificationCourseSetting] {
        try CourseReconciliationService(database: database).reconcile()
        return try database.query(
            """
            SELECT courses.id,courses.name,courses.code,sa.source_kind,
                   mapped.code AS mapped_code,m.canvas_course_id
            FROM courses JOIN source_accounts sa ON sa.id=courses.source_account_id
            LEFT JOIN academic_course_mappings m
              ON m.canvas_course_id=courses.id AND m.is_active=1 AND m.decision_state='confirmed'
            LEFT JOIN courses mapped ON mapped.id=m.siweb_course_id
            WHERE courses.source_state='active' AND LOWER(sa.source_kind) IN ('canvas','siweb')
              AND NOT EXISTS (
                SELECT 1 FROM academic_course_mappings hidden
                WHERE hidden.siweb_course_id=courses.id AND hidden.is_active=1
                  AND hidden.decision_state='confirmed'
              )
            ORDER BY courses.name,courses.id
            """
        ).compactMap { row in
            guard let id = row.string("id"), let name = row.string("name") else { return nil }
            let mappedCode = row.string("mapped_code") ?? ""
            let display = row.string("canvas_course_id") == nil
                ? "\(name) (\(row.string("source_kind") ?? "Source"))"
                : CourseIdentityNormalizer.displayTitle(name: name, code: mappedCode)
            return NotificationCourseSetting(
                id: id, name: display, enabled: (try? persistence.courseEnabled(id)) ?? true
            )
        }
    }

    func updatePreferences(_ preferences: NotificationPreferences) async throws {
        let old = try persistence.preferences()
        var value = preferences
        if old != preferences { value.policyVersion = max(old.policyVersion + 1, preferences.policyVersion) }
        try persistence.save(value, now: clock.now)
        if !value.enabled { await cancelAllPending() }
        else { try await reconcileReminders() }
    }

    func setCourseEnabled(_ enabled: Bool, courseID: String) async throws {
        try persistence.setCourseEnabled(enabled, courseID: courseID, now: clock.now)
        try await reconcileReminders()
    }

    func apply(_ commands: [NotificationCommand]) async throws {
        for command in commands {
            switch command {
            case .schedule(_, let objectID, let at): try await scheduleNewItem(objectID: objectID, observedAt: at)
            case .cancel(let key): await cancel(key: key)
            }
        }
    }

    func reconcileReminders() async throws {
        let preferences = try persistence.preferences()
        guard preferences.enabled, await center.authorizationState() == .authorized else {
            await cancelAllPending()
            return
        }
        var desired: [String: DesiredNotification] = [:]
        try collectTaskReminders(preferences: preferences, into: &desired)
        try collectMeetingReminders(preferences: preferences, into: &desired)

        let active = try database.query(
            """
            SELECT notification_key, notification_type FROM notification_deliveries
            WHERE state = 'scheduled' AND notification_type IN ('deadline_reminder', 'class_reminder')
            """
        )
        let obsolete = active.compactMap { row -> String? in
            guard let key = row.string("notification_key") else { return nil }
            return desired[key] == nil ? key : nil
        }
        await center.removePending(identifiers: obsolete)
        try markCancelled(obsolete)
        for item in desired.values.sorted(by: { $0.key < $1.key }) { try await persistAndSchedule(item) }
    }

    func recordSyncResult(
        sourceAccountID: String,
        sourceName: String,
        errorCategory: String?
    ) async throws {
        let current = try database.query(
            "SELECT * FROM sync_notification_state WHERE source_account_id = ?",
            bindings: [.text(sourceAccountID)]
        ).first
        if let errorCategory {
            let emitted = current?.int("failure_notification_emitted") == 1
            let alreadyActive = current?.int("failure_active") == 1
            let cycle = Int(current?.int("failure_cycle") ?? 0) + (alreadyActive ? 0 : 1)
            let newlyEmitted: Bool
            if emitted { newlyEmitted = true }
            else {
                newlyEmitted = try await scheduleStatus(
                    sourceID: sourceAccountID, sourceName: sourceName, type: .syncFailure,
                    slot: "cycle-\(cycle)",
                    title: "Campus Dashboard sync needs attention",
                    body: "\(sourceName) could not synchronize (\(errorCategory))."
                )
            }
            try database.execute(
                """
                INSERT INTO sync_notification_state
                  (source_account_id, failure_active, failure_notification_emitted,
                   recovery_notification_emitted, failure_cycle, last_error_category, updated_at)
                VALUES (?, 1, ?, 0, ?, ?, ?) ON CONFLICT(source_account_id) DO UPDATE SET
                  failure_active=1, failure_notification_emitted=excluded.failure_notification_emitted,
                  recovery_notification_emitted=0, failure_cycle=excluded.failure_cycle,
                  last_error_category=excluded.last_error_category,
                  updated_at=excluded.updated_at
                """,
                bindings: [
                    .text(sourceAccountID), .integer(newlyEmitted ? 1 : 0),
                    .integer(Int64(cycle)), .text(errorCategory),
                    .real(clock.now.timeIntervalSince1970)
                ]
            )
        } else if current?.int("failure_active") == 1 {
            let recoveryEmitted = current?.int("recovery_notification_emitted") == 1
            let cycle = Int(current?.int("failure_cycle") ?? 0)
            if !recoveryEmitted {
                _ = try await scheduleStatus(
                    sourceID: sourceAccountID, sourceName: sourceName, type: .syncRecovery,
                    slot: "cycle-\(cycle)",
                    title: "Campus Dashboard sync recovered",
                    body: "\(sourceName) is synchronizing again."
                )
            }
            try database.execute(
                """
                UPDATE sync_notification_state SET failure_active=0,
                  failure_notification_emitted=0, recovery_notification_emitted=1,
                  last_error_category=NULL, updated_at=? WHERE source_account_id=?
                """,
                bindings: [.real(clock.now.timeIntervalSince1970), .text(sourceAccountID)]
            )
        } else if current?.int("recovery_notification_emitted") == 1 {
            try database.execute(
                "UPDATE sync_notification_state SET recovery_notification_emitted=0, updated_at=? WHERE source_account_id=?",
                bindings: [.real(clock.now.timeIntervalSince1970), .text(sourceAccountID)]
            )
        }
    }

    func scheduleTestNotification(after delay: TimeInterval = 5) async throws -> String {
        guard try persistence.preferences().enabled,
              await center.authorizationState() == .authorized else {
            throw NotificationSchedulingError.unavailable
        }
        let fire = clock.now.addingTimeInterval(max(1, delay))
        let key = NotificationKey.make(
            objectType: "test", objectID: "synthetic", type: .newAnnouncement,
            slot: NotificationKey.dateSlot(fire), policyVersion: 1
        )
        try await persistAndSchedule(DesiredNotification(
            key: key, objectType: "test", objectID: "synthetic",
            type: .newAnnouncement, fireDate: fire,
            title: "Campus Dashboard test", body: "Synthetic local notification test."
        ))
        return key
    }

    private func scheduleNewItem(objectID: String, observedAt: Date) async throws {
        let preferences = try persistence.preferences()
        guard preferences.enabled, await center.authorizationState() == .authorized,
              clock.now.timeIntervalSince(observedAt) < 86_400 else { return }
        let item: DesiredNotification?
        if let row = try database.query(
            """
            SELECT learning_tasks.id, learning_tasks.title, learning_tasks.normalized_type,
              learning_tasks.official_type, learning_tasks.course_id, courses.name AS course_name
            FROM learning_tasks LEFT JOIN courses ON courses.id = learning_tasks.course_id
            JOIN source_accounts sa ON sa.id=learning_tasks.source_account_id
            WHERE learning_tasks.id = ? AND learning_tasks.source_state = 'active'
              AND LOWER(sa.source_kind) IN ('canvas','siweb')
            """, bindings: [.text(objectID)]
        ).first, try persistence.courseEnabled(row.string("course_id")) {
            let isQuiz = (row.string("normalized_type") ?? row.string("official_type") ?? "")
                .localizedCaseInsensitiveContains("quiz")
            let type: CampusNotificationType = isQuiz ? .newQuiz : .newAssignment
            let fire = adjustedForQuietHours(clock.now.addingTimeInterval(1), preferences: preferences)
            item = DesiredNotification(
                key: NotificationKey.make(
                    objectType: "learning_task", objectID: objectID, type: type,
                    slot: NotificationKey.dateSlot(observedAt), policyVersion: preferences.policyVersion
                ), objectType: "learning_task", objectID: objectID, type: type, fireDate: fire,
                title: isQuiz ? "New quiz" : "New assignment",
                body: conciseBody(title: row.string("title"), course: row.string("course_name"))
            )
        } else if let row = try database.query(
            """
            SELECT announcements.id, announcements.title, announcements.course_id,
              courses.name AS course_name FROM announcements
            LEFT JOIN courses ON courses.id = announcements.course_id
            JOIN source_accounts sa ON sa.id=announcements.source_account_id
            WHERE announcements.id = ? AND announcements.source_state = 'active'
              AND LOWER(sa.source_kind) IN ('canvas','siweb')
            """, bindings: [.text(objectID)]
        ).first, try persistence.courseEnabled(row.string("course_id")) {
            let fire = adjustedForQuietHours(clock.now.addingTimeInterval(1), preferences: preferences)
            item = DesiredNotification(
                key: NotificationKey.make(
                    objectType: "announcement", objectID: objectID, type: .newAnnouncement,
                    slot: NotificationKey.dateSlot(observedAt), policyVersion: preferences.policyVersion
                ), objectType: "announcement", objectID: objectID, type: .newAnnouncement,
                fireDate: fire, title: "New announcement",
                body: conciseBody(title: row.string("title"), course: row.string("course_name"))
            )
        } else { item = nil }
        if let item { try await persistAndSchedule(item) }
    }

    private func collectTaskReminders(
        preferences: NotificationPreferences,
        into desired: inout [String: DesiredNotification]
    ) throws {
        let rows = try database.query(
            """
            SELECT learning_tasks.*, courses.name AS course_name FROM learning_tasks
            LEFT JOIN courses ON courses.id = learning_tasks.course_id
            JOIN source_accounts sa ON sa.id=learning_tasks.source_account_id
            WHERE learning_tasks.source_state = 'active' AND LOWER(sa.source_kind) IN ('canvas','siweb')
            """
        )
        for row in rows where try persistence.courseEnabled(row.string("course_id")) {
            let due: Date?
            if let official = row.double("official_due_at") { due = Date(timeIntervalSince1970: official) }
            else if row.double("suggestion_confirmed_at") != nil,
                    let suggested = row.double("suggested_complete_at") {
                due = Date(timeIntervalSince1970: suggested)
            } else { due = nil }
            guard let due, due > clock.now, let objectID = row.string("id") else { continue }
            for offset in preferences.deadlineOffsetsMinutes {
                let nominal = due.addingTimeInterval(-Double(offset * 60))
                guard nominal > clock.now else { continue }
                let fire = adjustedForQuietHours(nominal, preferences: preferences)
                guard fire > clock.now, fire < due else { continue }
                let key = NotificationKey.make(
                    objectType: "learning_task", objectID: objectID, type: .deadlineReminder,
                    slot: "due-\(NotificationKey.dateSlot(due))-lead-\(offset)",
                    policyVersion: preferences.policyVersion
                )
                desired[key] = DesiredNotification(
                    key: key, objectType: "learning_task", objectID: objectID,
                    type: .deadlineReminder, fireDate: fire, title: "Upcoming deadline",
                    body: conciseBody(title: row.string("title"), course: row.string("course_name"))
                )
            }
        }
    }

    private func collectMeetingReminders(
        preferences: NotificationPreferences,
        into desired: inout [String: DesiredNotification]
    ) throws {
        let rows = try database.query(
            """
            SELECT course_meetings.*, courses.name AS course_name,
              courses.id AS notification_course_id FROM course_meetings
            JOIN courses ON courses.id = course_meetings.course_id
            JOIN source_accounts sa ON sa.id=courses.source_account_id
            WHERE course_meetings.source_state = 'active' AND LOWER(sa.source_kind) IN ('canvas','siweb')
            """
        )
        for row in rows where try persistence.courseEnabled(row.string("notification_course_id")) {
            guard let objectID = row.string("id"), let startValue = row.double("starts_at") else { continue }
            let start = Date(timeIntervalSince1970: startValue)
            let nominal = start.addingTimeInterval(-Double(preferences.classLeadMinutes * 60))
            guard nominal > clock.now else { continue }
            let fire = adjustedForQuietHours(nominal, preferences: preferences)
            guard fire > clock.now, fire < start else { continue }
            let key = NotificationKey.make(
                objectType: "course_meeting", objectID: objectID, type: .classReminder,
                slot: "start-\(NotificationKey.dateSlot(start))-lead-\(preferences.classLeadMinutes)",
                policyVersion: preferences.policyVersion
            )
            desired[key] = DesiredNotification(
                key: key, objectType: "course_meeting", objectID: objectID,
                type: .classReminder, fireDate: fire, title: "Class starts soon",
                body: row.string("course_name") ?? "Upcoming class"
            )
        }
    }

    private func scheduleStatus(
        sourceID: String, sourceName: String, type: CampusNotificationType,
        slot: String, title: String, body: String
    ) async throws -> Bool {
        let preferences = try persistence.preferences()
        guard preferences.enabled, await center.authorizationState() == .authorized else { return false }
        let fire = adjustedForQuietHours(clock.now.addingTimeInterval(1), preferences: preferences)
        let key = NotificationKey.make(
            objectType: "source_account", objectID: sourceID, type: type,
            slot: slot, policyVersion: preferences.policyVersion
        )
        try await persistAndSchedule(DesiredNotification(
            key: key, objectType: "source_account", objectID: sourceID,
            type: type, fireDate: fire, title: title, body: body
        ))
        return true
    }

    private func persistAndSchedule(_ item: DesiredNotification) async throws {
        guard item.fireDate > clock.now else { return }
        let existing = try database.query(
            "SELECT state FROM notification_deliveries WHERE notification_key = ?",
            bindings: [.text(item.key)]
        ).first
        guard existing == nil else { return }
        try await center.add(LocalNotificationRequest(
            identifier: item.key, title: item.title, body: item.body, fireDate: item.fireDate
        ))
        try database.execute(
            """
            INSERT INTO notification_deliveries
              (notification_key, object_type, object_id, notification_type, scheduled_at,
               state, system_notification_id, updated_at)
            VALUES (?, ?, ?, ?, ?, 'scheduled', ?, ?)
            ON CONFLICT(notification_key) DO NOTHING
            """,
            bindings: [
                .text(item.key), .text(item.objectType), .text(item.objectID), .text(item.type.rawValue),
                .real(item.fireDate.timeIntervalSince1970), .text(item.key),
                .real(clock.now.timeIntervalSince1970)
            ]
        )
    }

    private func cancel(key: String) async {
        var keys = [key]
        if let objectID = key.split(separator: ":").last.map(String.init),
           let rows = try? database.query(
            "SELECT notification_key FROM notification_deliveries WHERE object_id = ? AND state = 'scheduled'",
            bindings: [.text(objectID)]
           ) {
            keys.append(contentsOf: rows.compactMap { $0.string("notification_key") })
        }
        let unique = Array(Set(keys))
        await center.removePending(identifiers: unique)
        try? markCancelled(unique)
    }

    private func cancelAllPending() async {
        let keys = (try? database.query(
            "SELECT notification_key FROM notification_deliveries WHERE state = 'scheduled'"
        ).compactMap { $0.string("notification_key") }) ?? []
        await center.removePending(identifiers: keys)
        try? markCancelled(keys)
    }

    private func markCancelled(_ keys: [String]) throws {
        for key in keys {
            try database.execute(
                "UPDATE notification_deliveries SET state='cancelled', updated_at=? WHERE notification_key=?",
                bindings: [.real(clock.now.timeIntervalSince1970), .text(key)]
            )
        }
    }

    private func adjustedForQuietHours(_ date: Date, preferences: NotificationPreferences) -> Date {
        let start = preferences.quietStartMinutes
        let end = preferences.quietEndMinutes
        guard start != end else { return date }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let quiet = start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
        guard quiet else { return date }
        let sameDayEnd = calendar.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: date) ?? date
        if start < end || minute < end { return sameDayEnd > date ? sameDayEnd : nextDayEnd(after: date, end: end) }
        return nextDayEnd(after: date, end: end)
    }

    private func nextDayEnd(after date: Date, end: Int) -> Date {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        return calendar.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: nextDay) ?? nextDay
    }

    private func conciseBody(title: String?, course: String?) -> String {
        [course, title].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return String(value.prefix(120))
        }.joined(separator: " · ")
    }
}

private struct DesiredNotification {
    let key: String
    let objectType: String
    let objectID: String
    let type: CampusNotificationType
    let fireDate: Date
    let title: String
    let body: String
}
