import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 15R course reconciliation")
struct CourseReconciliationTests {
    @Test("Canvas embedded module codes and SIweb sections normalize deterministically")
    func normalization() {
        let canvasName = "2026-1: Software Engineering COMP3001-01"
        #expect(CourseIdentityNormalizer.embeddedCode(name: canvasName, rawCode: "Software Engineering") == "COMP300101")
        #expect(CourseIdentityNormalizer.baseCode("COMP300101") == "COMP3001")
        #expect(CourseIdentityNormalizer.normalizedTitle(canvasName) == "softwareengineering")
        #expect(CourseIdentityNormalizer.normalizedTitle("Software Engineering") == "softwareengineering")
        #expect(CourseIdentityNormalizer.embeddedCode(name: "Networks COMP2001-01", rawCode: "Networks") == "COMP200101")
        #expect(CourseIdentityNormalizer.normalizedTitle("(26/27-S1) Natural Language Processing COMP4120-411") == "naturallanguageprocessing")
    }

    @Test("Real 26/27-S1 names yield five safe mappings and one reviewed code conflict")
    func realTermPrefixCorpus() throws {
        try withDatabase { database in
            let rows = [
                ("Software Engineering", "COMP3001-411", "COMP3001-311"),
                ("Computer Networks", "COMP3002-411", "COMP3002-311"),
                ("Database Systems", "COMP3003-411", "COMP3003-311"),
                ("Artificial Intelligence", "COMP3004-411", "COMP3004-311"),
                ("Operating Systems", "COMP3005-411", "COMP3005-311"),
                ("Natural Language Processing", "COMP4120-411", "CSAI3122-311")
            ]
            for (title, canvasCode, siwebCode) in rows {
                _ = try seedPair(
                    database,
                    canvasName: "(26/27-S1) \(title) \(canvasCode)", canvasCode: title,
                    siwebName: title, siwebCode: siwebCode
                )
            }

            let service = CourseReconciliationService(database: database)
            let decisions = try service.reconcile()
            #expect(decisions.count == 6)
            #expect(decisions.filter { $0.state == .confirmed }.count == 5)
            let conflict = try #require(decisions.first { $0.canvasCode == "COMP4120411" })
            #expect(conflict.siwebCode == "CSAI3122311")
            #expect(conflict.state == .proposed)
            #expect(conflict.origin == "proposed_unique_title_code_conflict")
            #expect(try service.canonicalCourseIDs().count == 10)
            #expect(try database.scalarInt("SELECT COUNT(*) FROM academic_course_mappings") == 6)
        }
    }

    @Test("Unique compatible code and title auto-map, while ambiguity never guesses")
    func deterministicMappingAndAmbiguity() throws {
        try withDatabase { database in
            let pair = try seedPair(database, canvasName: "2026-1 Software Engineering COMP3001-01",
                                    canvasCode: "Software Engineering", siwebName: "Software Engineering",
                                    siwebCode: "COMP3001/02")
            let service = CourseReconciliationService(database: database)
            let decision = try #require(service.reconcile().first)
            #expect(decision.state == .confirmed)
            #expect(decision.origin == "auto_code_family_unique_title")
            #expect(try service.canonicalCourseIDs()[pair.siweb] == pair.canvas)
        }
        try withDatabase { database in
            _ = try seedPair(database, canvasName: "Networks COMP2001-01", canvasCode: "Networks",
                             siwebName: "Networks", siwebCode: "COMP2001-01")
            try seedCourse(database, account: "canvas", id: UUID(), objectID: "canvas-duplicate",
                           name: "Networks COMP2001-02", code: "Networks")
            let service = CourseReconciliationService(database: database)
            #expect(try service.reconcile().isEmpty)
            #expect(try service.canonicalCourseIDs().isEmpty)
        }
    }

    @Test("Code-family conflicts require a persisted local decision with undo and reset")
    func conflictDecisionAudit() throws {
        try withDatabase { database in
            _ = try seedPair(database, canvasName: "Databases COMP3002-01", canvasCode: "Databases",
                             siwebName: "Databases", siwebCode: "MATH3002-01")
            let service = CourseReconciliationService(database: database)
            var decision = try #require(service.reconcile().first)
            #expect(decision.state == .proposed)
            #expect(try service.canonicalCourseIDs().isEmpty)

            try service.map(decision.id)
            decision = try #require(service.decisions().first)
            #expect(decision.state == .confirmed)
            #expect(decision.canUndo)
            #expect(try database.scalarInt("SELECT COUNT(*) FROM academic_course_mapping_audit") == 1)

            try service.undo(decision.id)
            #expect(try service.decisions().first?.state == .proposed)
            try service.keepSeparate(decision.id)
            #expect(try service.decisions().first?.state == .separate)
            #expect(try service.canonicalCourseIDs().isEmpty)
            try service.reset(decision.id)
            #expect(try service.decisions().first?.state == .proposed)
        }
    }

