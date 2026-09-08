import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 15T triage and placeholder semantics")
struct Stage15TTests {
    @Test("Task list partitions always-shown placeholders without duplicates and respects filters")
    @MainActor
    func taskListPartition() {
        let active = learningTask(id: 1, kind: .assignment)
        let grouped = learningTask(id: 2, kind: .assignment, placeholder: true)
        let alwaysShown = learningTask(id: 3, kind: .quiz, placeholder: true, alwaysShow: true)
        let tasks = [active, grouped, alwaysShown]

        let normal = TasksView.normalTasks(in: tasks, filter: nil)
        let placeholders = TasksView.groupedPlaceholders(in: tasks, filter: nil)
        #expect(Set(normal.map(\.id)).isDisjoint(with: Set(placeholders.map(\.id))))
        #expect(normal.map(\.id) == [active.id, alwaysShown.id])
        #expect(placeholders.map(\.id) == [grouped.id])

        #expect(TasksView.normalTasks(in: tasks, filter: .assignment).map(\.id) == [active.id])
        #expect(TasksView.groupedPlaceholders(in: tasks, filter: .assignment).map(\.id) == [grouped.id])
        #expect(TasksView.normalTasks(in: tasks, filter: .quiz).map(\.id) == [alwaysShown.id])
        #expect(TasksView.groupedPlaceholders(in: tasks, filter: .quiz).isEmpty)
    }

    @Test("Placeholder classifier is conservative across the evidence matrix")
    func classificationMatrix() {
        let cases: [(String, TaskPlaceholderEvidence, Date?, Bool)] = [
            ("truly empty shell", evidence(), nil, true),
            ("incomplete source evidence", .incomplete, nil, false),
            ("official due date", evidence(), Date(), false),
            ("meaningful instructions", evidence(description: true), nil, false),
            ("attachment", evidence(attachment: true), nil, false),
            ("quiz or external activity", evidence(activity: true), nil, false),
            ("meaningful submission route", evidence(submission: true), nil, false),
            ("offline work without submission", evidence(action: true), nil, false),
            ("reading or preparation without submission", evidence(action: true), nil, false)
        ]
        for (_, value, dueAt, expected) in cases {
            #expect(value.classifiesAsPlaceholder(dueAt: dueAt) == expected)
        }
    }

    @Test("Canvas decoding uses complete standard evidence and optional attachment signals")
    func decodingCompleteness() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let incomplete = try decoder.decode(CanvasAssignmentDTO.self, from: Data(
            #"{"id":1,"name":"Shell","due_at":null,"submission_types":["none"]}"#.utf8
        ))
        #expect(!incomplete.payload(fallbackCourseID: "c").placeholderEvidence.isComplete)

        let missingNecessaryStandardField = try decoder.decode(CanvasAssignmentDTO.self, from: Data(
            #"{"id":1,"name":"Shell","due_at":null,"description":null,"attachments":[],"submission_types":["none"],"quiz_id":null,"external_tool_tag_attributes":null}"#.utf8
        ))
        #expect(!missingNecessaryStandardField.payload(fallbackCourseID: "c").placeholderEvidence.isComplete)

        let complete = try decoder.decode(CanvasAssignmentDTO.self, from: Data(
            #"{"id":1,"name":"Shell","due_at":null,"description":null,"submission_types":["none"],"quiz_id":null,"external_tool_tag_attributes":null,"annotatable_attachment_id":null}"#.utf8
        ))
        #expect(complete.payload(fallbackCourseID: "c").placeholderEvidence.classifiesAsPlaceholder(dueAt: nil))

        let annotatable = try decoder.decode(CanvasAssignmentDTO.self, from: Data(
            #"{"id":2,"name":"Annotated work","due_at":null,"description":null,"submission_types":["none"],"quiz_id":null,"external_tool_tag_attributes":null,"annotatable_attachment_id":42}"#.utf8
        ))
        let annotatableEvidence = annotatable.payload(fallbackCourseID: "c").placeholderEvidence
        #expect(annotatableEvidence.isComplete)
        #expect(annotatableEvidence.hasAttachment)
        #expect(!annotatableEvidence.classifiesAsPlaceholder(dueAt: nil))

