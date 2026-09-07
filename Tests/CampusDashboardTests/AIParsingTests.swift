import Foundation
import Testing
@testable import CampusDashboard

@Suite("Controlled AI parsing and confirmation")
struct AIParsingTests {
    @Test("AI defaults off while deterministic rules remain usable")
    func disabledDeterministicPath() async throws {
        try await withDatabase { database in
            let capture = CapturingProvider(data: Data("not-json".utf8))
            let coordinator = AIParsingCoordinator(database: database, provider: capture)
            let settings = try coordinator.settings()
            #expect(settings.enabled == false)
            let outcome = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input(title: "Quiz 2"))
            #expect(outcome.deterministicType == "quiz")
            #expect(outcome.parseResult == nil)
            #expect(capture.calls == 0)
        }
    }

    @Test("Strict schema rejects malformed output without blocking deterministic processing")
    func invalidOutputFailsSafe() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            let provider = CapturingProvider(data: Data(#"{"confidence":2}"#.utf8))
            let coordinator = AIParsingCoordinator(database: database, provider: provider)
            try coordinator.setEnabled(true)
            let outcome = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            #expect(outcome.deterministicType == "assignment")
            #expect(outcome.parseResult == nil)
            #expect(outcome.failureCategory == "invalid_output")
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM ai_parse_results WHERE confirmation_state='failed'") == 1)
        }
    }

    @Test("Provider is restricted to Canvas records")
    func canvasOnly() async throws {
        try await withDatabase { database in
            let provider = try CapturingProvider(response: TestData.response())
            let coordinator = AIParsingCoordinator(database: database, provider: provider)
            try coordinator.setEnabled(true)
            let outcome = await coordinator.process(
                rawSourceRecordID: TestData.rawID, input: TestData.input(source: .siweb)
            )
            #expect(outcome.failureCategory == "unsupported_source")
            #expect(provider.calls == 0)
        }
    }

    @Test("Committed Canvas raw records feed the confirmation queue")
    func persistedCanvasPipeline() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            let coordinator = AIParsingCoordinator(database: database)
            try coordinator.setEnabled(true)
            let outcomes = await coordinator.processPendingCanvasRecords()
            #expect(outcomes.count == 1)
            #expect(outcomes.first?.parseResult?.targetObjectID == "task-1")
            #expect(try coordinator.pendingConfirmations().count == 1)
            let repeated = await coordinator.processPendingCanvasRecords()
            #expect(repeated.isEmpty)
        }
    }

    @Test("Official dates are immutable and inferred dates require confirmation")
    func officialDateAndConfirmationGate() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            let suggested = Date(timeIntervalSince1970: 2_000)
            let provider = try CapturingProvider(response: TestData.response(suggestedDate: suggested, confidence: 1))
            let coordinator = AIParsingCoordinator(database: database, provider: provider, clock: FixedClock(now: Date(timeIntervalSince1970: 3_000)))
            try coordinator.setEnabled(true)
            let outcome = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            let record = try #require(outcome.parseResult)
            #expect(record.suggestedDateIsInferred)
            #expect(record.confirmationState == .pending)
            let before = try #require(database.query("SELECT * FROM learning_tasks WHERE id='task-1'").first)
            #expect(before.double("official_due_at") == 1_000)
            #expect(before.double("suggested_complete_at") == nil)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == 0)

            try coordinator.confirm(record.id)
            let after = try #require(database.query("SELECT * FROM learning_tasks WHERE id='task-1'").first)
            #expect(after.double("official_due_at") == 1_000)
            #expect(after.double("suggested_complete_at") == 2_000)
            #expect(after.string("suggestion_origin") == "ai_inferred")
            #expect(after.double("suggestion_confirmed_at") == 3_000)
            #expect(try coordinator.auditTrail(parseResultID: record.id).map(\.action) == [.confirm])
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == 1)
        }
    }

    @Test("Official date echoes that conflict with source data are rejected")
    func conflictingOfficialEcho() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            let response = AIProviderResponse(
                normalizedTitle: nil, suggestedType: nil,
                officialDateEcho: Date(timeIntervalSince1970: 999), suggestedDate: nil,
                relatedObjectIDs: [], actionItems: [], confidence: 0.9,
                rationale: "Synthetic conflict", hasConflict: false,
                changeSummary: "Conflict", uncertain: false
            )
            let coordinator = AIParsingCoordinator(database: database, provider: try CapturingProvider(response: response))
            try coordinator.setEnabled(true)
            let result = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            #expect(result.failureCategory == "invalid_output")
            #expect(try database.query("SELECT official_due_at FROM learning_tasks").first?.double("official_due_at") == 1_000)
        }
    }

    @Test("Consumed inferred-date Calendar work is removed on undo and replay stays idempotent")
    func calendarUndoAfterConsumption() async throws {
        try await withDatabase { database in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let suggested = now.addingTimeInterval(200_000)
            try TestData.seed(database, officialDueAt: nil)
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(
                    suggestedDate: suggested, officialDateEcho: nil
                )),
                clock: FixedClock(now: now)
            )
            try coordinator.setEnabled(true)
            let result = await coordinator.process(
                rawSourceRecordID: TestData.rawID,
                input: TestData.input(officialDueAt: nil)
            )
            let id = try #require(result.parseResult?.id)
            try coordinator.confirm(id)

            let calendar = InspectingCalendarService(database: database)
            let processor = OutboxProcessor(
                database: database, calendar: calendar,
                notifications: FakeNotificationService(), clock: FixedClock(now: now)
            )
            #expect(await processor.processPending() == 1)
            #expect(await calendar.eventDate == suggested)
            #expect(await calendar.createCount == 1)

            try coordinator.undo(id)
            #expect(await processor.processPending() == 1)
            #expect(await calendar.eventDate == nil)
            #expect(await calendar.removeCount == 1)

            try database.execute(
                "UPDATE outbox_work SET state='pending' WHERE deduplication_key LIKE '%:transition:2'"
            )
            #expect(await processor.processPending() == 1)
            #expect(await calendar.eventDate == nil)
            #expect(await calendar.removeCount == 1)
            let outboxCount = try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work")
            try coordinator.undo(id)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == outboxCount)
        }
    }

    @Test("Undo before Calendar consumption supersedes the stale upsert without retrying")
    func calendarUndoBeforeConsumption() async throws {
        try await withDatabase { database in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            try TestData.seed(database, officialDueAt: nil)
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(
                    suggestedDate: now.addingTimeInterval(200_000), officialDateEcho: nil
                )), clock: FixedClock(now: now)
            )
            try coordinator.setEnabled(true)
            let result = await coordinator.process(
                rawSourceRecordID: TestData.rawID,
                input: TestData.input(officialDueAt: nil)
            )
            let id = try #require(result.parseResult?.id)
            try coordinator.confirm(id)
            try coordinator.undo(id)

            let calendar = InspectingCalendarService(database: database)
            let processor = OutboxProcessor(
                database: database, calendar: calendar,
                notifications: FakeNotificationService(), clock: FixedClock(now: now)
            )
            #expect(await processor.processPending() == 2)
            #expect(await calendar.eventDate == nil)
            #expect(await calendar.createCount == 0)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM outbox_work WHERE state='completed' AND attempt_count=0"
            ) == 2)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM outbox_work WHERE state='pending'"
            ) == 0)
        }
    }

    @Test("Undo preserves the official Calendar deadline")
    func calendarUndoPreservesOfficialDate() async throws {
        try await withDatabase { database in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let official = now.addingTimeInterval(300_000)
            let suggested = now.addingTimeInterval(200_000)
            try TestData.seed(database, officialDueAt: official)
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(
                    suggestedDate: suggested, officialDateEcho: official
                )), clock: FixedClock(now: now)
            )
            try coordinator.setEnabled(true)
            let result = await coordinator.process(
                rawSourceRecordID: TestData.rawID,
                input: TestData.input(officialDueAt: official)
            )
            let id = try #require(result.parseResult?.id)
            try coordinator.confirm(id)
            let calendar = InspectingCalendarService(database: database)
            let processor = OutboxProcessor(
                database: database, calendar: calendar,
                notifications: FakeNotificationService(), clock: FixedClock(now: now)
            )
            #expect(await processor.processPending() == 1)
            #expect(await calendar.eventDate == official)
            try coordinator.undo(id)
            #expect(await processor.processPending() == 1)
            #expect(await calendar.eventDate == official)
            #expect(await calendar.removeCount == 0)
            #expect(await calendar.createCount == 1)
        }
    }

    @MainActor
    @Test("Awaited Dashboard AI decisions synchronously converge deadline notifications")
    func awaitedDashboardDecisionsReconcileNotifications() async throws {
        try await withMainActorDatabase { database in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let suggested = now.addingTimeInterval(300_000)
            try TestData.seed(database, officialDueAt: nil)
            try NotificationPersistence(database: database).save(
                NotificationPreferences(enabled: true), now: now
            )
            let center = AIUndoNotificationCenter()
            let notifications = CampusNotificationService(
                database: database, center: center, clock: FixedClock(now: now)
            )
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(
                    suggestedDate: suggested, officialDateEcho: nil
                )), clock: FixedClock(now: now)
            )
            try coordinator.setEnabled(true)
            let result = await coordinator.process(
                rawSourceRecordID: TestData.rawID,
                input: TestData.input(officialDueAt: nil)
            )
            let id = try #require(result.parseResult?.id)
            let model = DashboardModel(
                notificationService: notifications, aiCoordinator: coordinator
            )
            await model.confirmAIResult(id)
            #expect(!(await center.requests).isEmpty)
            #expect(try database.query(
                "SELECT suggestion_confirmed_at FROM learning_tasks WHERE id='task-1'"
            ).first?.double("suggestion_confirmed_at") == now.timeIntervalSince1970)

            await model.undoAIResult(id)
            #expect(await center.requests.isEmpty)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM notification_deliveries WHERE state='scheduled' AND notification_type='deadline_reminder'"
            ) == 0)

            let corrected = suggested.addingTimeInterval(100_000)
            await model.correctAIResult(
                id, title: "Corrected", type: "reading", date: corrected
            )
            #expect(!(await center.requests).isEmpty)
            #expect(try database.query(
                "SELECT suggested_complete_at FROM learning_tasks WHERE id='task-1'"
            ).first?.double("suggested_complete_at") == corrected.timeIntervalSince1970)
            await model.undoAIResult(id)
            #expect(await center.requests.isEmpty)
        }
    }

    @MainActor
    @Test("Notification reconciliation failure preserves the AI decision and explains partial success")
    func notificationFailurePreservesDecision() async throws {
        try await withMainActorDatabase { database in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            let suggested = now.addingTimeInterval(300_000)
            try TestData.seed(database, officialDueAt: nil)
            try NotificationPersistence(database: database).save(
                NotificationPreferences(enabled: true), now: now
            )
            let center = AIUndoNotificationCenter(failAdds: true)
            let notifications = CampusNotificationService(
                database: database, center: center, clock: FixedClock(now: now)
            )
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(
                    suggestedDate: suggested, officialDateEcho: nil
                )), clock: FixedClock(now: now)
            )
            try coordinator.setEnabled(true)
            let result = await coordinator.process(
                rawSourceRecordID: TestData.rawID,
                input: TestData.input(officialDueAt: nil)
            )
            let id = try #require(result.parseResult?.id)
            let model = DashboardModel(
                notificationService: notifications, aiCoordinator: coordinator
            )

            await model.confirmAIResult(id)

            #expect(try coordinator.history().first { $0.id == id }?.confirmationState == .confirmed)
            #expect(try database.query(
                "SELECT suggestion_confirmed_at FROM learning_tasks WHERE id='task-1'"
            ).first?.double("suggestion_confirmed_at") == now.timeIntervalSince1970)
            #expect(model.aiMessage.contains("decision was saved"))
            #expect(model.aiMessage.contains("could not be updated"))
        }
    }

    @Test("Production Canvas input uses bounded redacted same-course known objects")
    func productionKnownObjectContext() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            for index in 0..<10 {
                let title: String
                if index == 0 { title = "Token=abc123 related task" }
                else if index == 1 { title = "Read https://canvas.invalid/private/path before class" }
                else { title = String(repeating: "Context \(index) ", count: 30) }
                try TestData.insertTask(
                    database, id: "context-\(String(format: "%02d", index))",
                    sourceID: "source-context-\(index)", title: title
                )
            }
            try database.execute(
                """
                INSERT INTO announcements
                  (id,source_account_id,source_object_id,course_id,title,published_at,summary,
                   content_hash,source_state,first_seen_at,last_seen_at)
                VALUES('announcement-1',?,'source-announcement-1','course-1',
                  'Cookie=cookie123 announcement',900,'Brief','hash-a','active',1,1)
                """,
                bindings: [.text(TestData.accountID.uuidString)]
            )
            try database.execute(
                """
                INSERT INTO courses
                  (id,source_account_id,source_object_id,name,code,term,time_zone,source_state,
                   first_seen_at,last_seen_at)
                VALUES('course-2',?,'source-course-2','Other Course','OTH','','UTC','active',1,1)
                """,
                bindings: [.text(TestData.accountID.uuidString)]
            )
            try TestData.insertTask(
                database, id: "unrelated-task", sourceID: "source-unrelated",
                courseID: "course-2", title: "Must not be included"
            )

            let provider = try CapturingProvider(response: TestData.response())
            let coordinator = AIParsingCoordinator(database: database, provider: provider)
            try coordinator.setEnabled(true)
            _ = await coordinator.processPendingCanvasRecords()
            let input = try #require(provider.inputs.first)
            #expect(input.knownObjectSummaries.count == AIParsingCoordinator.maximumKnownObjects)
            #expect(!input.knownObjectSummaries.contains { $0.objectID == "task-1" })
            #expect(!input.knownObjectSummaries.contains { $0.objectID == "unrelated-task" })
            #expect(input.knownObjectSummaries.allSatisfy { $0.title.count <= 160 })
            let encoded = try JSONEncoder().encode(input.knownObjectSummaries)
            let text = String(decoding: encoded, as: UTF8.self)
            #expect(!text.contains("abc123"))
            #expect(!text.contains("cookie123"))
            #expect(!text.contains("canvas.invalid"))
            #expect(text.contains("[REDACTED]"))
        }
    }

    @Test("Unknown related IDs are rejected without changing deterministic data")
    func unknownRelatedIDFailsSafe() async throws {
        try await withDatabase { database in
            try TestData.seed(database, secondTask: true)
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(
                    related: ["provider-invented-id"]
                ))
            )
            try coordinator.setEnabled(true)
            let outcome = await coordinator.process(
                rawSourceRecordID: TestData.rawID, input: TestData.input()
            )
            #expect(outcome.deterministicType == "assignment")
            #expect(outcome.failureCategory == "invalid_output")
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 2)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM ai_parse_results WHERE confirmation_state='failed'"
            ) == 1)
        }
    }

    @Test("Oversized title, type, and provider JSON are rejected safely")
    func outputLimits() async throws {
        let input = TestData.input()
        let longTitle = TestData.response(
            normalizedTitle: String(repeating: "t", count: AIStructuredOutputValidator.maximumNormalizedTitleLength + 1)
        )
        #expect(throws: AIParsingError.invalidOutput("output exceeds bounded field limits")) {
            try AIStructuredOutputValidator.decode(try TestData.encoded(longTitle), input: input)
        }
        let longType = TestData.response(
            type: String(repeating: "x", count: AIStructuredOutputValidator.maximumSuggestedTypeLength + 1)
        )
        #expect(throws: AIParsingError.invalidOutput("output exceeds bounded field limits")) {
            try AIStructuredOutputValidator.decode(try TestData.encoded(longType), input: input)
        }
        let oversized = Data(
            repeating: 0x20, count: AIStructuredOutputValidator.maximumOutputBytes + 1
        )
        #expect(throws: AIParsingError.invalidOutput("provider output exceeds maximum byte size")) {
            try AIStructuredOutputValidator.decode(oversized, input: input)
        }

        try await withDatabase { database in
            try TestData.seed(database)
            let coordinator = AIParsingCoordinator(
                database: database, provider: CapturingProvider(data: oversized)
            )
            try coordinator.setEnabled(true)
            let outcome = await coordinator.process(
                rawSourceRecordID: TestData.rawID, input: input
            )
            #expect(outcome.deterministicType == "assignment")
            #expect(outcome.failureCategory == "invalid_output")
            #expect(try database.query("SELECT title FROM learning_tasks").first?.string("title") == "Assignment 1")
        }
    }

    @Test("Minimal input is bounded and redacts credentials and URLs")
    func minimalInput() {
        let original = TestData.input(
            text: "Bearer abc123 password=private https://canvas.invalid/path " + String(repeating: "x", count: 2_000)
        )
        let value = AIParsingCoordinator.minimalInput(original)
        #expect(value.minimalText.count <= 1_200)
        #expect(!value.minimalText.contains("abc123"))
        #expect(!value.minimalText.contains("private"))
        #expect(!value.minimalText.contains("canvas.invalid"))
        #expect(value.minimalText.contains("[REDACTED]"))
    }

    @Test("Related-item suggestions never merge or delete source records")
    func duplicatesAreSuggestionsOnly() async throws {
        try await withDatabase { database in
            try TestData.seed(database, secondTask: true)
            let response = TestData.response(related: ["task-2"])
            let coordinator = AIParsingCoordinator(database: database, provider: try CapturingProvider(response: response))
            try coordinator.setEnabled(true)
            let outcome = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            let result = try #require(outcome.parseResult)
            #expect(result.relatedObjectIDs == ["task-2"])
            try coordinator.confirm(result.id)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 2)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM raw_source_records") == 1)
        }
    }

    @Test("Correction, rejection, and undo are durable and auditable")
    func auditedWorkflow() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            let coordinator = AIParsingCoordinator(
                database: database, provider: try CapturingProvider(response: TestData.response()),
                clock: FixedClock(now: Date(timeIntervalSince1970: 4_000))
            )
            try coordinator.setEnabled(true)
            let outcome = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            let id = try #require(outcome.parseResult?.id)
            try coordinator.correct(id, correction: AIConfirmationCorrection(
                normalizedTitle: "Corrected title", suggestedType: "reading",
                suggestedDate: Date(timeIntervalSince1970: 2_500)
            ))
            #expect(try coordinator.history().first?.confirmationState == .corrected)
            #expect(try database.query("SELECT * FROM learning_tasks").first?.string("normalized_type") == "reading")
            try coordinator.undo(id)
            #expect(try coordinator.pendingConfirmations().first?.confirmationState == .undone)
            let task = try #require(database.query("SELECT * FROM learning_tasks").first)
            #expect(task.string("normalized_type") == nil)
            #expect(task.double("suggested_complete_at") == nil)
            #expect(try coordinator.auditTrail(parseResultID: id).map(\.action) == [.correct, .undo])
            try coordinator.reject(id)
            #expect(try coordinator.auditTrail(parseResultID: id).map(\.action) == [.correct, .undo, .reject])
        }
    }

    @Test("Confirmation provenance and audit history survive database restart")
    func auditRestartPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-audit-restart-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("db.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        var resultID: UUID?
        do {
            let database = try SQLiteDatabase(path: path)
            try TestData.seed(database)
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(suggestedDate: Date(timeIntervalSince1970: 2_500)))
            )
            try coordinator.setEnabled(true)
            let result = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            resultID = result.parseResult?.id
            try coordinator.correct(try #require(resultID), correction: AIConfirmationCorrection(
                normalizedTitle: "Adopted synthetic title", suggestedType: "reading",
                suggestedDate: Date(timeIntervalSince1970: 2_600)
            ))
        }
        do {
            let coordinator = AIParsingCoordinator(database: try SQLiteDatabase(path: path))
            let record = try #require(coordinator.history().first { $0.id == resultID })
            #expect(record.confirmationState == .corrected)
            #expect(record.adoptedNormalizedTitle == "Adopted synthetic title")
            #expect(record.adoptedType == "reading")
            #expect(record.adoptedDate == Date(timeIntervalSince1970: 2_600))
            #expect(try coordinator.auditTrail(parseResultID: record.id).map(\.action) == [.correct])
        }
    }

    @Test("Deterministic and user values take precedence and undo restores exact prior state")
    func priorValuesWin() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            try database.execute(
                "UPDATE learning_tasks SET normalized_type='reading', suggested_complete_at=1500, suggestion_origin='user', suggestion_confirmed_at=1400 WHERE id='task-1'"
            )
            let coordinator = AIParsingCoordinator(
                database: database,
                provider: try CapturingProvider(response: TestData.response(type: "quiz", suggestedDate: Date(timeIntervalSince1970: 2_000)))
            )
            try coordinator.setEnabled(true)
            let result = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            let id = try #require(result.parseResult?.id)
            try coordinator.confirm(id)
            var task = try #require(database.query("SELECT * FROM learning_tasks").first)
            #expect(task.string("normalized_type") == "reading")
            #expect(task.double("suggested_complete_at") == 1_500)
            #expect(task.string("suggestion_origin") == "user")
            #expect(task.double("suggestion_confirmed_at") == 1_400)
            try coordinator.undo(id)
            task = try #require(database.query("SELECT * FROM learning_tasks").first)
            #expect(task.string("normalized_type") == "reading")
            #expect(task.double("suggested_complete_at") == 1_500)
            #expect(task.string("suggestion_origin") == "user")
            #expect(task.double("suggestion_confirmed_at") == 1_400)
        }
    }

    @Test("Unchanged parse inputs are idempotent")
    func parseIdempotency() async throws {
        try await withDatabase { database in
            try TestData.seed(database)
            let coordinator = AIParsingCoordinator(
                database: database, provider: try CapturingProvider(response: TestData.response())
            )
            try coordinator.setEnabled(true)
            let first = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            let second = await coordinator.process(rawSourceRecordID: TestData.rawID, input: TestData.input())
            #expect(first.parseResult?.id == second.parseResult?.id)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM ai_parse_results") == 1)
        }
    }

    @Test("External providers cannot be enabled without complete disclosure and consent")
    func externalConsentGate() throws {
        try withDatabaseSync { database in
            let store = AIPersistence(database: database)
            let unsafe = AIAssistanceSettings(
                enabled: true, providerKind: .external, providerDisclosure: "Provider",
                transmittedFields: nil, retentionPolicy: "Not retained",
                consentedAt: nil, updatedAt: Date()
            )
            #expect(throws: AIParsingError.consentRequired) { try store.saveSettings(unsafe) }
            let stored = try store.settings()
            #expect(stored.enabled == false)
        }
    }

    @Test("Synthetic evaluation reports all required safety metrics")
    func syntheticEvaluation() async throws {
        let dateText = "2026-09-10T10:00:00Z"
        let date = try #require(ISO8601DateFormatter().date(from: dateText))
        let fixtures: [(AIParseInput, String?, Set<String>, Date?, Bool)] = [
            (TestData.input(title: "Quiz 2"), "quiz", [], nil, false),
            (TestData.input(title: "Read chapter 4"), "reading", [], nil, false),
            (TestData.input(title: "Worksheet"), "assignment", [], nil, false),
            (TestData.input(title: "Studio", text: "[uncertain]"), "assignment", [], nil, true),
            (TestData.input(text: "Submit [date:\(dateText)]"), "assignment", [], date, false),
            (TestData.input(text: "See [related:task-2]"), "assignment", ["task-2"], nil, false),
            (TestData.input(title: "Mystery", text: "[uncertain]"), "assignment", [], nil, true),
            (TestData.input(title: "Quiz review", text: "[date:\(dateText)] [related:task-2] [action:Revise notes]"), "quiz", ["task-2"], date, false)
        ]
        let provider = DeterministicFakeAIProvider()
        var cases: [AISyntheticEvaluationCase] = []
        for fixture in fixtures {
            let data = try await provider.structuredSuggestion(for: fixture.0)
            let output = try AIStructuredOutputValidator.decode(data, input: fixture.0)
            if let expectedDate = fixture.3 {
                #expect(output.suggestedDate == expectedDate)
            }
            cases.append(AISyntheticEvaluationCase(
                expectedType: fixture.1, expectedRelatedObjectIDs: fixture.2,
                expectedDate: fixture.3, shouldBeUncertain: fixture.4, output: output
            ))
        }
        let report = AISyntheticEvaluator.evaluate(
            cases, unauthorizedCalendarWrites: 0, unauthorizedNotificationWrites: 0
        )
        #expect(report.sampleCount == 8)
        #expect(report.classificationAccuracy == 1)
        #expect(report.duplicateSuggestionPrecision == 1)
        #expect(report.dateExtractionAccuracy == 1)
        #expect(report.uncertaintyRecall == 1)
        #expect(report.unauthorizedCalendarWrites == 0)
        #expect(report.unauthorizedNotificationWrites == 0)
    }

    private func withDatabase(_ body: (SQLiteDatabase) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(SQLiteDatabase(path: directory.appendingPathComponent("db.sqlite3").path))
    }

    @MainActor
    private func withMainActorDatabase(
        _ body: (SQLiteDatabase) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-main-actor-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(SQLiteDatabase(path: directory.appendingPathComponent("db.sqlite3").path))
    }

    private func withDatabaseSync(_ body: (SQLiteDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(SQLiteDatabase(path: directory.appendingPathComponent("db.sqlite3").path))
    }
}