    @Test("Canonical dashboard and notification lists hide mapped duplicates and synthetic sources")
    func canonicalPresentationAndSyntheticIsolation() throws {
        try withDatabase { database in
            let pair = try seedPair(database, canvasName: "2026-1 Software Engineering COMP3001-01",
                                    canvasCode: "Software Engineering", siwebName: "Software Engineering",
                                    siwebCode: "COMP3001-01")
            try seedAccount(database, id: "qa", kind: "Stage10Test")
            try seedCourse(database, account: "qa", id: UUID(), objectID: "qa-course",
                           name: "Synthetic QA Course", code: "QA1000")
            let snapshot = try SQLiteDashboardDataReader(database: database).loadSnapshot()
            #expect(snapshot.courses.count == 1)
            #expect(snapshot.courses.first?.id == pair.canvas)
            #expect(snapshot.courses.first?.code == "COMP300101")
            #expect(try database.scalarInt("SELECT COUNT(*) FROM courses") == 3)

            let notifications = CampusNotificationService(database: database, center: ReconciliationNoopCenter())
            let settings = try notifications.courseSettings()
            #expect(settings.count == 1)
            #expect(settings.first?.id == pair.canvas.uuidString)
            try NotificationPersistence(database: database).setCourseEnabled(
                false, courseID: pair.canvas.uuidString, now: Date(timeIntervalSince1970: 10)
            )
            #expect(try database.scalarInt("SELECT COUNT(*) FROM course_notification_preferences WHERE enabled=0") == 2)

            try database.execute(
                "INSERT INTO sync_runs(id,trigger_kind,source_account_id,fetch_state,normalize_state,persistence_state,started_at,finished_at) VALUES('qa-run','manual','qa','complete','complete','committed',1,2)"
            )
            let metrics = try ReleaseReadinessService(database: database).outcomeMetrics()
            #expect(metrics.completedSyncs == 0)
        }
    }

    @Test("Mapping re-resolves schedule changes locally without Calendar or outbox writes")
    func scheduleReresolutionIsLocalAndIdempotent() throws {
        try withDatabase { database in
            let pair = try seedPair(database, canvasName: "Databases COMP3002-01", canvasCode: "Databases",
                                    siwebName: "Databases", siwebCode: "MATH3002-01")
            let meeting = UUID()
            try database.execute(
                "INSERT INTO course_meetings(id,course_id,source_object_id,starts_at,ends_at,original_time_zone,location,source_state) VALUES(?,?,?,1000,4600,'Asia/Macau','Room 1','active')",
                bindings: [.text(meeting.uuidString), .text(pair.siweb.uuidString), .text("meeting")]
            )
            try seedScheduleSignal(database, canvasCourse: pair.canvas)
            let service = CourseReconciliationService(database: database, now: { Date(timeIntervalSince1970: 20) })
            let proposal = try #require(service.reconcile().first)
            #expect(try database.query("SELECT target_meeting_id FROM academic_signals").first?.string("target_meeting_id") == nil)
            try service.map(proposal.id)
            #expect(try database.query("SELECT target_meeting_id FROM academic_signals").first?.string("target_meeting_id") == meeting.uuidString)
            #expect(try database.scalarInt("SELECT COUNT(*) FROM outbox_work") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) FROM calendar_bindings") == 0)
            _ = try service.reconcile()
            #expect(try database.scalarInt("SELECT COUNT(*) FROM academic_course_mappings") == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) FROM outbox_work") == 0)
        }
    }

    @Test("Standalone confirmed schedule changes never render as deadlines")
    func schedulePresentationSemantic() throws {
        let course = UUID(), announcement = UUID(), date = Date(timeIntervalSince1970: 2_000)
        let snapshot = DashboardSnapshot(
            sourceHealth: [], courses: [], meetings: [], tasks: [],
            announcements: [.init(id: announcement, sourceObjectID: "announcement", courseID: course,
                                  title: "Make-up class", summary: "Moved", publishedAt: date,
                                  source: .canvas, isLocallyRead: false, sourceURL: nil)], confirmations: []
        )
        let signal = AcademicSignalRecord(
            id: UUID(), analysisID: UUID(), announcementID: announcement, sourceAccountID: "canvas",
            sourceObjectID: "announcement", category: .courseScheduleChange, evidence: "moved",
            keyRequirement: "Attend the make-up class", inferredDate: date, isAllDay: false,
            timeZoneIdentifier: "Asia/Macau", confidence: 1, reason: "Explicit change", conflicts: [],
            provider: "deterministic", model: "local", promptVersion: "v1", schemaVersion: "v1",
            confirmationState: .confirmed, adoptedCategory: nil, adoptedDate: date,
            adoptedIsAllDay: false, courseID: course, createdAt: date, updatedAt: date
        )
        let event = try #require(CalendarPresentation.events(from: snapshot, academicSignals: [signal]).first)
        #expect(event.kind == .confirmedScheduleChange)
        #expect(event.kind != .confirmedInferredDeadline)
    }

