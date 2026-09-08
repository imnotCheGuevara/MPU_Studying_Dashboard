import Foundation

/// Executes committed side-effect intents through Stage 05 fake boundaries.
/// Rows left in `processing` by a crash are returned to `pending` before work begins.
actor OutboxProcessor {
    private let database: SQLiteDatabase
    private let calendar: any CalendarService
    private let notifications: any NotificationService
    private let clock: any Clock

    init(
        database: SQLiteDatabase,
        calendar: any CalendarService,
        notifications: any NotificationService,
        clock: any Clock = SystemClock()
    ) {
        self.database = database
        self.calendar = calendar
        self.notifications = notifications
        self.clock = clock
    }

    @discardableResult
    func processPending(limit: Int = 100) async -> Int {
        let now = clock.now
        try? database.execute(
            "UPDATE outbox_work SET state = 'pending', updated_at = ? WHERE state = 'processing'",
            bindings: [.real(now.timeIntervalSince1970)]
        )
        guard let rows = try? database.query(
            """
            SELECT * FROM outbox_work
            WHERE state = 'pending' AND available_at <= ?
            ORDER BY created_at, id LIMIT ?
            """,
            bindings: [.real(now.timeIntervalSince1970), .integer(Int64(max(0, limit)))]
        ) else { return 0 }

        var completed = 0
        for row in rows {
            if Task.isCancelled { break }
            guard let id = row.string("id"), let payload = row.data("payload") else { continue }
            do {
                try database.execute(
                    "UPDATE outbox_work SET state = 'processing', updated_at = ? WHERE id = ? AND state = 'pending'",
                    bindings: [.real(now.timeIntervalSince1970), .text(id)]
                )
                let envelope = try JSONDecoder.syncDecoder.decode(OutboxEnvelope.self, from: payload)
                try await apply(envelope)
                try database.execute(
                    "UPDATE outbox_work SET state = 'completed', updated_at = ?, last_error_category = NULL WHERE id = ?",
                    bindings: [.real(clock.now.timeIntervalSince1970), .text(id)]
                )
                completed += 1
            } catch {
                let attempts = Int(row.int("attempt_count") ?? 0) + 1
                let delay = min(pow(2, Double(attempts - 1)) * 60, 3_600)
                try? database.execute(
                    """
                    UPDATE outbox_work SET state = 'pending', attempt_count = ?, available_at = ?,
                      updated_at = ?, last_error_category = 'delivery_failed' WHERE id = ?
                    """,
                    bindings: [
                        .integer(Int64(attempts)), .real(clock.now.addingTimeInterval(delay).timeIntervalSince1970),
                        .real(clock.now.timeIntervalSince1970), .text(id)
                    ]
                )
            }
        }
        return completed
    }

    private func apply(_ envelope: OutboxEnvelope) async throws {
        switch envelope {
        case .calendarUpsert(let objectType, let objectID):
            if let command = try currentCalendarCommand(
                objectType: objectType, objectID: objectID
            ) { _ = try await calendar.apply([command]) }
        case .calendarRemove(let objectType, let objectID):
            _ = try await calendar.apply([.removeBoundEvent(objectType: objectType, objectID: objectID)])
        case .calendarReconcile(let objectType, let objectID):
            if let command = try currentCalendarCommand(
                objectType: objectType, objectID: objectID
            ) { _ = try await calendar.apply([command]) }
        case .notificationNew(let key, let objectID, let at):
            try await notifications.apply([.schedule(key: key, objectID: objectID, at: at)])
        case .notificationCancel(let key):
            try await notifications.apply([.cancel(key: key)])
        }
    }

    /// Calendar outbox work is desired-state based. A task may change after an
    /// intent commits but before it is consumed, especially when an AI date is
    /// immediately undone. Re-evaluating the committed domain row prevents a
    /// stale upsert from creating an ineligible event or retrying forever.
    private func currentCalendarCommand(
        objectType: String, objectID: String
    ) throws -> CalendarCommand? {
        guard objectType == "learning_task" || objectType == "academic_signal" else {
            return .upsert(objectType: objectType, objectID: objectID)
        }
        if objectType == "academic_signal" {
            let row = try database.query(
                "SELECT confirmation_state,adopted_date,inferred_date,is_active,category,adopted_category FROM academic_signals WHERE id=?",
                bindings: [.text(objectID)]
            ).first
            let eligible = row?.int("is_active") == 1
                && (row?.string("adopted_category") ?? row?.string("category"))
                    != AcademicSignalCategory.courseScheduleChange.rawValue
                && ["confirmed", "corrected"].contains(row?.string("confirmation_state") ?? "")
                && (row?.double("adopted_date") != nil || row?.double("inferred_date") != nil)
            if eligible { return .upsert(objectType: objectType, objectID: objectID) }
            let binding = try database.query(
                "SELECT sync_state FROM calendar_bindings WHERE object_type=? AND object_id=?",
                bindings: [.text(objectType), .text(objectID)]).first
            guard let binding, binding.string("sync_state") != "removed" else { return nil }
            return .removeBoundEvent(objectType: objectType, objectID: objectID)
        }
        let row = try database.query(
            """
            SELECT official_due_at, suggested_complete_at, suggestion_confirmed_at, source_state
            FROM learning_tasks WHERE id=?
            """,
            bindings: [.text(objectID)]
        ).first
        let eligible = row?.string("source_state") == "active"
            && (row?.double("official_due_at") != nil
                || (row?.double("suggested_complete_at") != nil
                    && row?.double("suggestion_confirmed_at") != nil))
        if eligible { return .upsert(objectType: objectType, objectID: objectID) }
        let binding = try database.query(
            "SELECT sync_state FROM calendar_bindings WHERE object_type=? AND object_id=?",
            bindings: [.text(objectType), .text(objectID)]
        ).first
        guard let binding, binding.string("sync_state") != "removed" else { return nil }
        return .removeBoundEvent(objectType: objectType, objectID: objectID)
    }
}

private extension JSONDecoder {
    static var syncDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