private final class CapturingProvider: AIParsingProvider, @unchecked Sendable {
    let providerName = "Synthetic provider"
    let modelName = "synthetic-v1"
    private let lock = NSLock()
    private let data: Data
    private var callCount = 0
    private var capturedInputs: [AIParseInput] = []
    var calls: Int { lock.withLock { callCount } }
    var inputs: [AIParseInput] { lock.withLock { capturedInputs } }

    init(data: Data) { self.data = data }
    convenience init(response: AIProviderResponse) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try self.init(data: encoder.encode(response))
    }
    func structuredSuggestion(for input: AIParseInput) async throws -> Data {
        lock.withLock {
            callCount += 1
            capturedInputs.append(input)
        }
        return data
    }
}

private actor InspectingCalendarService: CalendarService {
    private let database: SQLiteDatabase
    private(set) var eventDate: Date?
    private(set) var createCount = 0
    private(set) var removeCount = 0

    init(database: SQLiteDatabase) { self.database = database }

    func apply(_ commands: [CalendarCommand]) async throws -> [CalendarCommandResult] {
        for command in commands {
            switch command {
            case .upsert(let objectType, let objectID):
                guard objectType == "learning_task",
                      let row = try database.query(
                        "SELECT * FROM learning_tasks WHERE id=?", bindings: [.text(objectID)]
                      ).first else { continue }
                let selected = row.double("official_due_at") ?? (
                    row.double("suggestion_confirmed_at") == nil
                        ? nil : row.double("suggested_complete_at")
                )
                if eventDate == nil, selected != nil {
                    createCount += 1
                    try database.execute(
                        """
                        INSERT INTO calendar_bindings
                          (id,object_type,object_id,event_identifier,ownership_marker,
                           calendar_identifier,calendar_source_identifier,sync_state)
                        VALUES('ai-test-binding','learning_task',?,'ai-test-event','ai-test-marker',
                          'ai-test-calendar','ai-test-source','synced')
                        ON CONFLICT(object_type,object_id) DO UPDATE SET sync_state='synced'
                        """,
                        bindings: [.text(objectID)]
                    )
                }
                eventDate = selected.map(Date.init(timeIntervalSince1970:))
            case .removeBoundEvent:
                if eventDate != nil {
                    eventDate = nil
                    removeCount += 1
                    try database.execute(
                        "UPDATE calendar_bindings SET sync_state='removed' WHERE id='ai-test-binding'"
                    )
                }
            }
        }
        return commands.map { command in
            switch command {
            case .upsert(_, let objectID), .removeBoundEvent(_, let objectID):
                CalendarCommandResult(objectID: objectID, bindingIdentifier: nil)
            }
        }
    }
}

