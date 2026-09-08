import Foundation

actor SourceSingleFlight {
    private var active: Set<SourceKind> = []

    func run<T: Sendable>(
        source: SourceKind,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard active.insert(source).inserted else {
            throw SyncEngineError(category: .alreadyRunning, retryable: false)
        }
        defer { active.remove(source) }
        return try await operation()
    }
}

final class DeterministicSyncEngine: SyncService, @unchecked Sendable {
    typealias TransactionFault = @Sendable () throws -> Void

    private let database: SQLiteDatabase
    private let accounts: [SourceKind: SyncSourceAccount]
    private let readers: [SourceKind: any SyncSourceReader]
    private let clock: any Clock
    private let idGenerator: any IDGenerator
    private let transactionFault: TransactionFault?
    private let flights = SourceSingleFlight()

    init(
        database: SQLiteDatabase,
        accounts: [SyncSourceAccount],
        readers: [any SyncSourceReader],
        clock: any Clock = SystemClock(),
        idGenerator: any IDGenerator = SystemIDGenerator(),
        transactionFault: TransactionFault? = nil
    ) {
        self.database = database
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.source, $0) })
        self.readers = Dictionary(uniqueKeysWithValues: readers.map { ($0.source, $0) })
        self.clock = clock
        self.idGenerator = idGenerator
        self.transactionFault = transactionFault
    }

    func synchronize(source: SourceKind, trigger: SyncTrigger) async throws -> SyncSummary {
        try await flights.run(source: source) { [self] in
            try await synchronizeSingle(source: source, trigger: trigger)
        }
    }

    func synchronizeAll(trigger: SyncTrigger) async -> [SourceSyncOutcome] {
        await withTaskGroup(of: SourceSyncOutcome.self) { group in
            for source in SourceKind.allCases where accounts[source] != nil && readers[source] != nil {
                group.addTask { [self] in
                    do {
                        return SourceSyncOutcome(
                            source: source,
                            result: .success(try await synchronize(source: source, trigger: trigger))
                        )
                    } catch let error as SyncEngineError {
                        return SourceSyncOutcome(source: source, result: .failure(error))
                    } catch {
                        return SourceSyncOutcome(
                            source: source,
                            result: .failure(SyncEngineError(category: .unknown, retryable: false))
                        )
                    }
                }
            }
            var results: [SourceSyncOutcome] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.source.rawValue < $1.source.rawValue }
        }
    }

    private func synchronizeSingle(source: SourceKind, trigger: SyncTrigger) async throws -> SyncSummary {
        guard let account = accounts[source], let reader = readers[source] else {
            throw SyncEngineError(category: .unknown, retryable: false)
        }
        let runID = idGenerator.next()
        let startedAt = clock.now
        do {
            let account = try ensureAccount(account, at: startedAt)
            let snapshot = try await reader.read()
            try Task.checkCancellation()
            let summary = try apply(
                snapshot: snapshot, account: account, trigger: trigger,
                runID: runID, startedAt: startedAt, finishedAt: clock.now
            )
            return summary
        } catch {
            let classified = classify(error)
            try? recordFailedRun(
                id: runID, account: account, trigger: trigger, startedAt: startedAt,
                finishedAt: clock.now, error: classified
            )
            throw classified
        }
    }

    private func ensureAccount(_ account: SyncSourceAccount, at date: Date) throws -> SyncSourceAccount {
        try database.execute(
            """
            INSERT INTO source_accounts
              (id, source_kind, instance_url, display_name, authorization_state, capabilities_json,
               last_successful_sync, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'authorized', '{}', NULL, ?, ?)
            ON CONFLICT(source_kind, instance_url) DO UPDATE SET
              display_name = excluded.display_name, updated_at = excluded.updated_at
            """,
            bindings: [
                .text(account.id.uuidString), .text(account.source.rawValue), .text(account.instanceURL),
                .text(account.displayName), .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970)
            ]
        )
        guard let idString = try database.query(
            "SELECT id FROM source_accounts WHERE source_kind = ? AND instance_url = ?",
            bindings: [.text(account.source.rawValue), .text(account.instanceURL)]
        ).first?.string("id"), let id = UUID(uuidString: idString) else {
            throw SyncEngineError(category: .persistence, retryable: true)
        }
        return SyncSourceAccount(
            id: id, source: account.source, instanceURL: account.instanceURL, displayName: account.displayName
        )
    }

    private func apply(
        snapshot: SyncSnapshot,
        account: SyncSourceAccount,
        trigger: SyncTrigger,
        runID: UUID,
        startedAt: Date,
        finishedAt: Date
    ) throws -> SyncSummary {
        var counters = Counters()
        let taskBaselineComplete = try isBaselineComplete(type: .learningTask, accountID: account.id)
        let announcementBaselineComplete = try isBaselineComplete(type: .announcement, accountID: account.id)

        try database.transaction {
            for rawRecord in snapshot.rawRecords {
                try Task.checkCancellation()
                try saveRawRecord(rawRecord, account: account, runID: runID, at: finishedAt)
            }
            for course in snapshot.courses {
                try Task.checkCancellation()
                if snapshot.rawRecords.isEmpty { try saveRaw(course, account: account, runID: runID, at: finishedAt) }
                try apply(course, account: account, runID: runID, at: finishedAt, counters: &counters)
            }
            for meeting in snapshot.meetings {
                try Task.checkCancellation()
                if snapshot.rawRecords.isEmpty { try saveRaw(meeting, account: account, runID: runID, at: finishedAt) }
                try apply(meeting, account: account, runID: runID, at: finishedAt, counters: &counters)
            }
            for task in snapshot.tasks {
                try Task.checkCancellation()
                if snapshot.rawRecords.isEmpty { try saveRaw(task, account: account, runID: runID, at: finishedAt) }
                try apply(
                    task, account: account, runID: runID, at: finishedAt,
                    suppressNewNotification: !taskBaselineComplete, counters: &counters
                )
            }
            for announcement in snapshot.announcements {
                try Task.checkCancellation()
                if snapshot.rawRecords.isEmpty { try saveRaw(announcement, account: account, runID: runID, at: finishedAt) }
                try apply(
                    announcement, account: account, runID: runID, at: finishedAt,
                    suppressNewNotification: !announcementBaselineComplete, counters: &counters
                )
            }
            for type in snapshot.completeObjectTypes {
                try Task.checkCancellation()
                try applyAbsenceEvidence(
                    type: type, observed: observedIDs(type, in: snapshot), account: account,
                    runID: runID, at: finishedAt, counters: &counters
                )
                try completeBaseline(type: type, account: account, runID: runID, at: finishedAt)
            }
            try transactionFault?()
            try database.execute(
                """
                INSERT INTO sync_runs
                  (id, trigger_kind, source_account_id, fetch_state, normalize_state, persistence_state,
                   read_count, inserted_count, updated_count, cancelled_count, started_at, finished_at)
                VALUES (?, ?, ?, 'succeeded', 'succeeded', 'committed', ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(runID.uuidString), .text(trigger.rawValue), .text(account.id.uuidString),
                    .integer(Int64(snapshot.readCount)), .integer(Int64(counters.inserted)),
                    .integer(Int64(counters.updated)), .integer(Int64(counters.cancelled)),
                    .real(startedAt.timeIntervalSince1970), .real(finishedAt.timeIntervalSince1970)
                ]
            )
            try database.execute(
                "UPDATE source_accounts SET last_successful_sync = ?, updated_at = ? WHERE id = ?",
                bindings: [
                    .real(finishedAt.timeIntervalSince1970), .real(finishedAt.timeIntervalSince1970),
                    .text(account.id.uuidString)
                ]
            )
        }
        return SyncSummary(
            source: account.source, readCount: snapshot.readCount, insertedCount: counters.inserted,
            updatedCount: counters.updated, cancelledCount: counters.cancelled
        )
    }

    private func apply(
        _ value: NormalizedCourse, account: SyncSourceAccount, runID: UUID,
        at date: Date, counters: inout Counters
    ) throws {
        let existing = try row(type: .course, accountID: account.id, sourceID: value.sourceObjectID)
        let id = existing?.string("id") ?? idGenerator.next().uuidString
        let oldState = existing?.string("source_state")
        let changes = changesForCourse(existing, value)
        try database.execute(
            """
            INSERT INTO courses
              (id, source_account_id, source_object_id, name, code, term, time_zone, source_url,
               source_state, first_seen_at, last_seen_at, source_updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?)
            ON CONFLICT(source_account_id, source_object_id) DO UPDATE SET
              name=excluded.name, code=excluded.code, term=excluded.term, time_zone=excluded.time_zone,
              source_url=excluded.source_url, source_state='active', last_seen_at=excluded.last_seen_at,
              source_updated_at=excluded.source_updated_at
            """,
            bindings: [
                .text(id), .text(account.id.uuidString), .text(value.sourceObjectID), .text(value.name),
                .text(value.code), .text(value.term), .text(value.timeZone), optionalText(value.sourceURL),
                .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970)
            ]
        )
        try resetPresence(type: .course, sourceID: value.sourceObjectID, account: account, runID: runID, at: date)
        try record(changes, type: .course, objectID: id, at: date)
        count(existing: existing, changes: changes, oldState: oldState, newState: "active", counters: &counters)
    }

    private func apply(
        _ value: NormalizedMeeting, account: SyncSourceAccount, runID: UUID,
        at date: Date, counters: inout Counters
    ) throws {
        guard let courseID = try domainID(type: .course, accountID: account.id, sourceID: value.courseSourceObjectID) else {
            throw SyncEngineError(category: .malformedResponse, retryable: false)
        }
        let existing = try row(type: .courseMeeting, accountID: account.id, sourceID: value.sourceObjectID)
        let id = existing?.string("id") ?? idGenerator.next().uuidString
        let oldState = existing?.string("source_state")
        let changes = changesForMeeting(existing, value)
        try database.execute(
            """
            INSERT INTO course_meetings
              (id, course_id, source_object_id, starts_at, ends_at, is_all_day, original_time_zone,
               location, recurrence_rule, source_state, source_updated_at)
            VALUES (?, ?, ?, ?, ?, 0, ?, ?, NULL, ?, ?)
            ON CONFLICT(course_id, source_object_id) DO UPDATE SET
              starts_at=excluded.starts_at, ends_at=excluded.ends_at,
              original_time_zone=excluded.original_time_zone, location=excluded.location,
              source_state=excluded.source_state, source_updated_at=excluded.source_updated_at
            """,
            bindings: [
                .text(id), .text(courseID), .text(value.sourceObjectID),
                .real(value.startsAt.timeIntervalSince1970), .real(value.endsAt.timeIntervalSince1970),
                .text(value.timeZone), .text(value.location), .text(value.sourceState.rawValue),
                .real(date.timeIntervalSince1970)
            ]
        )
        try resetPresence(type: .courseMeeting, sourceID: value.sourceObjectID, account: account, runID: runID, at: date)
        try record(changes, type: .courseMeeting, objectID: id, at: date)
        let stateChanged = oldState != nil && oldState != value.sourceState.rawValue
        if value.sourceState == .cancelled {
            if oldState != SyncSourceState.cancelled.rawValue {
                counters.cancelled += 1
                try enqueue(.calendarRemove(objectType: SyncObjectType.courseMeeting.rawValue, objectID: id), keyVersion: "cancelled", at: date)
            }
        } else if value.endsAt >= date && (existing == nil || !changes.isEmpty || stateChanged) {
            try enqueue(.calendarUpsert(objectType: SyncObjectType.courseMeeting.rawValue, objectID: id), keyVersion: meetingVersion(value), at: date)
        } else if existing != nil, !changes.isEmpty,
                  let previousEnd = existing?.double("ends_at"), previousEnd >= date.timeIntervalSince1970 {
            try enqueue(.calendarRemove(objectType: SyncObjectType.courseMeeting.rawValue, objectID: id), keyVersion: "ended", at: date)
        }
        count(existing: existing, changes: changes, oldState: oldState, newState: value.sourceState.rawValue, counters: &counters)
    }

    private func apply(
        _ value: NormalizedTask, account: SyncSourceAccount, runID: UUID,
        at date: Date, suppressNewNotification: Bool, counters: inout Counters
    ) throws {
        guard let courseID = try domainID(type: .course, accountID: account.id, sourceID: value.courseSourceObjectID) else {
            throw SyncEngineError(category: .malformedResponse, retryable: false)
        }
        let existing = try row(type: .learningTask, accountID: account.id, sourceID: value.sourceObjectID)
        let id = existing?.string("id") ?? idGenerator.next().uuidString
        let oldState = existing?.string("source_state")
        let oldPlaceholder = existing?.string("placeholder_state") == "placeholder"
        let newPlaceholder = value.isPlaceholder
        let changes = changesForTask(existing, value)
        let courseTZ = try database.query("SELECT time_zone FROM courses WHERE id = ?", bindings: [.text(courseID)]).first?.string("time_zone") ?? "UTC"
        try database.execute(
            """
            INSERT INTO learning_tasks
              (id, source_account_id, source_object_id, course_id, title, official_type, normalized_type,
               official_due_at, official_due_time_zone, official_due_is_all_day, suggested_complete_at,
               suggestion_origin, suggestion_confirmed_at, opens_at, locks_at, source_url, source_state,
               source_updated_at, first_seen_at, last_seen_at, placeholder_state,
               placeholder_evidence_complete, placeholder_has_description, placeholder_has_attachment,
               placeholder_has_linked_activity, placeholder_has_submission, placeholder_has_action)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, NULL, NULL, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_account_id, source_object_id) DO UPDATE SET
              course_id=excluded.course_id, title=excluded.title, official_type=excluded.official_type,
              normalized_type=excluded.normalized_type, official_due_at=excluded.official_due_at,
              official_due_time_zone=excluded.official_due_time_zone, opens_at=excluded.opens_at,
              locks_at=excluded.locks_at, source_url=excluded.source_url, source_state='active',
              source_updated_at=excluded.source_updated_at, last_seen_at=excluded.last_seen_at,
              placeholder_state=excluded.placeholder_state,
              placeholder_evidence_complete=excluded.placeholder_evidence_complete,
              placeholder_has_description=excluded.placeholder_has_description,
              placeholder_has_attachment=excluded.placeholder_has_attachment,
              placeholder_has_linked_activity=excluded.placeholder_has_linked_activity,
              placeholder_has_submission=excluded.placeholder_has_submission,
              placeholder_has_action=excluded.placeholder_has_action
            """,
            bindings: [
                .text(id), .text(account.id.uuidString), .text(value.sourceObjectID), .text(courseID),
                .text(value.title), .text(value.officialType), .text(value.normalizedType),
                optionalDate(value.officialDueAt), .text(courseTZ), optionalDate(value.opensAt),
                optionalDate(value.locksAt), optionalText(value.sourceURL), .real(date.timeIntervalSince1970),
                .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970),
                .text(newPlaceholder ? "placeholder" : "active"),
                .integer(value.placeholderEvidence.isComplete ? 1 : 0),
                .integer(value.placeholderEvidence.hasMeaningfulDescription ? 1 : 0),
                .integer(value.placeholderEvidence.hasAttachment ? 1 : 0),
                .integer(value.placeholderEvidence.hasLinkedActivity ? 1 : 0),
                .integer(value.placeholderEvidence.hasMeaningfulSubmission ? 1 : 0),
                .integer(value.placeholderEvidence.hasActionableRequirement ? 1 : 0)
            ]
        )
        if existing == nil && newPlaceholder {
            try updatePlaceholderMetrics(suppressedDelta: 1, reactivatedDelta: 0, at: date)
        } else if oldPlaceholder != newPlaceholder {
            try updatePlaceholderMetrics(
                suppressedDelta: newPlaceholder ? 1 : 0,
                reactivatedDelta: newPlaceholder ? 0 : 1, at: date
            )
        } else if newPlaceholder && oldState == SyncSourceState.cancelled.rawValue {
            // Reappearing unchanged placeholders are active again, so refresh the
            // current count without treating the same shell as newly suppressed.
            try updatePlaceholderMetrics(suppressedDelta: 0, reactivatedDelta: 0, at: date)
        }
        try resetPresence(type: .learningTask, sourceID: value.sourceObjectID, account: account, runID: runID, at: date)
        try record(changes, type: .learningTask, objectID: id, at: date)
        if existing != nil && newPlaceholder && !oldPlaceholder {
            try enqueue(.calendarRemove(objectType: SyncObjectType.learningTask.rawValue, objectID: id), keyVersion: "placeholder", at: date)
            for delivery in try database.query(
                "SELECT notification_key FROM notification_deliveries WHERE object_type='learning_task' AND object_id=? AND state='scheduled'",
                bindings: [.text(id)]
            ) {
                if let key = delivery.string("notification_key") { try enqueue(.notificationCancel(key: key), keyVersion: "placeholder", at: date) }
            }
        } else if !newPlaceholder, let due = value.officialDueAt, due >= date,
           (existing == nil || !changes.isEmpty || oldState == "cancelled") {
            try enqueue(.calendarUpsert(objectType: SyncObjectType.learningTask.rawValue, objectID: id), keyVersion: taskVersion(value), at: date)
        } else if existing != nil, !changes.isEmpty,
                  let previousDue = existing?.double("official_due_at"),
                  previousDue >= date.timeIntervalSince1970 {
            try enqueue(.calendarRemove(objectType: SyncObjectType.learningTask.rawValue, objectID: id), keyVersion: "expired-or-undated", at: date)
        }
        let becameActionable = !newPlaceholder && (existing == nil || oldPlaceholder)
        if becameActionable && !suppressNewNotification {
            if try !hasNewTaskNotificationHistory(objectID: id) {
                let key = "new:\(SyncObjectType.learningTask.rawValue):\(id)"
                try enqueue(.notificationNew(key: key, objectID: id, at: date), keyVersion: "new", at: date)
            }
        }
        count(existing: existing, changes: changes, oldState: oldState, newState: "active", counters: &counters)
    }

    private func updatePlaceholderMetrics(suppressedDelta: Int, reactivatedDelta: Int, at date: Date) throws {
        try database.execute(
            """
            UPDATE placeholder_metrics SET suppressed_total=suppressed_total+?,
              reactivated_total=reactivated_total+?,
              current_suppressed=(SELECT COUNT(*) FROM learning_tasks
                WHERE source_state='active' AND placeholder_state='placeholder'), updated_at=?
            WHERE singleton_key=1
            """,
            bindings: [.integer(Int64(suppressedDelta)), .integer(Int64(reactivatedDelta)),
                       .real(date.timeIntervalSince1970)]
        )
    }

    private func hasNewTaskNotificationHistory(objectID: String) throws -> Bool {
        let key = "new:\(SyncObjectType.learningTask.rawValue):\(objectID)"
        return try !database.query(
            """
            SELECT 1 AS found FROM outbox_work
              WHERE kind='notification.schedule' AND object_type='notification' AND object_id=?
            UNION ALL
            SELECT 1 AS found FROM notification_deliveries WHERE notification_key=?
            LIMIT 1
            """,
            bindings: [.text(objectID), .text(key)]
        ).isEmpty
    }

    private func apply(
        _ value: NormalizedAnnouncement, account: SyncSourceAccount, runID: UUID,
        at date: Date, suppressNewNotification: Bool, counters: inout Counters
    ) throws {
        guard let courseID = try domainID(type: .course, accountID: account.id, sourceID: value.courseSourceObjectID) else {
            throw SyncEngineError(category: .malformedResponse, retryable: false)
        }
        let existing = try row(type: .announcement, accountID: account.id, sourceID: value.sourceObjectID)
        let id = existing?.string("id") ?? idGenerator.next().uuidString
        let oldState = existing?.string("source_state")
        let published = value.publishedAt ?? value.updatedAt
            ?? existing?.double("published_at").map(Date.init(timeIntervalSince1970:))
            ?? date
        let changes = changesForAnnouncement(existing, value, resolvedPublishedAt: published)
        try database.execute(
            """
            INSERT INTO announcements
              (id, source_account_id, source_object_id, course_id, title, published_at, source_updated_at,
               summary, content_hash, source_url, source_state, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)
            ON CONFLICT(source_account_id, source_object_id) DO UPDATE SET
              course_id=excluded.course_id, title=excluded.title, published_at=excluded.published_at,
              source_updated_at=excluded.source_updated_at, summary=excluded.summary,
              content_hash=excluded.content_hash, source_url=excluded.source_url,
              source_state='active', last_seen_at=excluded.last_seen_at
            """,
            bindings: [
                .text(id), .text(account.id.uuidString), .text(value.sourceObjectID), .text(courseID),
                .text(value.title), .real(published.timeIntervalSince1970), optionalDate(value.updatedAt),
                .text(value.summary), .text(value.contentHash), optionalText(value.sourceURL),
                .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970)
            ]
        )
        try resetPresence(type: .announcement, sourceID: value.sourceObjectID, account: account, runID: runID, at: date)
        try record(changes, type: .announcement, objectID: id, at: date)
        if existing == nil && !suppressNewNotification {
            let key = "new:\(SyncObjectType.announcement.rawValue):\(id)"
            try enqueue(.notificationNew(key: key, objectID: id, at: date), keyVersion: "new", at: date)
        }
        count(existing: existing, changes: changes, oldState: oldState, newState: "active", counters: &counters)
    }

    private func isBaselineComplete(type: SyncObjectType, accountID: UUID) throws -> Bool {
        try database.query(
            """
            SELECT 1 AS completed FROM source_baselines
            WHERE source_account_id = ? AND object_type = ?
            """,
            bindings: [.text(accountID.uuidString), .text(type.rawValue)]
        ).first != nil
    }

    private func completeBaseline(
        type: SyncObjectType, account: SyncSourceAccount, runID: UUID, at date: Date
    ) throws {
        try database.execute(
            """
            INSERT INTO source_baselines
              (source_account_id, object_type, completed_run_id, completed_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(source_account_id, object_type) DO NOTHING
            """,
            bindings: [
                .text(account.id.uuidString), .text(type.rawValue), .text(runID.uuidString),
                .real(date.timeIntervalSince1970)
            ]
        )
    }

    private func applyAbsenceEvidence(
        type: SyncObjectType, observed: Set<String>, account: SyncSourceAccount,
        runID: UUID, at date: Date, counters: inout Counters
    ) throws {
        let existing = try sourceRows(type: type, accountID: account.id)
        for row in existing {
            guard let sourceID = row.string("source_object_id"), !observed.contains(sourceID),
                  let objectID = row.string("id") else { continue }
            let prior = try database.query(
                """
                SELECT consecutive_complete_absences FROM source_presence
                WHERE source_account_id = ? AND object_type = ? AND source_object_id = ?
                """,
                bindings: [.text(account.id.uuidString), .text(type.rawValue), .text(sourceID)]
            ).first?.int("consecutive_complete_absences") ?? 0
            let next = prior + 1
            try database.execute(
                """
                INSERT INTO source_presence
                  (source_account_id, object_type, source_object_id, consecutive_complete_absences,
                   last_observed_run_id, updated_at)
                VALUES (?, ?, ?, ?, NULL, ?)
                ON CONFLICT(source_account_id, object_type, source_object_id) DO UPDATE SET
                  consecutive_complete_absences=excluded.consecutive_complete_absences,
                  updated_at=excluded.updated_at
                """,
                bindings: [
                    .text(account.id.uuidString), .text(type.rawValue), .text(sourceID),
                    .integer(next), .real(date.timeIntervalSince1970)
                ]
            )
            if next >= 2, row.string("source_state") != SyncSourceState.cancelled.rawValue {
                try softCancel(type: type, objectID: objectID, at: date)
                if type == .learningTask, row.string("placeholder_state") == "placeholder" {
                    try updatePlaceholderMetrics(suppressedDelta: 0, reactivatedDelta: 0, at: date)
                }
                try record([
                    ("source_state", row.string("source_state"), SyncSourceState.cancelled.rawValue)
                ], type: type, objectID: objectID, at: date)
                counters.updated += 1
                counters.cancelled += 1
                if type == .courseMeeting || type == .learningTask {
                    try enqueue(.calendarRemove(objectType: type.rawValue, objectID: objectID), keyVersion: "absent-2", at: date)
                    let notificationKey = "new:\(type.rawValue):\(objectID)"
                    try enqueue(.notificationCancel(key: notificationKey), keyVersion: "absent-2", at: date)
                }
            }
        }
    }

    private func softCancel(type: SyncObjectType, objectID: String, at date: Date) throws {
        let table: String
        switch type {
        case .course: table = "courses"
        case .courseMeeting: table = "course_meetings"
        case .learningTask: table = "learning_tasks"
        case .announcement: table = "announcements"
        }
        let timestampColumn = type == .courseMeeting ? "source_updated_at" : "last_seen_at"
        try database.execute(
            "UPDATE \(table) SET source_state = 'cancelled', \(timestampColumn) = ? WHERE id = ?",
            bindings: [.real(date.timeIntervalSince1970), .text(objectID)]
        )
    }

    private func resetPresence(
        type: SyncObjectType, sourceID: String, account: SyncSourceAccount,
        runID: UUID, at date: Date
    ) throws {
        try database.execute(
            """
            INSERT INTO source_presence
              (source_account_id, object_type, source_object_id, consecutive_complete_absences,
               last_observed_run_id, updated_at)
            VALUES (?, ?, ?, 0, ?, ?)
            ON CONFLICT(source_account_id, object_type, source_object_id) DO UPDATE SET
              consecutive_complete_absences=0, last_observed_run_id=excluded.last_observed_run_id,
              updated_at=excluded.updated_at
            """,
            bindings: [
                .text(account.id.uuidString), .text(type.rawValue), .text(sourceID),
                .text(runID.uuidString), .real(date.timeIntervalSince1970)
            ]
        )
    }

    private func record(
        _ changes: [(String, String?, String?)], type: SyncObjectType,
        objectID: String, at date: Date
    ) throws {
        for change in changes {
            try database.execute(
                """
                INSERT INTO change_records
                  (id, object_type, object_id, field_name, old_value_summary, new_value_summary,
                   change_source, discovered_at)
                VALUES (?, ?, ?, ?, ?, ?, 'source_sync', ?)
                """,
                bindings: [
                    .text(idGenerator.next().uuidString), .text(type.rawValue), .text(objectID),
                    .text(change.0), optionalText(change.1), optionalText(change.2),
                    .real(date.timeIntervalSince1970)
                ]
            )
        }
    }

    private func enqueue(_ envelope: OutboxEnvelope, keyVersion: String, at date: Date) throws {
        let payload = try JSONEncoder.syncEncoder.encode(envelope)
        let identity: (String, String, String)
        switch envelope {
        case .calendarUpsert(let type, let id): identity = ("calendar.upsert", type, id)
        case .calendarRemove(let type, let id): identity = ("calendar.remove", type, id)
        case .calendarReconcile(let type, let id): identity = ("calendar.reconcile", type, id)
        case .notificationNew(_, let id, _): identity = ("notification.schedule", "notification", id)
        case .notificationCancel(let key): identity = ("notification.cancel", "notification", key)
        }
        let occurrence = "\(keyVersion)|\(String(format: "%.6f", date.timeIntervalSince1970))"
        let dedupe = "\(identity.0):\(identity.1):\(identity.2):\(StableDigest.hash(occurrence))"
        try database.execute(
            """
            INSERT INTO outbox_work
              (id, kind, deduplication_key, object_type, object_id, payload, state, attempt_count,
               available_at, created_at, updated_at, last_error_category)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?, NULL)
            ON CONFLICT(deduplication_key) DO NOTHING
            """,
            bindings: [
                .text(idGenerator.next().uuidString), .text(identity.0), .text(dedupe),
                .text(identity.1), .text(identity.2), .blob(payload),
                .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970),
                .real(date.timeIntervalSince1970)
            ]
        )
    }

    private func saveRaw<T: Encodable>(
        _ value: T, account: SyncSourceAccount, runID: UUID, at date: Date
    ) throws {
        let encoder = JSONEncoder.syncEncoder
        let payload = try encoder.encode(value)
        let sourceID: String
        let type: SyncObjectType
        switch value {
        case let value as NormalizedCourse: sourceID = value.sourceObjectID; type = .course
        case let value as NormalizedMeeting: sourceID = value.sourceObjectID; type = .courseMeeting
        case let value as NormalizedTask: sourceID = value.sourceObjectID; type = .learningTask
        case let value as NormalizedAnnouncement: sourceID = value.sourceObjectID; type = .announcement
        default: throw SyncEngineError(category: .malformedResponse, retryable: false)
        }
        let hash = StableDigest.hash(payload.base64EncodedString())
        try database.execute(
            """
            INSERT INTO raw_source_records
              (id, source_account_id, object_type, source_object_id, fetch_batch_id,
               content_hash, payload, fetched_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_account_id, object_type, source_object_id, content_hash) DO NOTHING
            """,
            bindings: [
                .text(idGenerator.next().uuidString), .text(account.id.uuidString), .text(type.rawValue),
                .text(sourceID), .text(runID.uuidString), .text(hash), .blob(payload),
                .real(date.timeIntervalSince1970)
            ]
        )
    }

    private func saveRawRecord(
        _ value: RawSyncRecord, account: SyncSourceAccount, runID: UUID, at date: Date
    ) throws {
        let payload = try JSONEncoder.syncEncoder.encode(value)
        let hash = StableDigest.hash(payload.base64EncodedString())
        try database.execute(
            """
            INSERT INTO raw_source_records
              (id, source_account_id, object_type, source_object_id, fetch_batch_id,
               content_hash, payload, fetched_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_account_id, object_type, source_object_id, content_hash) DO NOTHING
            """,
            bindings: [
                .text(idGenerator.next().uuidString), .text(account.id.uuidString),
                .text(value.objectType.rawValue), .text(value.sourceObjectID), .text(runID.uuidString),
                .text(hash), .blob(payload), .real(date.timeIntervalSince1970)
            ]
        )
    }

    private func row(type: SyncObjectType, accountID: UUID, sourceID: String) throws -> SQLiteRow? {
        switch type {
        case .course, .learningTask, .announcement:
            return try database.query(
                "SELECT * FROM \(table(type)) WHERE source_account_id = ? AND source_object_id = ?",
                bindings: [.text(accountID.uuidString), .text(sourceID)]
            ).first
        case .courseMeeting:
            return try database.query(
                """
                SELECT course_meetings.* FROM course_meetings
                JOIN courses ON courses.id = course_meetings.course_id
                WHERE courses.source_account_id = ? AND course_meetings.source_object_id = ?
                """,
                bindings: [.text(accountID.uuidString), .text(sourceID)]
            ).first
        }
    }

    private func sourceRows(type: SyncObjectType, accountID: UUID) throws -> [SQLiteRow] {
        if type == .courseMeeting {
            return try database.query(
                """
                SELECT course_meetings.* FROM course_meetings
                JOIN courses ON courses.id = course_meetings.course_id
                WHERE courses.source_account_id = ?
                """, bindings: [.text(accountID.uuidString)]
            )
        }
        return try database.query(
            "SELECT * FROM \(table(type)) WHERE source_account_id = ?",
            bindings: [.text(accountID.uuidString)]
        )
    }

    private func domainID(type: SyncObjectType, accountID: UUID, sourceID: String) throws -> String? {
        try row(type: type, accountID: accountID, sourceID: sourceID)?.string("id")
    }

    private func table(_ type: SyncObjectType) -> String {
        switch type {
        case .course: "courses"
        case .courseMeeting: "course_meetings"
        case .learningTask: "learning_tasks"
        case .announcement: "announcements"
        }
    }

    private func observedIDs(_ type: SyncObjectType, in snapshot: SyncSnapshot) -> Set<String> {
        switch type {
        case .course: Set(snapshot.courses.map(\.sourceObjectID))
        case .courseMeeting: Set(snapshot.meetings.map(\.sourceObjectID))
        case .learningTask: Set(snapshot.tasks.map(\.sourceObjectID))
        case .announcement: Set(snapshot.announcements.map(\.sourceObjectID))
        }
    }

    private func count(
        existing: SQLiteRow?, changes: [(String, String?, String?)], oldState: String?,
        newState: String, counters: inout Counters
    ) {
        if existing == nil { counters.inserted += 1 }
        else if !changes.isEmpty || oldState != newState { counters.updated += 1 }
    }

    private func changesForCourse(_ row: SQLiteRow?, _ value: NormalizedCourse) -> [(String, String?, String?)] {
        guard let row else { return [] }
        return changed([
            ("name", row.string("name"), value.name), ("code", row.string("code"), value.code),
            ("term", row.string("term"), value.term), ("time_zone", row.string("time_zone"), value.timeZone),
            ("source_url", row.string("source_url"), value.sourceURL),
            ("source_state", row.string("source_state"), "active")
        ])
    }

    private func changesForMeeting(_ row: SQLiteRow?, _ value: NormalizedMeeting) -> [(String, String?, String?)] {
        guard let row else { return [] }
        return changed([
            ("starts_at", summary(row.double("starts_at")), summary(value.startsAt)),
            ("ends_at", summary(row.double("ends_at")), summary(value.endsAt)),
            ("original_time_zone", row.string("original_time_zone"), value.timeZone),
            ("location", row.string("location"), value.location),
            ("source_state", row.string("source_state"), value.sourceState.rawValue)
        ])
    }

    private func changesForTask(_ row: SQLiteRow?, _ value: NormalizedTask) -> [(String, String?, String?)] {
        guard let row else { return [] }
        return changed([
            ("title", row.string("title"), value.title),
            ("official_type", row.string("official_type"), value.officialType),
            ("normalized_type", row.string("normalized_type"), value.normalizedType),
            ("official_due_at", summary(row.double("official_due_at")), summary(value.officialDueAt)),
            ("opens_at", summary(row.double("opens_at")), summary(value.opensAt)),
            ("locks_at", summary(row.double("locks_at")), summary(value.locksAt)),
            ("source_url", row.string("source_url"), value.sourceURL),
            ("placeholder_state", row.string("placeholder_state"), value.isPlaceholder ? "placeholder" : "active"),
            ("source_state", row.string("source_state"), "active")
        ])
    }

    private func changesForAnnouncement(
        _ row: SQLiteRow?, _ value: NormalizedAnnouncement, resolvedPublishedAt: Date
    ) -> [(String, String?, String?)] {
        guard let row else { return [] }
        return changed([
            ("title", row.string("title"), value.title),
            ("published_at", summary(row.double("published_at")), summary(resolvedPublishedAt)),
            ("summary", row.string("summary"), value.summary),
            ("content_hash", row.string("content_hash"), value.contentHash),
            ("source_url", row.string("source_url"), value.sourceURL),
            ("source_state", row.string("source_state"), "active")
        ])
    }

    private func changed(_ values: [(String, String?, String?)]) -> [(String, String?, String?)] {
        values.filter { $0.1 != $0.2 }
    }

    private func meetingVersion(_ value: NormalizedMeeting) -> String {
        [summary(value.startsAt), summary(value.endsAt), value.timeZone, value.location, value.sourceState.rawValue]
            .map { $0 ?? "nil" }.joined(separator: "|")
    }

    private func taskVersion(_ value: NormalizedTask) -> String {
        [value.title, value.officialType, value.normalizedType, summary(value.officialDueAt) ?? "nil"]
            .joined(separator: "|")
    }

    private func summary(_ date: Date?) -> String? { date.map { String(format: "%.3f", $0.timeIntervalSince1970) } }
    private func summary(_ interval: Double?) -> String? { interval.map { String(format: "%.3f", $0) } }
    private func optionalText(_ value: String?) -> SQLiteValue { value.map(SQLiteValue.text) ?? .null }
    private func optionalDate(_ value: Date?) -> SQLiteValue { value.map { .real($0.timeIntervalSince1970) } ?? .null }

    private func recordFailedRun(
        id: UUID, account: SyncSourceAccount, trigger: SyncTrigger,
        startedAt: Date, finishedAt: Date, error: SyncEngineError
    ) throws {
        let account = try ensureAccount(account, at: startedAt)
        try database.execute(
            """
            INSERT OR REPLACE INTO sync_runs
              (id, trigger_kind, source_account_id, fetch_state, normalize_state, persistence_state,
               read_count, inserted_count, updated_count, cancelled_count, started_at, finished_at,
               error_category, redacted_error_summary)
            VALUES (?, ?, ?, ?, 'not_started', 'not_started', 0, 0, 0, 0, ?, ?, ?, ?)
            """,
            bindings: [
                .text(id.uuidString), .text(trigger.rawValue), .text(account.id.uuidString),
                .text(error.category == .cancelled ? "cancelled" : "failed"),
                .real(startedAt.timeIntervalSince1970), .real(finishedAt.timeIntervalSince1970),
                .text(error.category.rawValue), .text(error.category.rawValue)
            ]
        )
    }

    private func classify(_ error: Error) -> SyncEngineError {
        if error is CancellationError { return SyncEngineError(category: .cancelled, retryable: false) }
        if let error = error as? SyncEngineError { return error }
        if let error = error as? CanvasConnectorError {
            let category: SyncErrorCategory
            switch error.category {
            case .unauthorized: category = .unauthorized
            case .forbidden: category = .forbidden
            case .rateLimited: category = .rateLimited
            case .serverUnavailable: category = .temporaryServer
            case .timedOut, .offline, .transport: category = .offline
            case .malformedResponse, .unsafePagination: category = .malformedResponse
            case .notFound: category = .sourceChanged
            case .configuration: category = .unknown
            }
            return SyncEngineError(category: category, retryable: error.retryable)
        }
        if let error = error as? SIwebConnectorError {
            let category: SyncErrorCategory
            switch error.category {
            case .unauthorized, .sessionExpired: category = .unauthorized
            case .forbidden: category = .forbidden
            case .rateLimited: category = .rateLimited
            case .serverUnavailable: category = .temporaryServer
            case .timedOut, .offline, .transport: category = .offline
            case .structuralChange, .partialResponse, .loginRedirect: category = .sourceChanged
            case .malformedResponse, .unsafeRoute, .notFound: category = .malformedResponse
            case .configuration: category = .unknown
            }
            return SyncEngineError(category: category, retryable: error.retryable)
        }
        // Keychain failures are actionable authorization failures, not an opaque
        // source error. A fresh user-authorized setup recreates an item whose ACL
        // matches the current signed application identity.
        if error is SecretStoreError {
            return SyncEngineError(category: .unauthorized, retryable: false)
        }
        if error is DatabaseError { return SyncEngineError(category: .persistence, retryable: true) }
        return SyncEngineError(category: .unknown, retryable: false)
    }
}

private struct Counters {
    var inserted = 0
    var updated = 0
    var cancelled = 0
}

private extension JSONEncoder {
    static var syncEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}
