import Foundation

enum CalendarLocalTool {
    static func smokeTest(resultPath: String) async -> Int32 {
        let resultURL = URL(fileURLWithPath: resultPath)
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("campus-dashboard-eventkit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let database = try SQLiteDatabase(path: directory.appendingPathComponent("smoke.sqlite3").path)
            let store = EventKitEventStore()
            let service = CampusCalendarService(database: database, store: store)

            guard try await service.requestAccessFromUserAction() else {
                throw CampusCalendarError.permissionDenied
            }
            let sources = try await service.availableSources()
            guard let source = sources.first(where: { $0.kind == .local }) ?? sources.first else {
                throw CampusCalendarError.invalidSelection
            }
            let suffix = UUID().uuidString.prefix(8)
            let identity = try await service.createDedicatedCalendar(
                sourceIdentifier: source.identifier,
                title: "Campus Dashboard — Stage 06 Test \(suffix)"
            )

            do {
                try seedTask(database, dueAt: 1_800_000_000, title: "Stage 06 Create")
                _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "stage-06-task")])
                var events = await store.events(
                    calendarIdentifier: identity.calendarIdentifier,
                    around: Date(timeIntervalSince1970: 1_800_000_000),
                    ownershipMarker: "\(identity.ownershipMarker):learning_task:stage-06-task"
                )
                guard events.count == 1 else { throw CampusCalendarError.ambiguousOwnedEvents }
                let externalIdentifier = try requireExternalIdentifier(events[0])
                try database.execute(
                    "UPDATE calendar_bindings SET event_identifier = 'simulated-stale-event-id' WHERE object_id = 'stage-06-task'"
                )

                try database.execute(
                    "UPDATE learning_tasks SET title = 'Stage 06 Update', official_due_at = 1800864000 WHERE id = 'stage-06-task'"
                )
                _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "stage-06-task")])
                _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "stage-06-task")])
                events = await store.events(
                    calendarIdentifier: identity.calendarIdentifier,
                    around: Date(timeIntervalSince1970: 1_800_864_000),
                    ownershipMarker: "\(identity.ownershipMarker):learning_task:stage-06-task"
                )
                guard events.count == 1,
                      events[0].title.contains("Update"),
                      events[0].startsAt == Date(timeIntervalSince1970: 1_800_864_000),
                      events[0].externalIdentifier == externalIdentifier else {
                    throw CampusCalendarError.staleBinding
                }
                let repairedBinding = try CalendarPersistence(database: database).binding(
                    objectType: "learning_task", objectID: "stage-06-task"
                )
                guard repairedBinding?.eventIdentifier == events[0].identifier,
                      repairedBinding?.externalEventIdentifier == externalIdentifier else {
                    throw CampusCalendarError.staleBinding
                }

                _ = try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "stage-06-task")])
                _ = try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "stage-06-task")])
                guard await store.event(identifier: events[0].identifier) == nil else {
                    throw CampusCalendarError.staleBinding
                }
                let sourceLabel = identity.isICloud
                    ? "icloud" : (identity.sourceKind == .local ? "local" : "other")
                try write(
                    "PASS source=\(sourceLabel) create=1 update=1 cancel=1 repeated_sync=1 external_recovery=1 isolated_calendar=1\n",
                    to: resultURL
                )
                try await store.removeCalendar(identifier: identity.calendarIdentifier)
                return 0
            } catch {
                try? await store.removeCalendar(identifier: identity.calendarIdentifier)
                throw error
            }
        } catch {
            try? write("FAIL category=\(sanitizedCategory(error))\n", to: resultURL)
            return 1
        }
    }

    private static func seedTask(_ database: SQLiteDatabase, dueAt: Double, title: String) throws {
        try database.execute(
            """
            INSERT INTO source_accounts
              (id, source_kind, instance_url, display_name, authorization_state, created_at, updated_at)
            VALUES ('stage-06-account', 'Canvas', 'https://example.invalid', 'Stage 06', 'connected', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO courses
              (id, source_account_id, source_object_id, name, code, term, time_zone,
               source_state, first_seen_at, last_seen_at)
            VALUES ('stage-06-course', 'stage-06-account', 'course', 'Stage 06 Test', 'TEST', '', 'UTC', 'active', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO learning_tasks
              (id, source_account_id, source_object_id, course_id, title, official_type,
               official_due_at, source_state, first_seen_at, last_seen_at)
            VALUES ('stage-06-task', 'stage-06-account', 'task', 'stage-06-course', ?,
                    'assignment', ?, 'active', 1, 1)
            """,
            bindings: [.text(title), .real(dueAt)]
        )
    }

    private static func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url, options: .atomic)
    }

    private static func sanitizedCategory(_ error: Error) -> String {
        if let error = error as? CampusCalendarError { return String(describing: error) }
        return "eventkit_error"
    }

    private static func requireExternalIdentifier(_ event: CalendarStoredEvent) throws -> String {
        guard let identifier = event.externalIdentifier, !identifier.isEmpty else {
            throw CampusCalendarError.eventRecoveryUnavailable
        }
        return identifier
    }
}
