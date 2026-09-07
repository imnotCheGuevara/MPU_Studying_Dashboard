import Foundation

enum Stage12QAData {
    static let now = date(2026, 9, 7, 10, 15)

    @MainActor
    static func databaseModel() throws -> DashboardModel {
        let database = try SQLiteDatabase(path: ":memory:")
        let accountID = "72000000-0000-0000-0000-000000000001"
        let courseID = "72000000-0000-0000-0000-000000000002"
        let announcementID = UUID(uuidString: "72000000-0000-0000-0000-000000000003")!
        let rawID = UUID(uuidString: "72000000-0000-0000-0000-000000000004")!
        let analysisID = UUID(uuidString: "72000000-0000-0000-0000-000000000005")!
        try database.execute(
            "INSERT INTO source_accounts(id,source_kind,instance_url,display_name,authorization_state,capabilities_json,created_at,updated_at) VALUES(?,?,?,?,?,?,1,1)",
            bindings: [.text(accountID), .text("Canvas"), .text("https://example.invalid"),
                       .text("Canvas synthetic QA"), .text("authorized"), .text("{}")] )
        try database.execute(
            "INSERT INTO courses(id,source_account_id,source_object_id,name,code,term,time_zone,source_url,source_state,first_seen_at,last_seen_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            bindings: [.text(courseID), .text(accountID), .text("qa-course"),
                       .text("多语言 Synthetic Course 原文"), .text("QA-212"), .text("QA Term"),
                       .text("Asia/Macau"), .text("https://example.invalid/course"),
                       .text("active"), .real(1), .real(1)] )
        try database.execute(
            "INSERT INTO announcements(id,source_account_id,source_object_id,course_id,title,published_at,summary,content_hash,source_url,source_state,first_seen_at,last_seen_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
            bindings: [.text(announcementID.uuidString), .text(accountID), .text("qa-announcement"),
                       .text(courseID), .text("Quiz 改期 — source text unchanged"),
                       .real(date(2026, 9, 7, 8, 0).timeIntervalSince1970),
                       .text("The quiz moves to Tuesday 09:00; assignment due Wednesday."),
                       .text("qa-content-hash"), .text("https://example.invalid/announcement"),
                       .text("active"), .real(1), .real(1)] )
        try database.execute(
            "INSERT INTO raw_source_records(id,source_account_id,object_type,source_object_id,fetch_batch_id,content_hash,payload,fetched_at) VALUES(?,?,'announcement','qa-announcement','qa-batch','qa-raw-hash',?,1)",
            bindings: [.text(rawID.uuidString), .text(accountID), .blob(Data("{}".utf8))] )
        try database.execute(
            "INSERT INTO learning_tasks(id,source_account_id,source_object_id,course_id,title,official_type,official_due_at,official_due_time_zone,official_due_is_all_day,source_state,first_seen_at,last_seen_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
            bindings: [.text("72000000-0000-0000-0000-000000000006"), .text(accountID),
                       .text("qa-assignment"), .text(courseID), .text("Official red assignment DDL"),
                       .text("assignment"), .real(date(2026, 9, 8, 17, 0).timeIntervalSince1970),
                       .text("Asia/Macau"), .integer(0), .text("active"), .real(1), .real(1)] )

        let persistence = AcademicSignalPersistence(database: database)
        let analysis = AcademicAnnouncementAnalysis(
            id: analysisID, rawSourceRecordID: rawID, announcementID: announcementID,
            sourceAccountID: accountID, sourceObjectID: "qa-announcement",
            contentHash: "qa-content-hash", primaryCategory: .examTime, status: .analyzed,
            provider: "Synthetic no-network QA", model: "fixed-output-v1",
            promptVersion: AcademicSignalCoordinator.promptVersion,
            schemaVersion: AcademicSignalCoordinator.schemaVersion,
            failureCategory: nil, createdAt: now, updatedAt: now
        )
        _ = try persistence.saveAnalysis(analysis)
        let pending = AcademicSignalRecord(
            id: UUID(uuidString: "72000000-0000-0000-0000-000000000007")!,
            analysisID: analysisID, announcementID: announcementID,
            sourceAccountID: accountID, sourceObjectID: "qa-announcement",
            category: .examTime, evidence: "quiz moves to Tuesday 09:00",
            keyRequirement: "Attend the rescheduled Quiz",
            inferredDate: date(2026, 9, 8, 9, 0), isAllDay: false,
            timeZoneIdentifier: "Asia/Macau", confidence: 0.88,
            reason: "Synthetic explicit date and time for accessibility QA.",
            conflicts: ["Synthetic earlier date was superseded"],
            provider: "Synthetic no-network QA", model: "fixed-output-v1",
            promptVersion: AcademicSignalCoordinator.promptVersion,
            schemaVersion: AcademicSignalCoordinator.schemaVersion,
            confirmationState: .pending, adoptedCategory: nil, adoptedDate: nil,
            adoptedIsAllDay: nil, createdAt: now, updatedAt: now
        )
        let confirmed = AcademicSignalRecord(
            id: UUID(uuidString: "72000000-0000-0000-0000-000000000008")!,
            analysisID: analysisID, announcementID: announcementID,
            sourceAccountID: accountID, sourceObjectID: "qa-announcement",
            category: .assignmentDeadline, evidence: "assignment due Wednesday",
            keyRequirement: "Submit the synthetic assignment",
            inferredDate: date(2026, 9, 9, 17, 0), isAllDay: false,
            timeZoneIdentifier: "Asia/Macau", confidence: 0.91,
            reason: "Synthetic confirmed item for Schedule QA.", conflicts: [],
            provider: "Synthetic no-network QA", model: "fixed-output-v1",
            promptVersion: AcademicSignalCoordinator.promptVersion,
            schemaVersion: AcademicSignalCoordinator.schemaVersion,
            confirmationState: .confirmed, adoptedCategory: .assignmentDeadline,
            adoptedDate: date(2026, 9, 9, 17, 0), adoptedIsAllDay: false,
            createdAt: now, updatedAt: now
        )
        try persistence.replaceActiveSignals(analysisID: analysisID, values: [pending, confirmed])

        let repository = SQLitePersistenceRepository(database: database)
        let ai = AIParsingCoordinator(database: database)
        let academic = AcademicSignalCoordinator(database: database)
        let model = DashboardModel(
            localStateRepository: SQLiteLocalStateRepository(persistence: repository),
            dataReader: SQLiteDashboardDataReader(database: database),
            aiCoordinator: ai, academicSignalCoordinator: academic,
            now: { now }, timeZone: TimeZone(identifier: "Asia/Macau")!
        )
        model.refreshAIConfiguration()
        return model
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        CalendarDateMath.calendar(timeZone: TimeZone(identifier: "Asia/Macau")!)
            .date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
