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
        try database.execute(
            """
            INSERT INTO course_notification_preferences(course_id, enabled, updated_at)
            VALUES (?, ?, ?) ON CONFLICT(course_id) DO UPDATE SET
              enabled=excluded.enabled, updated_at=excluded.updated_at
            """,
            bindings: [.text(courseID), .integer(enabled ? 1 : 0), .real(now.timeIntervalSince1970)]
        )
    }

    func courseEnabled(_ courseID: String?) throws -> Bool {
        guard let courseID else { return true }
        return try database.query(
            "SELECT enabled FROM course_notification_preferences WHERE course_id = ?",
            bindings: [.text(courseID)]
        ).first?.int("enabled") != 0
    }
}
