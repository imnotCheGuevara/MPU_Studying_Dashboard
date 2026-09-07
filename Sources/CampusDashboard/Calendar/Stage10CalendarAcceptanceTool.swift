import Foundation

enum Stage10CalendarAcceptanceTool {
    enum Phase: String {
        case baseline
        case create
        case update
        case cancel
        case cleanup
    }

    private static let accountID = "f1000000-0000-0000-0000-000000000010"
    private static let courseID = "f1000000-0000-0000-0000-000000000011"
    private static let taskID = "f1000000-0000-0000-0000-000000000012"
    private static let objectType = "learning_task"
    private static let originalTitle = "Campus Dashboard Stage 10 Lifecycle"
    private static let updatedTitle = "Campus Dashboard Stage 10 Lifecycle Updated"

    static func run(phase: Phase, resultPath: String) async -> Int32 {
        do {
            let directory = try applicationSupportDirectory()
            let database = try SQLiteDatabase(path: directory.appendingPathComponent("campus-dashboard.sqlite3").path)
            let store = EventKitEventStore()
            let service = CampusCalendarService(database: database, store: store)
            guard let identity = try await service.configuredIdentity(), identity.isICloud else {
                throw AcceptanceError.iCloudCalendarNotConfigured
            }
            guard try await service.validateDedicatedCalendar() == .valid else {
                throw AcceptanceError.dedicatedCalendarInvalid
            }

            switch phase {
            case .baseline:
                let stateURL = directory.appendingPathComponent("stage10-calendar-acceptance-state.json")
                if let state = try? loadState(from: stateURL) {
                    try await verifyControl(state, store: store)
                } else {
                    let state = try await createControl(
                        identity: identity, store: store, stateURL: stateURL
                    )
                    try await verifyControl(state, store: store)
                }
                let managedBindings = try aggregateCount(
                    database, sql: "SELECT count(*) AS value FROM calendar_bindings WHERE sync_state!='removed'"
                )
                let notifications = try aggregateCount(
                    database, sql: "SELECT count(*) AS value FROM notification_deliveries"
                )
                try write(
                    "PASS phase=baseline source=icloud managed_bindings=\(managedBindings) " +
                    "control_calendars=1 control_events=1 notifications=\(notifications)",
                    to: resultPath
                )

            case .create:
                try await verifyStoredControl(directory: directory, store: store)
                try seed(database, startsAt: lifecycleStart(), title: originalTitle)
                _ = try await service.apply([.upsert(objectType: objectType, objectID: taskID)])
                _ = try await service.apply([.upsert(objectType: objectType, objectID: taskID)])
                let count = try await verifiedEventCount(database: database, store: store, identity: identity)
                guard count == 1 else { throw AcceptanceError.eventCountMismatch }
                try write(
                    "PASS phase=create source=icloud managed_events=1 repeated_sync=1 control_unchanged=1",
                    to: resultPath
                )

            case .update:
                try await verifyStoredControl(directory: directory, store: store)
                let oldBinding = try requireBinding(database)
                let oldExternalIdentifier = oldBinding.externalEventIdentifier
                guard let row = try database.query(
                    "SELECT official_due_at FROM learning_tasks WHERE id=?", bindings: [.text(taskID)]
                ).first, let oldStart = row.double("official_due_at") else {
                    throw AcceptanceError.lifecycleStateMissing
                }
                try database.execute(
                    "UPDATE learning_tasks SET title=?, official_due_at=? WHERE id=?",
                    bindings: [.text(updatedTitle), .real(oldStart + 7_200), .text(taskID)]
                )
                _ = try await service.apply([.upsert(objectType: objectType, objectID: taskID)])
                _ = try await service.apply([.upsert(objectType: objectType, objectID: taskID)])
                let binding = try requireBinding(database)
                guard let event = await store.event(identifier: binding.eventIdentifier),
                      event.startsAt == Date(timeIntervalSince1970: oldStart + 7_200),
                      event.title == updatedTitle,
                      event.externalIdentifier == oldExternalIdentifier else {
                    throw AcceptanceError.bindingContinuityFailed
                }
                let count = try await verifiedEventCount(database: database, store: store, identity: identity)
                guard count == 1 else { throw AcceptanceError.eventCountMismatch }
                try write(
                    "PASS phase=update source=icloud managed_events=1 same_external_event=1 repeated_sync=1 control_unchanged=1",
                    to: resultPath
                )

            case .cancel:
                try await verifyStoredControl(directory: directory, store: store)
                let binding = try requireBinding(database)
                _ = try await service.apply([.removeBoundEvent(objectType: objectType, objectID: taskID)])
                _ = try await service.apply([.removeBoundEvent(objectType: objectType, objectID: taskID)])
                guard await store.event(identifier: binding.eventIdentifier) == nil else {
                    throw AcceptanceError.eventCountMismatch
                }
                try database.transaction {
                    try database.execute(
                        "DELETE FROM calendar_bindings WHERE object_type=? AND object_id=?",
                        bindings: [.text(objectType), .text(taskID)]
                    )
                    try database.execute("DELETE FROM source_accounts WHERE id=?", bindings: [.text(accountID)])
                }
                try write(
                    "PASS phase=cancel source=icloud managed_events=0 repeated_cancel=1 local_seed_removed=1 control_unchanged=1",
                    to: resultPath
                )

            case .cleanup:
                let stateURL = directory.appendingPathComponent("stage10-calendar-acceptance-state.json")
                let state = try loadState(from: stateURL)
                try await verifyControl(state, store: store)
                try await store.removeCalendar(identifier: state.calendarIdentifier)
                try FileManager.default.removeItem(at: stateURL)
                try write("PASS phase=cleanup control_calendars=0 control_state_removed=1", to: resultPath)
            }
            return 0
        } catch {
            try? write("FAIL category=\(safeCategory(error))", to: resultPath)
            return 1
        }
    }

