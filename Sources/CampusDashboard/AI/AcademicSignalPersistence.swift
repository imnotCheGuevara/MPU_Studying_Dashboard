import Foundation

final class AcademicSignalPersistence: @unchecked Sendable {
    private let database: SQLiteDatabase

    init(database: SQLiteDatabase) { self.database = database }

    func analysis(
        rawSourceRecordID: UUID, contentHash: String, provider: String,
        model: String, promptVersion: String, schemaVersion: String
    ) throws -> AcademicAnnouncementAnalysis? {
        try database.query(
            """
            SELECT * FROM academic_signal_analyses
            WHERE raw_source_record_id=? AND content_hash=? AND provider=? AND model=?
              AND prompt_version=? AND schema_version=?
            """, bindings: [
                .text(rawSourceRecordID.uuidString), .text(contentHash), .text(provider),
                .text(model), .text(promptVersion), .text(schemaVersion)
            ]
        ).first.flatMap(decodeAnalysis)
    }

    @discardableResult
    func saveAnalysis(_ value: AcademicAnnouncementAnalysis) throws -> AcademicAnnouncementAnalysis {
        try database.execute(
            """
            INSERT INTO academic_signal_analyses
              (id,raw_source_record_id,announcement_id,source_account_id,source_object_id,
               content_hash,primary_category,status,provider,model,prompt_version,schema_version,
               failure_category,created_at,updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(raw_source_record_id,content_hash,provider,model,prompt_version,schema_version)
            DO UPDATE SET status=excluded.status,failure_category=excluded.failure_category,
              updated_at=excluded.updated_at
            """, bindings: [
                .text(value.id.uuidString), .text(value.rawSourceRecordID.uuidString),
                .text(value.announcementID.uuidString), .text(value.sourceAccountID),
                .text(value.sourceObjectID), .text(value.contentHash),
                .text(value.primaryCategory.rawValue), .text(value.status.rawValue),
                .text(value.provider), .text(value.model), .text(value.promptVersion),
                .text(value.schemaVersion), value.failureCategory.map(SQLiteValue.text) ?? .null,
                .real(value.createdAt.timeIntervalSince1970), .real(value.updatedAt.timeIntervalSince1970)
            ]
        )
        return try analysis(
            rawSourceRecordID: value.rawSourceRecordID, contentHash: value.contentHash,
            provider: value.provider, model: value.model, promptVersion: value.promptVersion,
            schemaVersion: value.schemaVersion
        ) ?? value
    }

    func replaceActiveSignals(analysisID: UUID, values: [AcademicSignalRecord]) throws {
        try database.transaction {
            try database.execute(
                """
                UPDATE academic_signals SET is_active=0
                WHERE announcement_id=(SELECT announcement_id FROM academic_signal_analyses WHERE id=?)
                  AND decision_origin!='user_correction'
                """,
                bindings: [.text(analysisID.uuidString)]
            )
            for value in values { try insertSignal(value) }
        }
    }

    func analyses() throws -> [AcademicAnnouncementAnalysis] {
        try database.query(
            "SELECT * FROM academic_signal_analyses ORDER BY created_at DESC,id DESC"
        ).compactMap(decodeAnalysis)
    }

    func activeSignals() throws -> [AcademicSignalRecord] {
        try database.query(
            "SELECT * FROM academic_signals WHERE is_active=1 ORDER BY created_at DESC,id DESC"
        ).compactMap(decodeSignal)
    }

    func signal(id: UUID) throws -> AcademicSignalRecord? {
        try database.query("SELECT * FROM academic_signals WHERE id=?", bindings: [.text(id.uuidString)])
            .first.flatMap(decodeSignal)
    }

    func hasActiveUserDecision(announcementID: UUID) throws -> Bool {
        try database.query(
            "SELECT COUNT(*) AS value FROM academic_signals WHERE announcement_id=? AND is_active=1 AND decision_origin='user_correction'",
            bindings: [.text(announcementID.uuidString)]
        ).first?.int("value") ?? 0 > 0
    }

