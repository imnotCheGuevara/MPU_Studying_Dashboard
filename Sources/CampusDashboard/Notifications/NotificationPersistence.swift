import Foundation

struct NotificationPersistence: Sendable {
    let database: SQLiteDatabase

    func preferences() throws -> NotificationPreferences {
        guard let row = try database.query(
            "SELECT * FROM notification_preferences WHERE singleton_key = 1"
        ).first else { throw NotificationSchedulingError.unavailable }
        let offsets = (row.string("deadline_offsets_minutes") ?? "")
            .split(separator: ",").compactMap { Int($0) }.filter { $0 > 0 }
        return NotificationPreferences(
            enabled: row.int("enabled") == 1,
            deadlineOffsetsMinutes: offsets,
            classLeadMinutes: Int(row.int("class_lead_minutes") ?? 15),
            quietStartMinutes: Int(row.int("quiet_start_minutes") ?? 1_320),
            quietEndMinutes: Int(row.int("quiet_end_minutes") ?? 480),
            policyVersion: Int(row.int("policy_version") ?? 1)
        )
    }

    func save(_ value: NotificationPreferences, now: Date) throws {
        guard value.deadlineOffsetsMinutes.allSatisfy({ $0 > 0 }), value.classLeadMinutes > 0,
              (0..<1_440).contains(value.quietStartMinutes),
              (0..<1_440).contains(value.quietEndMinutes)
        else { throw NotificationSchedulingError.invalidPreference }
        let offsets = Array(Set(value.deadlineOffsetsMinutes)).sorted(by: >)
        try database.execute(
            """
            UPDATE notification_preferences SET enabled = ?, deadline_offsets_minutes = ?,
              class_lead_minutes = ?, quiet_start_minutes = ?, quiet_end_minutes = ?,
              policy_version = ?, updated_at = ? WHERE singleton_key = 1
            """,
            bindings: [
                .integer(value.enabled ? 1 : 0), .text(offsets.map(String.init).joined(separator: ",")),
                .integer(Int64(value.classLeadMinutes)), .integer(Int64(value.quietStartMinutes)),
                .integer(Int64(value.quietEndMinutes)), .integer(Int64(value.policyVersion)),
                .real(now.timeIntervalSince1970)
            ]
        )
    }

    func setCourseEnabled(_ enabled: Bool, courseID: String, now: Date) throws {
        let courseIDs = try notificationCourseIDs(for: courseID)
        try database.transaction {
            for id in courseIDs {
                try database.execute(
                    """
                    INSERT INTO course_notification_preferences(course_id, enabled, updated_at)
                    VALUES (?, ?, ?) ON CONFLICT(course_id) DO UPDATE SET
                      enabled=excluded.enabled, updated_at=excluded.updated_at
                    """,
                    bindings: [.text(id), .integer(enabled ? 1 : 0), .real(now.timeIntervalSince1970)]
                )
            }
        }
    }

    func courseEnabled(_ courseID: String?) throws -> Bool {
        guard let courseID else { return true }
        let courseIDs = try notificationCourseIDs(for: courseID)
        let placeholders = courseIDs.map { _ in "?" }.joined(separator: ",")
        let rows = try database.query(
            "SELECT enabled FROM course_notification_preferences WHERE course_id IN (\(placeholders)) ORDER BY updated_at DESC LIMIT 1",
            bindings: courseIDs.map(SQLiteValue.text)
        )
        return rows.first?.int("enabled") != 0
    }

    private func notificationCourseIDs(for courseID: String) throws -> [String] {
        let row = try database.query(
            """
            SELECT canvas_course_id,siweb_course_id FROM academic_course_mappings
            WHERE is_active=1 AND decision_state='confirmed'
              AND (canvas_course_id=? OR siweb_course_id=?) LIMIT 1
            """, bindings: [.text(courseID), .text(courseID)]
        ).first
        guard let row, let canvas = row.string("canvas_course_id"),
              let siweb = row.string("siweb_course_id") else { return [courseID] }
        return [canvas, siweb]
    }
}