    private static func seed(_ database: SQLiteDatabase, startsAt: Date, title: String) throws {
        let now = Date().timeIntervalSince1970
        try database.transaction {
            try database.execute(
                """
                INSERT INTO source_accounts
                  (id, source_kind, instance_url, display_name, authorization_state, created_at, updated_at)
                VALUES (?, 'Stage10Test', 'https://stage10.invalid', 'Stage 10 Test', 'authorized', ?, ?)
                ON CONFLICT(source_kind, instance_url) DO UPDATE SET updated_at=excluded.updated_at
                """,
                bindings: [.text(accountID), .real(now), .real(now)]
            )
            try database.execute(
                """
                INSERT INTO courses
                  (id, source_account_id, source_object_id, name, code, term, time_zone,
                   source_state, first_seen_at, last_seen_at)
                VALUES (?, ?, 'stage10-course', 'Stage 10 Test', 'ST10', '', 'Asia/Macau', 'active', ?, ?)
                ON CONFLICT(source_account_id, source_object_id) DO UPDATE SET last_seen_at=excluded.last_seen_at
                """,
                bindings: [.text(courseID), .text(accountID), .real(now), .real(now)]
            )
            try database.execute(
                """
                INSERT INTO learning_tasks
                  (id, source_account_id, source_object_id, course_id, title, official_type,
                   official_due_at, official_due_time_zone, source_state, first_seen_at, last_seen_at)
                VALUES (?, ?, 'stage10-task', ?, ?, 'assignment', ?, 'Asia/Macau', 'active', ?, ?)
                ON CONFLICT(source_account_id, source_object_id) DO UPDATE SET
                  title=excluded.title, official_due_at=excluded.official_due_at,
                  official_due_time_zone=excluded.official_due_time_zone, source_state='active',
                  last_seen_at=excluded.last_seen_at
                """,
                bindings: [
                    .text(taskID), .text(accountID), .text(courseID), .text(title),
                    .real(startsAt.timeIntervalSince1970), .real(now), .real(now)
                ]
            )
        }
    }

    private static func requireBinding(_ database: SQLiteDatabase) throws -> CalendarBindingRecord {
        guard let binding = try CalendarPersistence(database: database).binding(
            objectType: objectType, objectID: taskID
        ), binding.syncState == "synced" else {
            throw AcceptanceError.lifecycleStateMissing
        }
        return binding
    }

    private static func verifiedEventCount(
        database: SQLiteDatabase,
        store: EventKitEventStore,
        identity: ManagedCalendarIdentity
    ) async throws -> Int {
        let binding = try requireBinding(database)
        guard let row = try database.query(
            "SELECT official_due_at FROM learning_tasks WHERE id=?", bindings: [.text(taskID)]
        ).first, let timestamp = row.double("official_due_at") else {
            throw AcceptanceError.lifecycleStateMissing
        }
        return await store.events(
            calendarIdentifier: identity.calendarIdentifier,
            around: Date(timeIntervalSince1970: timestamp),
            ownershipMarker: binding.ownershipMarker
        ).count
    }