private actor AIUndoNotificationCenter: UserNotificationCenterClient {
    private let failAdds: Bool
    private(set) var requests: [LocalNotificationRequest] = []

    init(failAdds: Bool = false) { self.failAdds = failAdds }
    func authorizationState() async -> NotificationAuthorizationState { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func add(_ request: LocalNotificationRequest) async throws {
        if failAdds { throw AIUndoNotificationError.syntheticFailure }
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }
    func removePending(identifiers: [String]) async {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
}

private enum AIUndoNotificationError: Error {
    case syntheticFailure
}

private enum TestData {
    static let accountID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    static let rawID = UUID(uuidString: "82000000-0000-0000-0000-000000000001")!

    static func input(
        source: SourceKind = .canvas, title: String = "Assignment 1",
        text: String = "Complete the synthetic worksheet",
        officialDueAt: Date? = Date(timeIntervalSince1970: 1_000),
        knownObjects: [AIKnownObjectSummary]? = nil
    ) -> AIParseInput {
        AIParseInput(
            source: source,
            objectType: "learning_task", objectID: "task-1", title: title,
            officialType: "assignment", courseName: "Synthetic Course",
            officialDueAt: officialDueAt, minimalText: text,
            language: "en", knownObjectSummaries: knownObjects ?? [AIKnownObjectSummary(
                objectID: "task-2", objectType: "learning_task",
                title: "Related synthetic item", type: "assignment",
                date: Date(timeIntervalSince1970: 1_500)
            )],
            sourceURL: "https://canvas.invalid/synthetic-task"
        )
    }

    static func response(
        type: String? = "assignment", suggestedDate: Date? = nil,
        related: [String] = [], confidence: Double = 0.9,
        hasConflict: Bool = false, uncertain: Bool = false,
        officialDateEcho: Date? = Date(timeIntervalSince1970: 1_000),
        normalizedTitle: String? = "Assignment 1"
    ) -> AIProviderResponse {
        AIProviderResponse(
            normalizedTitle: normalizedTitle, suggestedType: type,
            officialDateEcho: officialDateEcho, suggestedDate: suggestedDate,
            relatedObjectIDs: related, actionItems: ["Review synthetic notes"],
            confidence: confidence, rationale: "Synthetic evaluation rationale",
            hasConflict: hasConflict, changeSummary: "One synthetic suggestion.", uncertain: uncertain
        )
    }

    static func encoded(_ response: AIProviderResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(response)
    }

    static func seed(
        _ database: SQLiteDatabase, secondTask: Bool = false,
        officialDueAt: Date? = Date(timeIntervalSince1970: 1_000)
    ) throws {
        try database.execute(
            "INSERT INTO source_accounts(id,source_kind,instance_url,display_name,authorization_state,capabilities_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)",
            bindings: [.text(accountID.uuidString), .text("Canvas"), .text("https://canvas.invalid"), .text("Synthetic"), .text("connected"), .text("{}"), .real(1), .real(1)]
        )
        try database.execute(
            """
            INSERT INTO courses
              (id,source_account_id,source_object_id,name,code,term,time_zone,source_state,
               first_seen_at,last_seen_at)
            VALUES('course-1',?,'source-course-1','Synthetic Course','SYN','','UTC','active',1,1)
            """,
            bindings: [.text(accountID.uuidString)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let rawPayload = try encoder.encode(RawSyncRecord(
            objectType: .learningTask, sourceObjectID: "source-task-1",
            fields: [
                "title": "Assignment 1", "officialType": "assignment",
                "courseSourceObjectID": nil
            ]
        ))
        try database.execute(
            "INSERT INTO raw_source_records(id,source_account_id,object_type,source_object_id,fetch_batch_id,content_hash,payload,fetched_at) VALUES(?,?,?,?,?,?,?,?)",
            bindings: [.text(rawID.uuidString), .text(accountID.uuidString), .text("learning_task"), .text("source-task-1"), .text("batch"), .text("hash"), .blob(rawPayload), .real(1)]
        )
        try insertTask(
            database, id: "task-1", sourceID: "source-task-1", officialDueAt: officialDueAt
        )
        if secondTask {
            try insertTask(
                database, id: "task-2", sourceID: "source-task-2", officialDueAt: officialDueAt
            )
        }
    }

    static func insertTask(
        _ database: SQLiteDatabase, id: String, sourceID: String,
        officialDueAt: Date? = Date(timeIntervalSince1970: 1_000),
        courseID: String? = "course-1", title: String = "Assignment 1"
    ) throws {
        try database.execute(
            """
            INSERT INTO learning_tasks(id,source_account_id,source_object_id,course_id,title,official_type,
              official_due_at,official_due_time_zone,source_state,first_seen_at,last_seen_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?)
            """,
            bindings: [
                .text(id), .text(accountID.uuidString), .text(sourceID),
                courseID.map(SQLiteValue.text) ?? .null, .text(title), .text("assignment"),
                officialDueAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                .text("UTC"), .text("active"), .real(1), .real(1)
            ]
        )
    }
}