    func transition(
        id: UUID, action: String, correction: AcademicSignalCorrection?, now: Date,
        auditID: UUID
    ) throws {
        guard let value = try signal(id: id) else { throw AIParsingError.invalidTransition }
        let next: AcademicSignalConfirmationState
        switch action {
        case "confirm": next = .confirmed
        case "correct": next = .corrected
        case "reject": next = .rejected
        case "undo": next = .undone
        case "reset": next = value.inferredDate == nil ? .notRequired : .pending
        default: throw AIParsingError.invalidTransition
        }
        let deciding = ["confirm", "correct", "reject"].contains(action)
        guard (!deciding || [.pending, .notRequired, .confirmed, .corrected, .rejected, .undone]
                .contains(value.confirmationState)),
              (action != "confirm" || value.category != .courseScheduleChange
                || value.audienceResolution == .resolved),
              (action != "undo" || [.confirmed, .corrected, .rejected].contains(value.confirmationState)),
              (action != "reset" || value.decisionOrigin == .userCorrection) else {
            throw AIParsingError.invalidTransition
        }
        let adoptedCategory = correction?.category ?? value.category
        let adoptedDate = correction?.inferredDate ?? value.inferredDate
        let adoptedAllDay = correction?.isAllDay ?? value.isAllDay
        let correctedCourseID = correction?.courseID ?? value.courseID
        let correctedTarget = correction == nil ? value.targetMeetingID
            : try resolvedMeeting(courseID: correctedCourseID, category: adoptedCategory, date: adoptedDate)
        let audience: AcademicAudienceResolution = adoptedCategory == .courseScheduleChange
            ? (correctedTarget == nil ? .pendingReview : .resolved) : .noTarget
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let correctionData = correction.flatMap { try? encoder.encode($0) }
        try database.transaction {
            try database.execute(
                """
                UPDATE academic_signals SET confirmation_state=?,adopted_category=?,adopted_date=?,
                  adopted_is_all_day=?,course_id=COALESCE(?,course_id),adopted_key_requirement=?,
                  adopted_time_zone_identifier=?,decision_origin=?,target_meeting_id=?,
                  audience_resolution=?,updated_at=? WHERE id=?
                """, bindings: [
                    .text(next.rawValue), next == .rejected ? .null : .text(adoptedCategory.rawValue),
                    [.rejected, .undone].contains(next) || action == "reset" ? .null : adoptedDate.map { .real($0.timeIntervalSince1970) } ?? .null,
                    [.rejected, .undone].contains(next) || action == "reset" ? .null : .integer(adoptedAllDay ? 1 : 0),
                    correction?.courseID.map { .text($0.uuidString) } ?? .null,
                    action == "reset" ? .null : correction.map { .text($0.keyRequirement) } ?? value.adoptedKeyRequirement.map(SQLiteValue.text) ?? .null,
                    action == "reset" ? .null : correction?.timeZoneIdentifier.map(SQLiteValue.text) ?? value.adoptedTimeZoneIdentifier.map(SQLiteValue.text) ?? .null,
                    .text(correction == nil ? value.decisionOrigin.rawValue : AcademicDecisionOrigin.userCorrection.rawValue),
                    correctedTarget.map { .text($0.uuidString) } ?? .null, .text(audience.rawValue),
                    .real(now.timeIntervalSince1970), .text(id.uuidString)
                ]
            )
            try database.execute(
                """
                INSERT INTO academic_signal_audit
                  (id,signal_id,action,previous_state,new_state,correction_json,occurred_at)
                VALUES(?,?,?,?,?,?,?)
                """, bindings: [
                    .text(auditID.uuidString), .text(id.uuidString), .text(action),
                    .text(value.confirmationState.rawValue), .text(next.rawValue),
                    correctionData.map(SQLiteValue.blob) ?? .null,
                    .real(now.timeIntervalSince1970)
                ]
            )
            let calendarSafe = adoptedCategory == .courseScheduleChange
                ? correctedTarget != nil
                : adoptedDate != nil
            if calendarSafe || value.targetMeetingID != nil {
                try enqueueCalendarDecision(signalID: id, eligible: calendarSafe && ![.rejected, .undone].contains(next) && action != "reset", now: now, action: action)
            }
        }
    }