    private static func lifecycleStart() -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func createControl(
        identity: ManagedCalendarIdentity,
        store: EventKitEventStore,
        stateURL: URL
    ) async throws -> ControlState {
        let calendar = try await store.createCalendar(
            title: "Campus Dashboard — Stage 10 Control",
            sourceIdentifier: identity.sourceIdentifier
        )
        guard calendar.source.kind == .iCloud else {
            try? await store.removeCalendar(identifier: calendar.identifier)
            throw AcceptanceError.iCloudCalendarNotConfigured
        }
        let start = lifecycleStart().addingTimeInterval(14_400)
        let marker = "stage10-control:\(UUID().uuidString.lowercased())"
        do {
            let event = try await store.saveEvent(
                CalendarEventDraft(
                    title: "Campus Dashboard Stage 10 Control",
                    startsAt: start, endsAt: start.addingTimeInterval(1_800),
                    isAllDay: false, location: nil, sourceURL: nil,
                    ownershipMarker: marker
                ),
                calendarIdentifier: calendar.identifier,
                existingEventIdentifier: nil
            )
            let state = ControlState(
                calendarIdentifier: calendar.identifier,
                sourceIdentifier: identity.sourceIdentifier,
                eventIdentifier: event.identifier,
                externalEventIdentifier: event.externalIdentifier,
                ownershipMarker: marker,
                startsAt: start.timeIntervalSince1970
            )
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
            return state
        } catch {
            try? await store.removeCalendar(identifier: calendar.identifier)
            throw error
        }
    }

    private static func verifyStoredControl(
        directory: URL,
        store: EventKitEventStore
    ) async throws {
        try await verifyControl(
            loadState(from: directory.appendingPathComponent("stage10-calendar-acceptance-state.json")),
            store: store
        )
    }

    private static func loadState(from url: URL) throws -> ControlState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AcceptanceError.controlStateMissing
        }
        return try JSONDecoder().decode(ControlState.self, from: Data(contentsOf: url))
    }

    private static func verifyControl(
        _ state: ControlState,
        store: EventKitEventStore
    ) async throws {
        let event: CalendarStoredEvent?
        if let direct = await store.event(identifier: state.eventIdentifier) {
            event = direct
        } else if let external = state.externalEventIdentifier {
            let candidates = await store.events(
                externalIdentifier: external, calendarIdentifier: state.calendarIdentifier
            )
            guard candidates.count <= 1 else { throw AcceptanceError.controlChanged }
            event = candidates.first
        } else {
            event = nil
        }
        guard let event,
              event.calendarIdentifier == state.calendarIdentifier,
              event.calendarSourceIdentifier == state.sourceIdentifier,
              event.ownershipMarker == state.ownershipMarker,
              event.title == "Campus Dashboard Stage 10 Control",
              event.startsAt == Date(timeIntervalSince1970: state.startsAt),
              event.endsAt == Date(timeIntervalSince1970: state.startsAt + 1_800) else {
            throw AcceptanceError.controlChanged
        }
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.campusdashboard.desktop", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func aggregateCount(_ database: SQLiteDatabase, sql: String) throws -> Int64 {
        guard let value = try database.query(sql).first?.int("value") else {
            throw AcceptanceError.lifecycleStateMissing
        }
        return value
    }

    private static func write(_ value: String, to path: String) throws {
        try Data((value + "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func safeCategory(_ error: Error) -> String {
        if let error = error as? AcceptanceError { return error.rawValue }
        if let error = error as? CampusCalendarError { return String(describing: error) }
        if error is DatabaseError { return "persistence" }
        return "acceptance_unavailable"
    }
}

private enum AcceptanceError: String, Error {
    case iCloudCalendarNotConfigured = "icloud_calendar_not_configured"
    case dedicatedCalendarInvalid = "dedicated_calendar_invalid"
    case lifecycleStateMissing = "lifecycle_state_missing"
    case eventCountMismatch = "event_count_mismatch"
    case bindingContinuityFailed = "binding_continuity_failed"
    case controlStateMissing = "control_state_missing"
    case controlChanged = "control_changed"
}

private struct ControlState: Codable {
    let calendarIdentifier: String
    let sourceIdentifier: String
    let eventIdentifier: String
    let externalEventIdentifier: String?
    let ownershipMarker: String
    let startsAt: TimeInterval
}