    @Test("Reconciliation controls and schedule-change semantics are bilingual and accessible")
    func bilingualAccessibleSurface() throws {
        for key in [
            "Course reconciliation", "Mapping needs confirmation", "Mapped locally",
            "Kept separate locally", "Map", "Keep separate", "Undo", "Reset",
            "Confirmed schedule change"
        ] {
            #expect(Localizer.text(key, language: .simplifiedChinese) != key)
        }
        let settings = try String(
            contentsOfFile: "Sources/CampusDashboard/Features/Settings/SettingsView.swift",
            encoding: .utf8
        )
        #expect(settings.contains("course-map-"))
        #expect(settings.contains("course-separate-"))
        #expect(settings.contains("course-undo-"))
        #expect(settings.contains("course-reset-"))
    }

    private func withDatabase(_ operation: (SQLiteDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("course-reconciliation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase(path: directory.appendingPathComponent("test.sqlite3").path)
        try seedAccount(database, id: "canvas", kind: SourceKind.canvas.rawValue)
        try seedAccount(database, id: "siweb", kind: SourceKind.siweb.rawValue)
        try operation(database)
    }

    private func seedAccount(_ database: SQLiteDatabase, id: String, kind: String) throws {
        try database.execute(
            "INSERT INTO source_accounts(id,source_kind,instance_url,display_name,authorization_state,created_at,updated_at) VALUES(?,?,?,?,'authorized',1,1)",
            bindings: [.text(id), .text(kind), .text("https://example.invalid/\(id)"), .text(id)]
        )
    }

    @discardableResult
    private func seedCourse(_ database: SQLiteDatabase, account: String, id: UUID, objectID: String,
                            name: String, code: String) throws -> UUID {
        try database.execute(
            "INSERT INTO courses(id,source_account_id,source_object_id,name,code,term,time_zone,source_state,first_seen_at,last_seen_at) VALUES(?,?,?,?,?,'2026-1','Asia/Macau','active',1,1)",
            bindings: [.text(id.uuidString), .text(account), .text(objectID), .text(name), .text(code)]
        )
        return id
    }

    private func seedPair(_ database: SQLiteDatabase, canvasName: String, canvasCode: String,
                          siwebName: String, siwebCode: String) throws -> (canvas: UUID, siweb: UUID) {
        let canvas = try seedCourse(database, account: "canvas", id: UUID(), objectID: "canvas-\(UUID())",
                                    name: canvasName, code: canvasCode)
        let siweb = try seedCourse(database, account: "siweb", id: UUID(), objectID: "siweb-\(UUID())",
                                   name: siwebName, code: siwebCode)
        return (canvas, siweb)
    }

    private func seedScheduleSignal(_ database: SQLiteDatabase, canvasCourse: UUID) throws {
        let announcement = UUID(), raw = UUID(), analysis = UUID(), signal = UUID()
        try database.execute(
            "INSERT INTO raw_source_records(id,source_account_id,object_type,source_object_id,fetch_batch_id,content_hash,payload,fetched_at) VALUES(?,'canvas','announcement','ann','batch','hash',X'7B7D',1)",
            bindings: [.text(raw.uuidString)]
        )
        try database.execute(
            "INSERT INTO announcements(id,source_account_id,source_object_id,course_id,title,published_at,summary,content_hash,source_state,first_seen_at,last_seen_at) VALUES(?,'canvas','ann',?,'Schedule change',1,'Moved','hash','active',1,1)",
            bindings: [.text(announcement.uuidString), .text(canvasCourse.uuidString)]
        )
        try database.execute(
            "INSERT INTO academic_signal_analyses(id,raw_source_record_id,announcement_id,source_account_id,source_object_id,content_hash,primary_category,status,provider,model,prompt_version,schema_version,created_at,updated_at) VALUES(?,?,?,'canvas','ann','hash','course_schedule_change','analyzed','deterministic','local','v1','v1',1,1)",
            bindings: [.text(analysis.uuidString), .text(raw.uuidString), .text(announcement.uuidString)]
        )
        try database.execute(
            "INSERT INTO academic_signals(id,analysis_id,announcement_id,source_account_id,source_object_id,category,evidence,key_requirement,inferred_date,is_all_day,confidence,reason,conflicts_json,provider,model,prompt_version,schema_version,confirmation_state,is_active,created_at,updated_at,course_id,audience_resolution) VALUES(?,?,?,'canvas','ann','course_schedule_change','moved','Attend',1000,0,1,'Explicit','[]','deterministic','local','v1','v1','pending',1,1,1,?,'pending_review')",
            bindings: [.text(signal.uuidString), .text(analysis.uuidString), .text(announcement.uuidString), .text(canvasCourse.uuidString)]
        )
    }
}

private actor ReconciliationNoopCenter: UserNotificationCenterClient {
    func authorizationState() async -> NotificationAuthorizationState { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func add(_ request: LocalNotificationRequest) async throws {}
    func removePending(identifiers: [String]) async {}
}
