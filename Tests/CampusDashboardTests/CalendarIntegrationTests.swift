import Foundation
import Testing
@testable import CampusDashboard

@Suite("Apple Calendar integration")
struct CalendarIntegrationTests {
    private let localSource = CalendarSourceDescriptor(identifier: "source-local", title: "On My Mac", kind: .local)
    private let cloudSource = CalendarSourceDescriptor(identifier: "source-cloud", title: "iCloud", kind: .iCloud)

    @Test("Permission denial and later revocation remain isolated from configuration")
    func permissionDeniedAndRevoked() async throws {
        try await withDatabase { database in
            let store = FakeCalendarEventStore(status: .denied, sources: [localSource])
            let service = CampusCalendarService(database: database, store: store)
            await #expect(throws: CampusCalendarError.permissionDenied) {
                try await service.availableSources()
            }
            await store.setStatus(.fullAccess)
            await store.setCalendars([calendar("dedicated", "Campus Dashboard", localSource)])
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            await store.setStatus(.denied)
            #expect(try await service.validateDedicatedCalendar() == .permissionRevoked)
            await #expect(throws: CampusCalendarError.permissionRevoked) {
                try await service.apply([.upsert(objectType: "learning_task", objectID: "missing")])
            }
        }
    }

    @Test("A permission failure leaves outbox work pending and replays once after access is restored")
    func permissionRetry() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", localSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [localSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000)
            try insertOutbox(database, id: "work-1", objectID: "task-1")
            let processor = OutboxProcessor(
                database: database, calendar: service, notifications: FakeNotificationService(),
                clock: FixedClock(now: Date(timeIntervalSince1970: 20_000))
            )
            await store.setStatus(.denied)
            #expect(await processor.processPending() == 0)
            #expect(try database.scalarInt("SELECT attempt_count AS value FROM outbox_work") == 1)
            #expect(await store.eventsInCalendar("dedicated").isEmpty)
            await store.setStatus(.fullAccess)
            try database.execute("UPDATE outbox_work SET available_at = 1")
            #expect(await processor.processPending() == 1)
            #expect(await store.eventsInCalendar("dedicated").count == 1)
        }
    }

    @Test("Lost identifier and duplicate names never cause automatic calendar adoption")
    func duplicateNamesAndLostIdentifier() async throws {
        try await withDatabase { database in
            let original = calendar("original", "Campus Dashboard", cloudSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [cloudSource], calendars: [original])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: original.identifier)
            await store.setCalendars([calendar("single-candidate", "Campus Dashboard", cloudSource)])
            #expect(try await service.validateDedicatedCalendar() == .missing)
            #expect(try await service.recoveryCandidates().count == 1)
            await store.setCalendars([
                calendar("same-name-1", "Campus Dashboard", cloudSource),
                calendar("same-name-2", "Campus Dashboard", cloudSource)
            ])
            #expect(try await service.validateDedicatedCalendar() == .ambiguous)
            #expect(try await service.recoveryCandidates().count == 2)
            await #expect(throws: CampusCalendarError.ambiguousCalendarCandidates) {
                try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "x")])
            }
        }
    }

    @Test("The app creates and persists the exact dedicated calendar returned by the chosen source")
    func createDedicatedCalendar() async throws {
        try await withDatabase { database in
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [localSource])
            let service = CampusCalendarService(database: database, store: store)
            let identity = try await service.createDedicatedCalendar(sourceIdentifier: localSource.identifier)
            #expect(identity.selectionKind == .appCreated)
            #expect(identity.calendarTitle == "Campus Dashboard")
            #expect(identity.sourceIdentifier == localSource.identifier)
            #expect(await store.calendars().map(\.identifier) == [identity.calendarIdentifier])
        }
    }

    @Test("Local and iCloud source identity is persisted and unwritable calendars are rejected")
    func sourceIdentityAndWritability() async throws {
        try await withDatabase { database in
            let store = FakeCalendarEventStore(
                status: .fullAccess,
                sources: [localSource, cloudSource],
                calendars: [
                    calendar("local", "Campus Dashboard", localSource),
                    calendar("cloud", "Campus Dashboard", cloudSource),
                    calendar("readonly", "Campus Dashboard", cloudSource, writable: false)
                ]
            )
            let service = CampusCalendarService(database: database, store: store)
            let local = try await service.selectDedicatedCalendar(calendarIdentifier: "local")
            #expect(!local.isICloud)
            let cloud = try await service.selectDedicatedCalendar(calendarIdentifier: "cloud")
            #expect(cloud.isICloud)
            #expect(try await service.configuredIdentity()?.sourceIdentifier == cloudSource.identifier)
            await #expect(throws: CampusCalendarError.calendarUnwritable) {
                try await service.selectDedicatedCalendar(calendarIdentifier: "readonly")
            }
        }
    }

    @Test("Create, update, cancel, and outbox replay are idempotent and leave unrelated events untouched")
    func lifecycleAndReplay() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let otherCalendar = calendar("personal", "Personal", cloudSource)
            let store = FakeCalendarEventStore(
                status: .fullAccess, sources: [cloudSource], calendars: [dedicated, otherCalendar]
            )
            await store.seedUnrelatedEvent(calendarIdentifier: otherCalendar.identifier)
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: dedicated.identifier)
            try insertTask(database, id: "task-1", dueAt: 10_000, title: "Original")
            try insertOutbox(database, id: "work-1", objectID: "task-1")
            let processor = OutboxProcessor(
                database: database, calendar: service, notifications: FakeNotificationService(),
                clock: FixedClock(now: Date(timeIntervalSince1970: 20_000))
            )

            #expect(await processor.processPending() == 1)
            #expect(await store.eventsInCalendar("dedicated").count == 1)
            // Simulate EventKit succeeding immediately before the binding commit.
            try database.execute("DELETE FROM calendar_bindings WHERE object_id = 'task-1'")
            try database.execute("UPDATE outbox_work SET state = 'pending'")
            #expect(await processor.processPending() == 1)
            #expect(await store.eventsInCalendar("dedicated").count == 1)

            try database.execute(
                "UPDATE learning_tasks SET title = 'Updated', official_due_at = 11000 WHERE id = 'task-1'"
            )
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            let updated = try #require(await store.eventsInCalendar("dedicated").first)
            #expect(updated.title.contains("Updated"))
            #expect(updated.startsAt == Date(timeIntervalSince1970: 11_000))
            #expect(await store.eventsInCalendar("dedicated").count == 1)

            _ = try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "task-1")])
            _ = try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "task-1")])
            #expect(await store.eventsInCalendar("dedicated").isEmpty)
            #expect(await store.eventsInCalendar("personal").count == 1)
        }
    }

    @Test("External identifier recovery updates an event after its internal ID and time both change")
    func externalIdentifierRecoversUpdateBeyondMarkerWindow() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [cloudSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000, title: "Original")
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            let original = try #require(await store.eventsInCalendar("dedicated").first)
            let externalIdentifier = try #require(original.externalIdentifier)
            _ = try #require(await store.rotateInternalIdentifier(
                in: "dedicated", to: "event-after-full-sync"
            ))
            try database.execute(
                "UPDATE learning_tasks SET title = 'Far Future', official_due_at = 1000000 WHERE id = 'task-1'"
            )

            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])

            let events = await store.eventsInCalendar("dedicated")
            let updated = try #require(events.first)
            #expect(events.count == 1)
            #expect(updated.identifier == "event-after-full-sync")
            #expect(updated.externalIdentifier == externalIdentifier)
            #expect(updated.startsAt == Date(timeIntervalSince1970: 1_000_000))
            let storedBinding = try CalendarPersistence(database: database).binding(
                objectType: "learning_task", objectID: "task-1"
            )
            let binding = try #require(storedBinding)
            #expect(binding.eventIdentifier == "event-after-full-sync")
            #expect(binding.externalEventIdentifier == externalIdentifier)
        }
    }

    @Test("External identifier recovery deletes the original event after its internal ID changes")
    func externalIdentifierRecoversCancel() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [cloudSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000)
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            let original = try #require(await store.eventsInCalendar("dedicated").first)
            let externalIdentifier = try #require(original.externalIdentifier)
            _ = try #require(await store.rotateInternalIdentifier(
                in: "dedicated", to: "event-after-full-sync"
            ))

            _ = try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "task-1")])

            #expect(await store.eventsInCalendar("dedicated").isEmpty)
            let storedBinding = try CalendarPersistence(database: database).binding(
                objectType: "learning_task", objectID: "task-1"
            )
            let binding = try #require(storedBinding)
            #expect(binding.eventIdentifier == "event-after-full-sync")
            #expect(binding.externalEventIdentifier == externalIdentifier)
            #expect(binding.syncState == "removed")
        }
    }

    @Test("External recovery rejects another calendar and an incorrect ownership marker")
    func externalIdentifierScopeAndMarkerProtection() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let personal = calendar("personal", "Personal", cloudSource)
            let store = FakeCalendarEventStore(
                status: .fullAccess, sources: [cloudSource], calendars: [dedicated, personal]
            )
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000)
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            await store.moveFirstEvent(from: "dedicated", to: "personal")

            await #expect(throws: CampusCalendarError.eventRecoveryUnavailable) {
                try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "task-1")])
            }
            #expect(await store.eventsInCalendar("personal").count == 1)
        }

        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [cloudSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000)
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            _ = try #require(await store.rotateInternalIdentifier(
                in: "dedicated", to: "event-after-full-sync"
            ))
            await store.corruptOwnershipMarker(in: "dedicated")

            await #expect(throws: CampusCalendarError.staleBinding) {
                try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "task-1")])
            }
            #expect(await store.eventsInCalendar("dedicated").count == 1)
        }
    }

    @Test("Multiple external identifier candidates fail closed")
    func ambiguousExternalIdentifier() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [cloudSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000)
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            _ = try #require(await store.rotateInternalIdentifier(
                in: "dedicated", to: "event-after-full-sync"
            ))
            await store.duplicateFirstExternalCandidate(in: "dedicated", identifier: "event-duplicate")

            await #expect(throws: CampusCalendarError.ambiguousExternalIdentifier) {
                try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            }
            #expect(await store.eventsInCalendar("dedicated").count == 2)
        }
    }

    @Test("Missing external ID uses only a scoped marker fallback and otherwise fails closed")
    func missingExternalIdentifierFallback() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [cloudSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000)
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            try database.execute(
                "UPDATE calendar_bindings SET external_event_identifier = NULL WHERE object_id = 'task-1'"
            )
            _ = try #require(await store.rotateInternalIdentifier(
                in: "dedicated", to: "event-marker-recovery"
            ))

            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            #expect(await store.eventsInCalendar("dedicated").count == 1)
            let storedBinding = try CalendarPersistence(database: database).binding(
                objectType: "learning_task", objectID: "task-1"
            )
            let repaired = try #require(storedBinding)
            #expect(repaired.eventIdentifier == "event-marker-recovery")
            #expect(repaired.externalEventIdentifier != nil)

            try database.execute(
                "UPDATE calendar_bindings SET external_event_identifier = NULL WHERE object_id = 'task-1'"
            )
            _ = try #require(await store.rotateInternalIdentifier(
                in: "dedicated", to: "event-no-safe-recovery"
            ))
            try database.execute("UPDATE learning_tasks SET official_due_at = 1000000 WHERE id = 'task-1'")

            await #expect(throws: CampusCalendarError.eventRecoveryUnavailable) {
                try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            }
            let events = await store.eventsInCalendar("dedicated")
            #expect(events.count == 1)
            #expect(events.first?.identifier == "event-no-safe-recovery")
        }
    }

    @Test("Stale binding and an event whose marker changed are both rejected")
    func staleBindingProtection() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", localSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [localSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000)
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            try database.execute(
                "UPDATE calendar_bindings SET calendar_identifier = 'other' WHERE object_id = 'task-1'"
            )
            await #expect(throws: CampusCalendarError.staleBinding) {
                try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "task-1")])
            }
            #expect(await store.eventsInCalendar("dedicated").count == 1)
            try database.execute(
                "UPDATE calendar_bindings SET calendar_identifier = 'dedicated' WHERE object_id = 'task-1'"
            )
            await store.corruptOwnershipMarker(in: "dedicated")
            await #expect(throws: CampusCalendarError.staleBinding) {
                try await service.apply([.removeBoundEvent(objectType: "learning_task", objectID: "task-1")])
            }
            #expect(await store.eventsInCalendar("dedicated").count == 1)
        }
    }

    @Test("Eligible course meetings create and cancel only their bound event")
    func courseMeetingLifecycle() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", localSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [localSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertMeeting(database)
            _ = try await service.apply([.upsert(objectType: "course_meeting", objectID: "meeting-1")])
            #expect(await store.eventsInCalendar("dedicated").count == 1)
            try database.execute("UPDATE course_meetings SET source_state = 'cancelled' WHERE id = 'meeting-1'")
            _ = try await service.apply([.upsert(objectType: "course_meeting", objectID: "meeting-1")])
            #expect(await store.eventsInCalendar("dedicated").isEmpty)
        }
    }

    @Test("Unconfirmed inferred dates are rejected at the Calendar boundary")
    func inferredDateGate() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", localSource)
            let store = FakeCalendarEventStore(status: .fullAccess, sources: [localSource], calendars: [dedicated])
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: nil, suggestedAt: 10_000, confirmedAt: nil)
            await #expect(throws: CampusCalendarError.unconfirmedInferredDate) {
                try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            }
            #expect(await store.eventsInCalendar("dedicated").isEmpty)
            try database.execute("UPDATE learning_tasks SET suggestion_confirmed_at = 9000 WHERE id = 'task-1'")
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            #expect(await store.eventsInCalendar("dedicated").count == 1)
        }
    }

    @Test("Calendar cleanup stays separate, previewable, and limited to revalidated app-owned bindings")
    func previewableCalendarCleanup() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", cloudSource)
            let personal = calendar("personal", "Personal", cloudSource)
            let store = FakeCalendarEventStore(
                status: .fullAccess, sources: [cloudSource], calendars: [dedicated, personal]
            )
            await store.seedUnrelatedEvent(calendarIdentifier: "personal")
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            try insertTask(database, id: "task-1", dueAt: 10_000, title: "Synthetic cleanup item")
            _ = try await service.apply([.upsert(objectType: "learning_task", objectID: "task-1")])
            try database.execute(
                """
                INSERT INTO calendar_bindings
                  (id, object_type, object_id, event_identifier, external_event_identifier,
                   ownership_marker, calendar_identifier, calendar_source_identifier, sync_state)
                VALUES ('00000000-0000-0000-0000-000000000099', 'learning_task', 'foreign-object',
                  'unrelated', 'external-unrelated', 'foreign-marker', 'personal', 'source-cloud', 'synced')
                """
            )

            // Ordinary source-cache clearing retains both Calendar events and bindings.
            _ = try PrivacyDiagnosticsService(database: database).clear(.sourceCache)
            #expect(await store.eventsInCalendar("dedicated").count == 1)
            #expect(await store.eventsInCalendar("personal").count == 1)

            let preview = try await service.cleanupPreview()
            #expect(preview.count == 1)
            #expect(preview.first?.objectID == "task-1")
            #expect(try await service.cleanupPreviewedEvents(bindingIDs: Set(preview.map(\.id))) == 1)
            #expect(await store.eventsInCalendar("dedicated").isEmpty)
            #expect(await store.eventsInCalendar("personal").count == 1)
            #expect(try database.query(
                "SELECT sync_state FROM calendar_bindings WHERE object_id='foreign-object'"
            ).first?.string("sync_state") == "synced")
        }
    }

    @Test("Academic exam preview writes exactly one owned event only after confirmation and undo removes it")
    func academicExamPreviewAndReconciliation() async throws {
        try await withDatabase { database in
            let dedicated = calendar("dedicated", "Campus Dashboard", localSource)
            let store = FakeCalendarEventStore(
                status: .fullAccess, sources: [localSource], calendars: [dedicated]
            )
            let service = CampusCalendarService(database: database, store: store)
            _ = try await service.selectDedicatedCalendar(calendarIdentifier: "dedicated")
            let signalID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
            try insertAcademicExam(database, signalID: signalID)

            let preview = try await service.previewAcademicSignal(signalID: signalID)
            #expect(preview.operation == .create)
            #expect(preview.semantic == .exam)
            #expect(preview.displayMarker == "[EXAM]")
            #expect(preview.calendarTitle == "Campus Dashboard")
            #expect(await store.eventsInCalendar("dedicated").isEmpty)

            try database.execute(
                "UPDATE academic_signals SET confirmation_state='confirmed' WHERE id=?",
                bindings: [.text(signalID.uuidString)]
            )
            _ = try await service.reconcileAcademicSignal(signalID: signalID)
            _ = try await service.reconcileAcademicSignal(signalID: signalID)
            let events = await store.eventsInCalendar("dedicated")
            #expect(events.count == 1)
            #expect(events.first?.title.contains("[EXAM]") == true)

            try database.execute(
                "UPDATE academic_signals SET confirmation_state='pending' WHERE id=?",
                bindings: [.text(signalID.uuidString)]
            )
            _ = try await service.reconcileAcademicSignal(signalID: signalID)
            #expect(await store.eventsInCalendar("dedicated").isEmpty)
        }
    }

    private func calendar(
        _ id: String, _ title: String, _ source: CalendarSourceDescriptor, writable: Bool = true
    ) -> CalendarDescriptor {
        CalendarDescriptor(identifier: id, title: title, source: source, allowsContentModifications: writable)
    }

    private func withDatabase(
        _ operation: (SQLiteDatabase) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-calendar-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await operation(try SQLiteDatabase(path: directory.appendingPathComponent("test.sqlite3").path))
    }

    private func insertTask(
        _ database: SQLiteDatabase,
        id: String,
        dueAt: Double?,
        title: String = "Deadline",
        suggestedAt: Double? = nil,
        confirmedAt: Double? = nil
    ) throws {
        try database.execute(
            """
            INSERT INTO source_accounts
              (id, source_kind, instance_url, display_name, authorization_state, created_at, updated_at)
            VALUES ('account', 'Canvas', 'https://canvas.invalid', 'Synthetic', 'connected', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO courses
              (id, source_account_id, source_object_id, name, code, term, time_zone,
               source_state, first_seen_at, last_seen_at)
            VALUES ('course', 'account', 'course-source', 'Synthetic Course', 'SYN', 'Term', 'UTC', 'active', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO learning_tasks
              (id, source_account_id, source_object_id, course_id, title, official_type,
               official_due_at, suggested_complete_at, suggestion_origin, suggestion_confirmed_at,
               source_state, first_seen_at, last_seen_at)
            VALUES (?, 'account', ?, 'course', ?, 'assignment', ?, ?, 'inferred', ?, 'active', 1, 1)
            """,
            bindings: [
                .text(id), .text("source-\(id)"), .text(title),
                dueAt.map(SQLiteValue.real) ?? .null, suggestedAt.map(SQLiteValue.real) ?? .null,
                confirmedAt.map(SQLiteValue.real) ?? .null
            ]
        )
    }

    private func insertOutbox(_ database: SQLiteDatabase, id: String, objectID: String) throws {
        let payload = Data(
            "{\"operation\":\"calendarUpsert\",\"objectType\":\"learning_task\",\"objectID\":\"\(objectID)\"}".utf8
        )
        try database.execute(
            """
            INSERT INTO outbox_work
              (id, kind, deduplication_key, object_type, object_id, payload, state,
               available_at, created_at, updated_at)
            VALUES (?, 'calendar.upsert', ?, 'learning_task', ?, ?, 'pending', 1, 1, 1)
            """,
            bindings: [.text(id), .text("dedupe-\(id)"), .text(objectID), .blob(payload)]
        )
    }

    private func insertAcademicExam(_ database: SQLiteDatabase, signalID: UUID) throws {
        try database.execute(
            "INSERT INTO source_accounts(id,source_kind,instance_url,display_name,authorization_state,created_at,updated_at) VALUES('account','Canvas','https://canvas.invalid','Synthetic','connected',1,1)"
        )
        try database.execute(
            "INSERT INTO courses(id,source_account_id,source_object_id,name,code,term,time_zone,source_state,first_seen_at,last_seen_at) VALUES('course','account','course-source','Synthetic Course','SYN','Term','UTC','active',1,1)"
        )
        try database.execute(
            "INSERT INTO announcements(id,source_account_id,source_object_id,course_id,title,published_at,summary,content_hash,source_state,first_seen_at,last_seen_at) VALUES('announcement','account','announcement-source','course','Synthetic exam',1,'Synthetic','hash','active',1,1)"
        )
        try database.execute(
            "INSERT INTO raw_source_records(id,source_account_id,object_type,source_object_id,fetch_batch_id,content_hash,payload,fetched_at) VALUES('raw','account','announcement','announcement-source','batch','hash',X'7B7D',1)"
        )
        try database.execute(
            "INSERT INTO academic_signal_analyses(id,raw_source_record_id,announcement_id,source_account_id,source_object_id,content_hash,primary_category,status,provider,model,prompt_version,schema_version,created_at,updated_at) VALUES('analysis','raw','announcement','account','announcement-source','hash','exam_time','analyzed','deterministic','local','v1','v1',1,1)"
        )
        try database.execute(
            "INSERT INTO academic_signals(id,analysis_id,announcement_id,source_account_id,source_object_id,category,evidence,key_requirement,inferred_date,is_all_day,time_zone_identifier,confidence,reason,provider,model,prompt_version,schema_version,confirmation_state,course_id,created_at,updated_at) VALUES(?,'analysis','announcement','account','announcement-source','exam_time','exam','Attend exam',20000,0,'UTC',0.9,'Synthetic','deterministic','local','v1','v1','pending','course',1,1)",
            bindings: [.text(signalID.uuidString)]
        )
    }

    private func insertMeeting(_ database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO source_accounts
              (id, source_kind, instance_url, display_name, authorization_state, created_at, updated_at)
            VALUES ('account', 'SIweb', 'https://siweb.invalid', 'Synthetic', 'connected', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO courses
              (id, source_account_id, source_object_id, name, code, term, time_zone,
               source_state, first_seen_at, last_seen_at)
            VALUES ('course', 'account', 'course-source', 'Synthetic Course', 'SYN', 'Term', 'UTC', 'active', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO course_meetings
              (id, course_id, source_object_id, starts_at, ends_at, original_time_zone,
               location, source_state)
            VALUES ('meeting-1', 'course', 'meeting-source', 10000, 10600, 'UTC', 'Room 1', 'active')
            """
        )
    }
}

private actor FakeCalendarEventStore: CalendarEventStore {
    private var status: CalendarAccessStatus
    private var sourceValues: [CalendarSourceDescriptor]
    private var calendarValues: [CalendarDescriptor]
    private var eventValues: [String: CalendarStoredEvent] = [:]
    private var nextEventID = 1

    init(
        status: CalendarAccessStatus,
        sources: [CalendarSourceDescriptor],
        calendars: [CalendarDescriptor] = []
    ) {
        self.status = status
        self.sourceValues = sources
        self.calendarValues = calendars
    }

    func setStatus(_ status: CalendarAccessStatus) { self.status = status }
    func setCalendars(_ calendars: [CalendarDescriptor]) { calendarValues = calendars }
    func authorizationStatus() -> CalendarAccessStatus { status }
    func requestFullAccess() -> Bool { status == .fullAccess }
    func sources() -> [CalendarSourceDescriptor] { sourceValues }
    func calendars() -> [CalendarDescriptor] { calendarValues }

    func createCalendar(title: String, sourceIdentifier: String) throws -> CalendarDescriptor {
        guard let source = sourceValues.first(where: { $0.identifier == sourceIdentifier }) else {
            throw CampusCalendarError.invalidSelection
        }
        let value = CalendarDescriptor(
            identifier: "created-\(calendarValues.count + 1)", title: title,
            source: source, allowsContentModifications: true
        )
        calendarValues.append(value)
        return value
    }

    func removeCalendar(identifier: String) {
        calendarValues.removeAll { $0.identifier == identifier }
        eventValues = eventValues.filter { $0.value.calendarIdentifier != identifier }
    }

    func event(identifier: String) -> CalendarStoredEvent? { eventValues[identifier] }

    func events(externalIdentifier: String, calendarIdentifier: String) -> [CalendarStoredEvent] {
        eventValues.values.filter {
            $0.externalIdentifier == externalIdentifier && $0.calendarIdentifier == calendarIdentifier
        }
    }

    func events(
        calendarIdentifier: String,
        around date: Date,
        ownershipMarker: String
    ) -> [CalendarStoredEvent] {
        eventValues.values.filter {
            $0.calendarIdentifier == calendarIdentifier && $0.ownershipMarker == ownershipMarker &&
            abs($0.startsAt.timeIntervalSince(date)) <= 172_800
        }
    }

    func saveEvent(
        _ draft: CalendarEventDraft,
        calendarIdentifier: String,
        existingEventIdentifier: String?
    ) throws -> CalendarStoredEvent {
        guard calendarValues.contains(where: {
            $0.identifier == calendarIdentifier && $0.allowsContentModifications
        }) else { throw CampusCalendarError.calendarUnwritable }
        let calendar = calendarValues.first { $0.identifier == calendarIdentifier }!
        let identifier: String
        if let existingEventIdentifier {
            guard let existing = eventValues[existingEventIdentifier] else {
                throw CampusCalendarError.eventRecoveryUnavailable
            }
            guard existing.calendarIdentifier == calendarIdentifier,
                  existing.calendarSourceIdentifier == calendar.source.identifier,
                  existing.ownershipMarker == draft.ownershipMarker else {
                throw CampusCalendarError.staleBinding
            }
            identifier = existingEventIdentifier
        } else {
            identifier = "event-\(nextEventID)"
            nextEventID += 1
        }
        let externalIdentifier = existingEventIdentifier.flatMap { eventValues[$0]?.externalIdentifier }
            ?? "external-\(identifier)"
        let event = CalendarStoredEvent(
            identifier: identifier, externalIdentifier: externalIdentifier,
            calendarIdentifier: calendarIdentifier,
            calendarSourceIdentifier: calendar.source.identifier,
            ownershipMarker: draft.ownershipMarker,
            title: draft.title, startsAt: draft.startsAt, endsAt: draft.endsAt
        )
        eventValues[identifier] = event
        return event
    }

    func removeEvent(
        identifier: String,
        calendarIdentifier: String,
        calendarSourceIdentifier: String,
        ownershipMarker: String,
        externalIdentifier: String?
    ) throws {
        guard let event = eventValues[identifier] else {
            throw CampusCalendarError.eventRecoveryUnavailable
        }
        guard event.calendarIdentifier == calendarIdentifier,
              event.calendarSourceIdentifier == calendarSourceIdentifier,
              event.ownershipMarker == ownershipMarker else { throw CampusCalendarError.staleBinding }
        if let externalIdentifier {
            guard event.externalIdentifier == externalIdentifier else { throw CampusCalendarError.staleBinding }
        }
        eventValues.removeValue(forKey: identifier)
    }

    func eventsInCalendar(_ identifier: String) -> [CalendarStoredEvent] {
        eventValues.values.filter { $0.calendarIdentifier == identifier }
    }

    func seedUnrelatedEvent(calendarIdentifier: String) {
        eventValues["unrelated"] = CalendarStoredEvent(
            identifier: "unrelated", externalIdentifier: "external-unrelated",
            calendarIdentifier: calendarIdentifier,
            calendarSourceIdentifier: calendarValues.first { $0.identifier == calendarIdentifier }!.source.identifier,
            ownershipMarker: nil, title: "Personal",
            startsAt: Date(timeIntervalSince1970: 10_000), endsAt: Date(timeIntervalSince1970: 10_600)
        )
    }

    func corruptOwnershipMarker(in calendarIdentifier: String) {
        guard let pair = eventValues.first(where: { $0.value.calendarIdentifier == calendarIdentifier }) else { return }
        let event = pair.value
        eventValues[pair.key] = CalendarStoredEvent(
            identifier: event.identifier, externalIdentifier: event.externalIdentifier,
            calendarIdentifier: event.calendarIdentifier,
            calendarSourceIdentifier: event.calendarSourceIdentifier,
            ownershipMarker: "changed-by-someone-else",
            title: event.title, startsAt: event.startsAt, endsAt: event.endsAt
        )
    }

    @discardableResult
    func rotateInternalIdentifier(
        in calendarIdentifier: String,
        to newIdentifier: String,
        startsAt: Date? = nil
    ) -> CalendarStoredEvent? {
        guard let pair = eventValues.first(where: { $0.value.calendarIdentifier == calendarIdentifier }) else {
            return nil
        }
        eventValues.removeValue(forKey: pair.key)
        let old = pair.value
        let event = CalendarStoredEvent(
            identifier: newIdentifier, externalIdentifier: old.externalIdentifier,
            calendarIdentifier: old.calendarIdentifier,
            calendarSourceIdentifier: old.calendarSourceIdentifier,
            ownershipMarker: old.ownershipMarker, title: old.title,
            startsAt: startsAt ?? old.startsAt, endsAt: old.endsAt
        )
        eventValues[newIdentifier] = event
        return event
    }

    func moveFirstEvent(from sourceCalendarIdentifier: String, to targetCalendarIdentifier: String) {
        guard let pair = eventValues.first(where: { $0.value.calendarIdentifier == sourceCalendarIdentifier }),
              let target = calendarValues.first(where: { $0.identifier == targetCalendarIdentifier }) else { return }
        eventValues.removeValue(forKey: pair.key)
        let old = pair.value
        eventValues["moved-\(old.identifier)"] = CalendarStoredEvent(
            identifier: "moved-\(old.identifier)", externalIdentifier: old.externalIdentifier,
            calendarIdentifier: target.identifier, calendarSourceIdentifier: target.source.identifier,
            ownershipMarker: old.ownershipMarker, title: old.title,
            startsAt: old.startsAt, endsAt: old.endsAt
        )
    }

    func duplicateFirstExternalCandidate(in calendarIdentifier: String, identifier: String) {
        guard let old = eventValues.first(where: { $0.value.calendarIdentifier == calendarIdentifier })?.value else {
            return
        }
        eventValues[identifier] = CalendarStoredEvent(
            identifier: identifier, externalIdentifier: old.externalIdentifier,
            calendarIdentifier: old.calendarIdentifier,
            calendarSourceIdentifier: old.calendarSourceIdentifier,
            ownershipMarker: old.ownershipMarker, title: old.title,
            startsAt: old.startsAt, endsAt: old.endsAt
        )
    }
}
