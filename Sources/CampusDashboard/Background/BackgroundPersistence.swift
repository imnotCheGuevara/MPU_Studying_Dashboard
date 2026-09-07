import Foundation

struct BackgroundPersistence: Sendable {
    let database: SQLiteDatabase

    func load() throws -> BackgroundScheduleConfiguration {
        guard let row = try database.query(
            "SELECT * FROM background_schedule_state WHERE singleton_key=1"
        ).first else { throw NotificationSchedulingError.unavailable }
        return BackgroundScheduleConfiguration(
            enabled: row.int("enabled") == 1,
            targetInterval: row.double("target_interval_seconds") ?? 3_600,
            lastAttemptAt: row.double("last_attempt_at").map(Date.init(timeIntervalSince1970:)),
            lastCompletedAt: row.double("last_completed_at").map(Date.init(timeIntervalSince1970:)),
            lastTrigger: row.string("last_trigger"), lastResult: row.string("last_result"),
            lastErrorCategory: row.string("last_error_category")
        )
    }

    func setEnabled(_ enabled: Bool, targetInterval: TimeInterval, now: Date) throws {
        try database.execute(
            """
            UPDATE background_schedule_state SET enabled=?, target_interval_seconds=?, updated_at=?
            WHERE singleton_key=1
            """,
            bindings: [
                .integer(enabled ? 1 : 0), .real(max(1, targetInterval)),
                .real(now.timeIntervalSince1970)
            ]
        )
    }

    func recordStart(reason: BackgroundRunReason, now: Date) throws {
        try database.execute(
            """
            UPDATE background_schedule_state SET last_attempt_at=?, last_trigger=?,
              last_result='running', last_error_category=NULL, updated_at=? WHERE singleton_key=1
            """,
            bindings: [
                .real(now.timeIntervalSince1970), .text(reason.rawValue),
                .real(now.timeIntervalSince1970)
            ]
        )
    }

    func recordFinish(results: [ScheduledSourceResult], now: Date) throws {
        let errors = results.compactMap(\.errorCategory)
        let result = errors.isEmpty ? "succeeded" : (errors.count == results.count ? "failed" : "partial")
        let completed = errors.isEmpty
        try database.execute(
            """
            UPDATE background_schedule_state SET
              last_completed_at=CASE WHEN ? = 1 THEN ? ELSE last_completed_at END, last_result=?,
              last_error_category=?, updated_at=? WHERE singleton_key=1
            """,
            bindings: [
                .integer(completed ? 1 : 0), .real(now.timeIntervalSince1970), .text(result),
                errors.first.map(SQLiteValue.text) ?? .null, .real(now.timeIntervalSince1970)
            ]
        )
    }
}