        let linkedDescription = try decoder.decode(CanvasAssignmentDTO.self, from: Data(
            #"{"id":3,"name":"Linked work","due_at":null,"description":"<p><a href=\"https://canvas.invalid/resource\"></a></p>","submission_types":["none"],"quiz_id":null,"external_tool_tag_attributes":null,"annotatable_attachment_id":null}"#.utf8
        ))
        let linkedEvidence = linkedDescription.payload(fallbackCourseID: "c").placeholderEvidence
        #expect(linkedEvidence.hasMeaningfulDescription)
        #expect(!linkedEvidence.classifiesAsPlaceholder(dueAt: nil))
    }

    @Test("Sync preserves identity, transitions once, persists override, and reports aggregate counts")
    func transitionPersistenceAndMetrics() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-stage15t-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = try SQLiteDatabase(path: path)
        let reader = Stage15TReader(snapshot: snapshot(task: task(evidence: evidence())))
        let account = SyncSourceAccount(
            id: UUID(), source: .canvas, instanceURL: "https://canvas.invalid", displayName: "Canvas"
        )
        let engine = DeterministicSyncEngine(database: database, accounts: [account], readers: [reader],
                                             clock: FixedClock(now: Date(timeIntervalSince1970: 1_000)))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        let first = try #require(database.query("SELECT * FROM learning_tasks").first)
        let stableID = first.string("id")
        #expect(first.string("placeholder_state") == "placeholder")
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == 0)
        let provider = Stage15TCountingProvider()
        let ai = AIParsingCoordinator(database: database, provider: provider)
        try ai.setEnabled(true)
        #expect(await ai.processPendingCanvasRecords().isEmpty)
        #expect(provider.requestCount == 0)

        try SQLiteDashboardDataReader(database: database).setPlaceholderAlwaysShow(
            taskID: UUID(uuidString: stableID!)!, alwaysShow: true
        )
        await reader.set(snapshot(task: task(due: Date(timeIntervalSince1970: 9_000), evidence: evidence())))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        let active = try #require(database.query("SELECT * FROM learning_tasks").first)
        #expect(active.string("id") == stableID)
        #expect(active.string("placeholder_state") == "active")
        #expect(active.int("placeholder_always_show") == 1)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind='calendar.upsert'") == 1)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind='notification.schedule'") == 1)

        await reader.set(snapshot(task: task(evidence: evidence())))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        _ = try await engine.synchronize(source: .canvas, trigger: .scheduled)
        let metrics = try #require(database.query("SELECT * FROM placeholder_metrics").first)
        #expect(metrics.int("suppressed_total") == 2)
        #expect(metrics.int("reactivated_total") == 1)
        #expect(metrics.int("current_suppressed") == 1)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind='calendar.remove'") == 1)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind='notification.schedule'") == 1)

        await reader.set(snapshot(task: nil))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        let cancelledMetrics = try #require(database.query("SELECT * FROM placeholder_metrics").first)
        #expect(cancelledMetrics.int("suppressed_total") == 2)
        #expect(cancelledMetrics.int("reactivated_total") == 1)
        #expect(cancelledMetrics.int("current_suppressed") == 0)
        #expect(try database.query("SELECT source_state FROM learning_tasks").first?.string("source_state") == "cancelled")

        await reader.set(snapshot(task: task(evidence: evidence())))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        let reappearedMetrics = try #require(database.query("SELECT * FROM placeholder_metrics").first)
        #expect(reappearedMetrics.int("suppressed_total") == 2)
        #expect(reappearedMetrics.int("reactivated_total") == 1)
        #expect(reappearedMetrics.int("current_suppressed") == 1)
        let reappeared = try #require(database.query("SELECT * FROM learning_tasks").first)
        #expect(reappeared.string("source_state") == "active")
        #expect(reappeared.string("placeholder_state") == "placeholder")

        try database.execute("UPDATE learning_tasks SET placeholder_state='active'")
        let reloaded = try SQLiteDashboardDataReader(database: try SQLiteDatabase(path: path)).loadSnapshot()
        #expect(reloaded.tasks.first?.id.uuidString == stableID)
        #expect(reloaded.tasks.first?.isPlaceholder == true)
        #expect(reloaded.tasks.first?.placeholderAlwaysShow == true)
        #expect(reloaded.tasks.first?.appearsInNormalTaskList == true)
    }

    @Test("A placeholder's first actionable transition follows the new-task path exactly once")
    func placeholderActivationNotificationIsOnceOnly() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-stage15t-notification-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = try SQLiteDatabase(path: path)
        let reader = Stage15TReader(snapshot: snapshot(task: task(evidence: evidence())))
        let account = SyncSourceAccount(
            id: UUID(), source: .canvas, instanceURL: "https://canvas.invalid", displayName: "Canvas"
        )
        let engine = DeterministicSyncEngine(database: database, accounts: [account], readers: [reader],
                                             clock: FixedClock(now: Date(timeIntervalSince1970: 1_000)))

        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        #expect(try notificationScheduleCount(database) == 0)

        let actionable = task(due: Date(timeIntervalSince1970: 9_000), evidence: evidence())
        await reader.set(snapshot(task: actionable))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        _ = try await engine.synchronize(source: .canvas, trigger: .scheduled)
        #expect(try notificationScheduleCount(database) == 1)

        await reader.set(snapshot(task: task(evidence: evidence())))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        await reader.set(snapshot(task: actionable))
        _ = try await engine.synchronize(source: .canvas, trigger: .manual)
        #expect(try notificationScheduleCount(database) == 1)
    }

    @Test("Needs Review includes unresolved failures and other corrections, then removes resolved decisions")
    @MainActor
    func needsReviewPolicyAndAnnouncementRetention() async throws {
        let failed = analysis(category: .other, failure: "provider_unavailable")
        #expect(NeedsReviewPolicy.includes(failed))
        #expect(NeedsReviewPolicy.includes(analysis(category: .other, failure: nil)))
        #expect(!NeedsReviewPolicy.includes(analysis(category: .examTime, failure: nil)))
        #expect(NeedsReviewPolicy.includes(signal(state: .pending, category: .examTime)))
        #expect(NeedsReviewPolicy.includes(signal(state: .notRequired, category: .other)))
        #expect(!NeedsReviewPolicy.includes(signal(state: .confirmed, category: .other)))
        #expect(!NeedsReviewPolicy.includes(signal(state: .corrected, category: .other)))
        #expect(!NeedsReviewPolicy.includes(signal(state: .rejected, category: .courseScheduleChange)))

        let model = try Stage12QAData.databaseModel()
        await model.refresh()
        #expect(model.needsReviewCount == 1)
        #expect(model.snapshot.announcements.count == 1)
        model.rejectAcademicSignal(UUID(uuidString: "72000000-0000-0000-0000-000000000007")!)
        #expect(model.needsReviewCount == 0)
        #expect(model.snapshot.announcements.count == 1)
    }

    private func evidence(
        description: Bool = false, attachment: Bool = false, activity: Bool = false,
        submission: Bool = false, action: Bool = false
    ) -> TaskPlaceholderEvidence {
        .init(isComplete: true, hasMeaningfulDescription: description, hasAttachment: attachment,
              hasLinkedActivity: activity, hasMeaningfulSubmission: submission,
              hasActionableRequirement: action)
    }

    private func task(due: Date? = nil, evidence: TaskPlaceholderEvidence) -> NormalizedTask {
        .init(sourceObjectID: "task-1", courseSourceObjectID: "course-1", title: "Shell",
              officialType: "assignment", normalizedType: "assignment", officialDueAt: due,
              opensAt: nil, locksAt: nil, sourceURL: "https://canvas.invalid/tasks/1",
              placeholderEvidence: evidence)
    }

    private func snapshot(task: NormalizedTask?) -> SyncSnapshot {
        .init(courses: [.init(sourceObjectID: "course-1", name: "Course", code: "C",
                                term: "T", timeZone: "UTC", sourceURL: nil)], meetings: [],
              tasks: task.map { [$0] } ?? [], announcements: [],
              completeObjectTypes: [.course, .learningTask, .announcement])
    }

    private func learningTask(
        id: Int, kind: TaskKind, placeholder: Bool = false, alwaysShow: Bool = false
    ) -> LearningTask {
        LearningTask(
            id: UUID(uuidString: String(format: "15000000-0000-0000-0000-%012d", id))!,
            sourceAccountID: "account", sourceObjectID: "task-\(id)",
            courseID: UUID(uuidString: "15000000-0000-0000-0000-000000000099")!,
            title: "Task \(id)", kind: kind, officialDueAt: nil, suggestedCompleteAt: nil,
            suggestedDateConfirmed: false, source: .canvas, isLocallyComplete: false,
            localPriority: .medium, isPlaceholder: placeholder, placeholderAlwaysShow: alwaysShow
        )
    }

    private func notificationScheduleCount(_ database: SQLiteDatabase) throws -> Int {
        try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind='notification.schedule'")
    }

    private func analysis(category: AcademicSignalCategory, failure: String?) -> AcademicAnnouncementAnalysis {
        .init(id: UUID(), rawSourceRecordID: UUID(), announcementID: UUID(), sourceAccountID: "a",
              sourceObjectID: "n", contentHash: "h", primaryCategory: category,
              status: failure == nil ? .analyzed : .failed, provider: "production", model: "m",
              promptVersion: "p", schemaVersion: "s", failureCategory: failure,
              createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func signal(state: AcademicSignalConfirmationState,
                        category: AcademicSignalCategory) -> AcademicSignalRecord {
        .init(id: UUID(), analysisID: UUID(), announcementID: UUID(), sourceAccountID: "a",
              sourceObjectID: "n", category: category, evidence: "e", keyRequirement: "k",
              inferredDate: nil, isAllDay: false, timeZoneIdentifier: nil, confidence: 0.5,
              reason: "r", conflicts: [], provider: "production", model: "m", promptVersion: "p",
              schemaVersion: "s", confirmationState: state, adoptedCategory: nil, adoptedDate: nil,
              adoptedIsAllDay: nil, createdAt: .distantPast, updatedAt: .distantPast)
    }
}

private actor Stage15TReader: SyncSourceReader {
    let source: SourceKind = .canvas
    private var snapshot: SyncSnapshot
    init(snapshot: SyncSnapshot) { self.snapshot = snapshot }
    func read() async throws -> SyncSnapshot { snapshot }
    func set(_ value: SyncSnapshot) { snapshot = value }
}

private final class Stage15TCountingProvider: AIParsingProvider, @unchecked Sendable {
    let providerName = "stage15t-counting"
    let modelName = "no-network"
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.withLock { count } }
    func structuredSuggestion(for input: AIParseInput) async throws -> Data {
        lock.withLock { count += 1 }
        return Data("{}".utf8)
    }
}