    func correctAnalysis(id: UUID, correction: AcademicSignalCorrection, now: Date,
                         signalID: UUID, auditID: UUID) throws {
        guard let analysis = try database.query(
            "SELECT * FROM academic_signal_analyses WHERE id=?", bindings: [.text(id.uuidString)]
        ).first, let announcementID = analysis.string("announcement_id").flatMap(UUID.init(uuidString:)),
              let accountID = analysis.string("source_account_id"), let sourceID = analysis.string("source_object_id")
        else { throw AIParsingError.invalidTransition }
        let defaultCourse = try database.query(
            "SELECT course_id,title FROM announcements WHERE id=?", bindings: [.text(announcementID.uuidString)]
        ).first
        let courseID = correction.courseID ?? defaultCourse?.string("course_id").flatMap(UUID.init(uuidString:))
        let targetMeetingID = try resolvedMeeting(
            courseID: courseID, category: correction.category, date: correction.inferredDate
        )
        let audience: AcademicAudienceResolution = correction.category == .courseScheduleChange
            ? (targetMeetingID == nil ? .pendingReview : .resolved) : .noTarget
        let record = AcademicSignalRecord(
            id: signalID, analysisID: id, announcementID: announcementID,
            sourceAccountID: accountID, sourceObjectID: sourceID, category: correction.category,
            evidence: "User-created local correction", keyRequirement: correction.keyRequirement,
            inferredDate: correction.inferredDate, isAllDay: correction.isAllDay,
            timeZoneIdentifier: correction.timeZoneIdentifier, confidence: 1,
            reason: "Explicit local supervised feedback.", conflicts: [],
            provider: analysis.string("provider") ?? "Local correction",
            model: analysis.string("model") ?? "local", promptVersion: analysis.string("prompt_version") ?? "local",
            schemaVersion: analysis.string("schema_version") ?? "local", confirmationState: .corrected,
            adoptedCategory: correction.category, adoptedDate: correction.inferredDate,
            adoptedIsAllDay: correction.isAllDay, courseID: courseID,
            adoptedKeyRequirement: correction.keyRequirement,
            adoptedTimeZoneIdentifier: correction.timeZoneIdentifier,
            decisionOrigin: .userCorrection, personalizationRuleVersion: "course-local-v1",
            targetMeetingID: targetMeetingID, audienceResolution: audience,
            createdAt: now, updatedAt: now
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try database.transaction {
            try database.execute(
                "UPDATE academic_signals SET is_active=0 WHERE analysis_id=? AND decision_origin='user_correction'",
                bindings: [.text(id.uuidString)]
            )
            try insertSignal(record)
            try database.execute(
                """
                INSERT INTO academic_signal_audit
                  (id,signal_id,action,previous_state,new_state,correction_json,occurred_at)
                VALUES(?,?,'correct_analysis','not_required','corrected',?,?)
                """, bindings: [.text(auditID.uuidString), .text(signalID.uuidString),
                    .blob(try encoder.encode(correction)), .real(now.timeIntervalSince1970)]
            )
            if let courseID, let title = defaultCourse?.string("title") {
                let trigger = String(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
                if !trigger.isEmpty {
                    try database.execute(
                        """
                        INSERT INTO academic_personalization_rules
                          (id,course_id,trigger_phrase,category,key_requirement,rule_version,is_active,created_at,updated_at)
                        VALUES(?,?,?,?,?,'course-local-v1',1,?,?)
                        ON CONFLICT(course_id,trigger_phrase,rule_version) DO UPDATE SET
                          category=excluded.category,key_requirement=excluded.key_requirement,is_active=1,updated_at=excluded.updated_at
                        """, bindings: [.text(UUID().uuidString), .text(courseID.uuidString), .text(trigger),
                            .text(correction.category.rawValue), .text(correction.keyRequirement),
                            .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)]
                    )
                }
            }
            let calendarSafe = correction.category == .courseScheduleChange
                ? targetMeetingID != nil : correction.inferredDate != nil
            if calendarSafe {
                try enqueueCalendarDecision(signalID: signalID, eligible: true,
                                            now: now, action: "correct_analysis")
            }
        }
    }

    private func resolvedMeeting(
        courseID: UUID?, category: AcademicSignalCategory, date: Date?
    ) throws -> UUID? {
        guard category == .courseScheduleChange, let courseID else { return nil }
        let directKind = try database.query(
            "SELECT s.source_kind FROM courses c JOIN source_accounts s ON s.id=c.source_account_id WHERE c.id=?",
            bindings: [.text(courseID.uuidString)]
        ).first?.string("source_kind")
        let localCourseIDs: [String]
        if directKind == "SIweb" {
            localCourseIDs = [courseID.uuidString]
        } else {
            localCourseIDs = try database.query(
                "SELECT siweb_course_id FROM academic_course_mappings WHERE canvas_course_id=? AND is_active=1",
                bindings: [.text(courseID.uuidString)]
            ).compactMap { $0.string("siweb_course_id") }
        }
        guard localCourseIDs.count == 1 else { return nil }
        let rows = try database.query(
            "SELECT id,starts_at FROM course_meetings WHERE course_id=? AND source_state='active'",
            bindings: [.text(localCourseIDs[0])]
        )
        let matches = date.map { date in
            rows.filter { row in
                guard let start = row.double("starts_at") else { return false }
                return abs(start - date.timeIntervalSince1970) <= 43_200
            }
        } ?? rows
        guard matches.count == 1 else { return nil }
        return matches[0].string("id").flatMap(UUID.init(uuidString:))
    }

    private func insertSignal(_ value: AcademicSignalRecord) throws {
        try database.execute(
            """
            INSERT INTO academic_signals
              (id,analysis_id,announcement_id,source_account_id,source_object_id,category,
               evidence,key_requirement,inferred_date,is_all_day,time_zone_identifier,confidence,
               reason,conflicts_json,provider,model,prompt_version,schema_version,
               confirmation_state,adopted_category,adopted_date,adopted_is_all_day,is_active,
               course_id,adopted_key_requirement,adopted_time_zone_identifier,decision_origin,
               personalization_rule_version,target_meeting_id,audience_resolution,
               created_at,updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?,?,?,?,?,?,?,?)
            """, bindings: [
                .text(value.id.uuidString), .text(value.analysisID.uuidString),
                .text(value.announcementID.uuidString), .text(value.sourceAccountID),
                .text(value.sourceObjectID), .text(value.category.rawValue), .text(value.evidence),
                .text(value.keyRequirement), value.inferredDate.map { .real($0.timeIntervalSince1970) } ?? .null,
                .integer(value.isAllDay ? 1 : 0), value.timeZoneIdentifier.map(SQLiteValue.text) ?? .null,
                .real(value.confidence), .text(value.reason), .text(json(value.conflicts)),
                .text(value.provider), .text(value.model), .text(value.promptVersion),
                .text(value.schemaVersion), .text(value.confirmationState.rawValue),
                value.adoptedCategory.map { .text($0.rawValue) } ?? .null,
                value.adoptedDate.map { .real($0.timeIntervalSince1970) } ?? .null,
                value.adoptedIsAllDay.map { .integer($0 ? 1 : 0) } ?? .null,
                value.courseID.map { .text($0.uuidString) } ?? .null,
                value.adoptedKeyRequirement.map(SQLiteValue.text) ?? .null,
                value.adoptedTimeZoneIdentifier.map(SQLiteValue.text) ?? .null,
                .text(value.decisionOrigin.rawValue),
                value.personalizationRuleVersion.map(SQLiteValue.text) ?? .null,
                value.targetMeetingID.map { .text($0.uuidString) } ?? .null,
                .text(value.audienceResolution.rawValue),
                .real(value.createdAt.timeIntervalSince1970), .real(value.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    private func decodeAnalysis(_ row: SQLiteRow) -> AcademicAnnouncementAnalysis? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
              let rawID = row.string("raw_source_record_id").flatMap(UUID.init(uuidString:)),
              let announcementID = row.string("announcement_id").flatMap(UUID.init(uuidString:)),
              let accountID = row.string("source_account_id"), let sourceID = row.string("source_object_id"),
              let hash = row.string("content_hash"),
              let category = row.string("primary_category").flatMap(AcademicSignalCategory.init(rawValue:)),
              let status = row.string("status").flatMap(AcademicAnalysisStatus.init(rawValue:)),
              let provider = row.string("provider"), let model = row.string("model"),
              let prompt = row.string("prompt_version"), let schema = row.string("schema_version"),
              let created = row.double("created_at") else { return nil }
        return AcademicAnnouncementAnalysis(
            id: id, rawSourceRecordID: rawID, announcementID: announcementID,
            sourceAccountID: accountID, sourceObjectID: sourceID, contentHash: hash,
            primaryCategory: category, status: status, provider: provider, model: model,
            promptVersion: prompt, schemaVersion: schema,
            failureCategory: row.string("failure_category"),
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? created)
        )
    }

    private func decodeSignal(_ row: SQLiteRow) -> AcademicSignalRecord? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
              let analysisID = row.string("analysis_id").flatMap(UUID.init(uuidString:)),
              let announcementID = row.string("announcement_id").flatMap(UUID.init(uuidString:)),
              let accountID = row.string("source_account_id"), let sourceID = row.string("source_object_id"),
              let category = row.string("category").flatMap(AcademicSignalCategory.init(rawValue:)),
              let evidence = row.string("evidence"), let requirement = row.string("key_requirement"),
              let confidence = row.double("confidence"), let reason = row.string("reason"),
              let provider = row.string("provider"), let model = row.string("model"),
              let prompt = row.string("prompt_version"), let schema = row.string("schema_version"),
              let state = row.string("confirmation_state").flatMap(AcademicSignalConfirmationState.init(rawValue:)),
              let created = row.double("created_at") else { return nil }
        return AcademicSignalRecord(
            id: id, analysisID: analysisID, announcementID: announcementID,
            sourceAccountID: accountID, sourceObjectID: sourceID, category: category,
            evidence: evidence, keyRequirement: requirement,
            inferredDate: row.double("inferred_date").map(Date.init(timeIntervalSince1970:)),
            isAllDay: row.int("is_all_day") == 1, timeZoneIdentifier: row.string("time_zone_identifier"),
            confidence: confidence, reason: reason, conflicts: strings(row.string("conflicts_json")),
            provider: provider, model: model, promptVersion: prompt, schemaVersion: schema,
            confirmationState: state,
            adoptedCategory: row.string("adopted_category").flatMap(AcademicSignalCategory.init(rawValue:)),
            adoptedDate: row.double("adopted_date").map(Date.init(timeIntervalSince1970:)),
            adoptedIsAllDay: row.int("adopted_is_all_day").map { $0 == 1 },
            courseID: row.string("course_id").flatMap(UUID.init(uuidString:)),
            adoptedKeyRequirement: row.string("adopted_key_requirement"),
            adoptedTimeZoneIdentifier: row.string("adopted_time_zone_identifier"),
            decisionOrigin: row.string("decision_origin").flatMap(AcademicDecisionOrigin.init(rawValue:)) ?? .automated,
            personalizationRuleVersion: row.string("personalization_rule_version"),
            targetMeetingID: row.string("target_meeting_id").flatMap(UUID.init(uuidString:)),
            audienceResolution: row.string("audience_resolution").flatMap(AcademicAudienceResolution.init(rawValue:)) ?? .noTarget,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? created)
        )
    }

    private func enqueueCalendarDecision(signalID: UUID, eligible: Bool, now: Date, action: String) throws {
        let targetMeetingID = try database.query(
            "SELECT target_meeting_id FROM academic_signals WHERE id=?", bindings: [.text(signalID.uuidString)]
        ).first?.string("target_meeting_id")
        let objectType = targetMeetingID == nil ? "academic_signal" : "course_meeting"
        let objectID = targetMeetingID ?? signalID.uuidString
        let envelope: OutboxEnvelope = eligible
            ? .calendarReconcile(objectType: objectType, objectID: objectID)
            : .calendarReconcile(objectType: objectType, objectID: objectID)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        let kind = "calendar.reconcile"
        let dedupe = "\(kind):\(objectType):\(objectID):\(action):\(String(format: "%.6f", now.timeIntervalSince1970))"
        try database.execute(
            """
            INSERT INTO outbox_work
              (id,kind,deduplication_key,object_type,object_id,payload,state,attempt_count,available_at,created_at,updated_at,last_error_category)
            VALUES(?,?,?,?,?,?,'pending',0,?,?,?,NULL) ON CONFLICT(deduplication_key) DO NOTHING
            """, bindings: [.text(UUID().uuidString), .text(kind), .text(dedupe), .text(objectType),
                .text(objectID), .blob(try encoder.encode(envelope)),
                .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)]
        )
    }

    private func json(_ values: [String]) -> String {
        String(decoding: (try? JSONEncoder().encode(values)) ?? Data("[]".utf8), as: UTF8.self)
    }
    private func strings(_ value: String?) -> [String] {
        guard let data = value?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
