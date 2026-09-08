import Foundation

enum CourseMappingDecisionState: String, Sendable {
    case proposed
    case confirmed
    case separate
    case undone
}

struct CourseMappingDecision: Identifiable, Equatable, Sendable {
    let id: UUID
    let canvasCourseID: UUID
    let siwebCourseID: UUID
    let canvasName: String
    let canvasCode: String
    let siwebName: String
    let siwebCode: String
    let state: CourseMappingDecisionState
    let origin: String
    let confidence: Double
    let canUndo: Bool
}

enum CourseIdentityNormalizer {
    private static let codeExpression = try! NSRegularExpression(
        pattern: #"(?i)([A-Z]{2,}\s*[- ]?\d{3,4}(?:\s*[-_/]\s*(?:[A-Z]{1,3}|\d{1,3}))?)"#
    )
    private static let wholeCodeExpression = try! NSRegularExpression(
        pattern: #"(?i)^\s*([A-Z]{2,}\s*[- ]?\d{3,4}(?:\s*[-_/]\s*(?:[A-Z]{1,3}|\d{1,3}))?)\s*$"#
    )
    private static let compactCodeExpression = try! NSRegularExpression(
        pattern: #"(?i)^\s*([A-Z][A-Z0-9_-]{1,15})\s*$"#
    )
    private static let termPrefixExpression = try! NSRegularExpression(
        pattern: #"(?i)^\s*(?:\(\s*\d{2}\s*/\s*\d{2}\s*-\s*S[123]\s*\)|(?:(?:spring|summer|autumn|fall|winter|semester|term)\s*)?20\d{2}(?:\s*[-/]\s*(?:1|2|3|spring|summer|autumn|fall|winter))?)\s*[-:|·]*\s*"#
    )

    static func embeddedCode(name: String, rawCode: String) -> String? {
        if let whole = wholeMatch(wholeCodeExpression, in: rawCode) {
            return normalizedFullCode(whole)
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        let matches = codeExpression.matches(in: name, range: range)
        if let match = matches.last, let swiftRange = Range(match.range(at: 1), in: name) {
            return normalizedFullCode(String(name[swiftRange]))
        }
        if let compact = wholeMatch(compactCodeExpression, in: rawCode) {
            return normalizedFullCode(compact)
        }
        return nil
    }

    static func normalizedFullCode(_ value: String) -> String {
        value.uppercased().unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init).joined()
    }

    static func baseCode(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let expression = try! NSRegularExpression(pattern: #"^([A-Z]{2,}\d{3,4})"#)
        guard let match = expression.firstMatch(
            in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)
        ), let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    static func sectionIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalizedFullCode(value)
        guard !normalized.isEmpty else { return nil }
        if let base = baseCode(normalized), normalized.count > base.count {
            return String(normalized.dropFirst(base.count))
        }
        let stripped = normalized
            .replacingOccurrences(of: "SECTION", with: "")
            .replacingOccurrences(of: "SEC", with: "")
        return stripped.isEmpty ? nil : stripped
    }

    static func normalizedTitle(_ value: String) -> String {
        var result = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        result = replacing(termPrefixExpression, in: result, with: "")
        result = replacing(codeExpression, in: result, with: " ")
        return result.lowercased().unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init).joined()
    }

    static func displayTitle(name: String, code: String) -> String {
        let stripped = replacing(termPrefixExpression, in: name, with: "")
        let withoutCode = replacing(codeExpression, in: stripped, with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let title = withoutCode.isEmpty ? name : withoutCode
        return code.isEmpty ? title : "\(code) · \(title)"
    }

    private static func wholeMatch(_ expression: NSRegularExpression, in value: String) -> String? {
        guard let match = expression.firstMatch(
            in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)
        ), let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func replacing(
        _ expression: NSRegularExpression, in value: String, with replacement: String
    ) -> String {
        expression.stringByReplacingMatches(
            in: value, range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: replacement
        )
    }
}

final class CourseReconciliationService: @unchecked Sendable {
    private struct SourceCourse {
        let id: UUID
        let name: String
        let rawCode: String
        let source: SourceKind
        let titleKey: String
        let fullCode: String?
        let baseCode: String?
    }

    private let database: SQLiteDatabase
    private let now: @Sendable () -> Date

    init(database: SQLiteDatabase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.now = now
    }

    @discardableResult
    func reconcile() throws -> [CourseMappingDecision] {
        let courses = try sourceCourses()
        let canvas = courses.filter { $0.source == .canvas }
        let siweb = courses.filter { $0.source == .siweb }
        let canvasTitleCounts = Dictionary(grouping: canvas, by: \.titleKey).mapValues(\.count)
        let siwebTitleCounts = Dictionary(grouping: siweb, by: \.titleKey).mapValues(\.count)

        for left in canvas where !left.titleKey.isEmpty && canvasTitleCounts[left.titleKey] == 1 {
            let titleMatches = siweb.filter { $0.titleKey == left.titleKey }
            guard titleMatches.count == 1, siwebTitleCounts[left.titleKey] == 1,
                  let right = titleMatches.first else { continue }
            let state: CourseMappingDecisionState
            let origin: String
            let confidence: Double
            if left.fullCode != nil, left.fullCode == right.fullCode {
                state = .confirmed; origin = "auto_full_code_title"; confidence = 1
            } else if left.baseCode != nil, left.baseCode == right.baseCode {
                state = .confirmed; origin = "auto_code_family_unique_title"; confidence = 0.98
            } else {
                state = .proposed; origin = "proposed_unique_title_code_conflict"; confidence = 0.75
            }
            try persistCandidate(left: left, right: right, state: state, origin: origin, confidence: confidence)
        }
        try reresolveScheduleSignals()
        return try decisions()
    }

    func decisions(includeResolved: Bool = true) throws -> [CourseMappingDecision] {
        let clause = includeResolved ? "" : "AND m.decision_state='proposed'"
        return try database.query(
            """
            SELECT m.*,cc.name AS canvas_name,cc.code AS canvas_code,
                   sc.name AS siweb_name,sc.code AS siweb_code,
                   EXISTS(SELECT 1 FROM academic_course_mapping_audit a WHERE a.mapping_id=m.id) AS can_undo
            FROM academic_course_mappings m
            JOIN courses cc ON cc.id=m.canvas_course_id
            JOIN courses sc ON sc.id=m.siweb_course_id
            WHERE 1=1 \(clause)
            ORDER BY CASE m.decision_state WHEN 'proposed' THEN 0 ELSE 1 END,cc.name,m.id
            """
        ).compactMap(decodeDecision)
    }

    func map(_ id: UUID) throws { try transition(id, to: .confirmed, action: "map") }
    func keepSeparate(_ id: UUID) throws { try transition(id, to: .separate, action: "keep_separate") }
    func reset(_ id: UUID) throws { try transition(id, to: .proposed, action: "reset") }

    func undo(_ id: UUID) throws {
        guard let audit = try database.query(
            "SELECT previous_state FROM academic_course_mapping_audit WHERE mapping_id=? AND action!='undo' ORDER BY occurred_at DESC,id DESC LIMIT 1",
            bindings: [.text(id.uuidString)]
        ).first, let raw = audit.string("previous_state"),
              let state = CourseMappingDecisionState(rawValue: raw) else { return }
        try transition(id, to: state, action: "undo")
    }

    func canonicalCourseIDs() throws -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for row in try database.query(
            "SELECT canvas_course_id,siweb_course_id FROM academic_course_mappings WHERE is_active=1 AND decision_state='confirmed'"
        ) {
            guard let canvas = row.string("canvas_course_id").flatMap(UUID.init(uuidString:)),
                  let siweb = row.string("siweb_course_id").flatMap(UUID.init(uuidString:)) else { continue }
            result[canvas] = canvas
            result[siweb] = canvas
        }
        return result
    }

    private func sourceCourses() throws -> [SourceCourse] {
        try database.query(
            """
            SELECT c.id,c.name,c.code,sa.source_kind FROM courses c
            JOIN source_accounts sa ON sa.id=c.source_account_id
            WHERE c.source_state='active' AND LOWER(sa.source_kind) IN ('canvas','siweb')
            """
        ).compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let source = row.string("source_kind").flatMap(SourceKind.init(databaseValue:)) else { return nil }
            let name = row.string("name") ?? ""
            let rawCode = row.string("code") ?? ""
            let full = source == .canvas
                ? CourseIdentityNormalizer.embeddedCode(name: name, rawCode: rawCode)
                : CourseIdentityNormalizer.embeddedCode(name: rawCode, rawCode: rawCode)
            return SourceCourse(
                id: id, name: name, rawCode: rawCode, source: source,
                titleKey: CourseIdentityNormalizer.normalizedTitle(name), fullCode: full,
                baseCode: CourseIdentityNormalizer.baseCode(full)
            )
        }
    }

    private func persistCandidate(
        left: SourceCourse, right: SourceCourse, state: CourseMappingDecisionState,
        origin: String, confidence: Double
    ) throws {
        let existing = try database.query(
            "SELECT id,decision_state,origin FROM academic_course_mappings WHERE canvas_course_id=? AND siweb_course_id=? ORDER BY updated_at DESC LIMIT 1",
            bindings: [.text(left.id.uuidString), .text(right.id.uuidString)]
        ).first
        if let existing, let id = existing.string("id") {
            let priorState = existing.string("decision_state") ?? "confirmed"
            let priorOrigin = existing.string("origin") ?? ""
            if priorOrigin.hasPrefix("user_") || priorState == CourseMappingDecisionState.separate.rawValue { return }
            if priorState == CourseMappingDecisionState.confirmed.rawValue { return }
            try database.execute(
                "UPDATE academic_course_mappings SET section_key=?,origin=?,decision_state=?,canvas_code_key=?,siweb_code_key=?,title_key=?,confidence=?,is_active=?,updated_at=? WHERE id=?",
                bindings: [
                    left.fullCode.map(SQLiteValue.text) ?? .null, .text(origin), .text(state.rawValue),
                    left.fullCode.map(SQLiteValue.text) ?? .null,
                    right.fullCode.map(SQLiteValue.text) ?? .null, .text(left.titleKey), .real(confidence),
                    .integer(state == .confirmed ? 1 : 0), .real(now().timeIntervalSince1970), .text(id)
                ]
            )
            return
        }
        if state == .confirmed {
            let collision = Int(try database.query(
                "SELECT COUNT(*) AS count FROM academic_course_mappings WHERE is_active=1 AND (canvas_course_id=? OR siweb_course_id=?)",
                bindings: [.text(left.id.uuidString), .text(right.id.uuidString)]
            ).first?.int("count") ?? 0)
            guard collision == 0 else { return }
        }
        let timestamp = now().timeIntervalSince1970
        try database.execute(
            """
            INSERT INTO academic_course_mappings
              (id,canvas_course_id,siweb_course_id,section_key,origin,is_active,created_at,updated_at,
               decision_state,canvas_code_key,siweb_code_key,title_key,confidence)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, bindings: [
                .text(UUID().uuidString), .text(left.id.uuidString), .text(right.id.uuidString)
            ] + mappingBindings(left: left, right: right, state: state, origin: origin,
                                 confidence: confidence, timestamp: timestamp)
        )
    }

    private func mappingBindings(
        left: SourceCourse, right: SourceCourse, state: CourseMappingDecisionState,
        origin: String, confidence: Double, timestamp: Double? = nil
    ) -> [SQLiteValue] {
        let time = timestamp ?? now().timeIntervalSince1970
        let common: [SQLiteValue] = [
            left.fullCode.map(SQLiteValue.text) ?? .null, .text(origin),
            .integer(state == .confirmed ? 1 : 0)
        ]
        return common + [.real(time), .real(time), .text(state.rawValue),
            left.fullCode.map(SQLiteValue.text) ?? .null,
            right.fullCode.map(SQLiteValue.text) ?? .null, .text(left.titleKey), .real(confidence)]
    }

    private func transition(
        _ id: UUID, to state: CourseMappingDecisionState, action: String
    ) throws {
        guard let row = try database.query(
            "SELECT decision_state,canvas_course_id,siweb_course_id FROM academic_course_mappings WHERE id=?",
            bindings: [.text(id.uuidString)]
        ).first else { return }
        let previous = row.string("decision_state") ?? CourseMappingDecisionState.confirmed.rawValue
        let timestamp = now().timeIntervalSince1970
        try database.transaction {
            if state == .confirmed {
                try database.execute(
                    "UPDATE academic_course_mappings SET is_active=0 WHERE id<>? AND (canvas_course_id=? OR siweb_course_id=?)",
                    bindings: [.text(id.uuidString), .text(row.string("canvas_course_id") ?? ""),
                               .text(row.string("siweb_course_id") ?? "")]
                )
            }
            try database.execute(
                "UPDATE academic_course_mappings SET decision_state=?,origin=?,is_active=?,updated_at=? WHERE id=?",
                bindings: [.text(state.rawValue), .text("user_\(action)"),
                           .integer(state == .confirmed ? 1 : 0), .real(timestamp), .text(id.uuidString)]
            )
            try database.execute(
                "INSERT INTO academic_course_mapping_audit(id,mapping_id,action,previous_state,new_state,occurred_at) VALUES(?,?,?,?,?,?)",
                bindings: [.text(UUID().uuidString), .text(id.uuidString), .text(action),
                           .text(previous), .text(state.rawValue), .real(timestamp)]
            )
        }
        try reresolveScheduleSignals()
    }

    private func reresolveScheduleSignals() throws {
        let signals = try database.query(
            """
            SELECT s.* FROM academic_signals s
            JOIN courses c ON c.id=s.course_id JOIN source_accounts sa ON sa.id=c.source_account_id
            WHERE s.is_active=1
              AND COALESCE(s.adopted_category,s.category)='course_schedule_change'
              AND LOWER(sa.source_kind) IN ('canvas','siweb')
            """
        )
        for signal in signals {
            guard let signalID = signal.string("id"),
                  let courseID = signal.string("course_id").flatMap(UUID.init(uuidString:))
            else { continue }
            let previousTarget = signal.string("target_meeting_id").flatMap(UUID.init(uuidString:))
            let proposedTarget = signal.string("proposed_target_meeting_id").flatMap(UUID.init(uuidString:))
            let role = signal.string("schedule_date_role").flatMap(AcademicScheduleDateRole.init(rawValue:))
            let expectedTarget = previousTarget ?? proposedTarget
            let date = signal.double("adopted_date").map(Date.init(timeIntervalSince1970:))
                ?? signal.double("inferred_date").map(Date.init(timeIntervalSince1970:))
            let target = try AcademicScheduleTargetResolver.revalidate(
                database: database, courseID: courseID, date: date,
                isAllDay: signal.int("adopted_is_all_day").map { $0 == 1 }
                    ?? (signal.int("is_all_day") == 1),
                dateRole: role,
                affectedSection: signal.string("affected_section"),
                proposedTarget: proposedTarget,
                expectedTarget: expectedTarget
            )
            let previousState = signal.string("confirmation_state")
                .flatMap(AcademicSignalConfirmationState.init(rawValue:)) ?? .pending
            let invalidated = [.confirmed, .corrected].contains(previousState) && target == nil
            let nextState: AcademicSignalConfirmationState = invalidated ? .pending : previousState
            let audience: AcademicAudienceResolution = target == nil ? .pendingReview : .resolved
            let targetChanged = previousTarget != target
            let audienceChanged = signal.string("audience_resolution") != audience.rawValue

            if targetChanged || audienceChanged || invalidated {
                let timestamp = now()
                try database.transaction {
                    try database.execute(
                        "UPDATE academic_signals SET target_meeting_id=?,audience_resolution=?,confirmation_state=?,updated_at=? WHERE id=?",
                        bindings: [target.map { .text($0.uuidString) } ?? .null,
                                   .text(audience.rawValue), .text(nextState.rawValue),
                                   .real(timestamp.timeIntervalSince1970), .text(signalID)]
                    )
                    if invalidated {
                        try database.execute(
                            "INSERT INTO academic_signal_audit(id,signal_id,action,previous_state,new_state,correction_json,occurred_at) VALUES(?,?,'target_invalidated',?,?,NULL,?)",
                            bindings: [.text(UUID().uuidString), .text(signalID),
                                       .text(previousState.rawValue), .text(nextState.rawValue),
                                       .real(timestamp.timeIntervalSince1970)]
                        )
                    }
                }
            }
            if let previousTarget, previousTarget != target {
                try enqueueCalendarReconcileIfBound(
                    objectType: "course_meeting", objectID: previousTarget.uuidString,
                    action: "schedule_target_invalidated"
                )
            }
            try enqueueCalendarReconcileIfBound(
                objectType: "academic_signal", objectID: signalID,
                action: "schedule_standalone_cleanup"
            )
        }
    }

    private func enqueueCalendarReconcileIfBound(
        objectType: String, objectID: String, action: String
    ) throws {
        let hasBinding = try database.query(
            "SELECT 1 AS value FROM calendar_bindings WHERE object_type=? AND object_id=? AND sync_state!='removed' LIMIT 1",
            bindings: [.text(objectType), .text(objectID)]
        ).first != nil
        guard hasBinding else { return }
        let alreadyPending = try database.query(
            "SELECT 1 AS value FROM outbox_work WHERE kind='calendar.reconcile' AND object_type=? AND object_id=? AND state IN ('pending','retry') LIMIT 1",
            bindings: [.text(objectType), .text(objectID)]
        ).first != nil
        guard !alreadyPending else { return }
        let timestamp = now()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        let envelope = OutboxEnvelope.calendarReconcile(objectType: objectType, objectID: objectID)
        try database.execute(
            """
            INSERT INTO outbox_work
              (id,kind,deduplication_key,object_type,object_id,payload,state,attempt_count,
               available_at,created_at,updated_at,last_error_category)
            VALUES(?,'calendar.reconcile',?,?,?,?, 'pending',0,?,?,?,NULL)
            """, bindings: [
                .text(UUID().uuidString),
                .text("calendar.reconcile:\(objectType):\(objectID):\(action):\(timestamp.timeIntervalSince1970)"),
                .text(objectType), .text(objectID), .blob(try encoder.encode(envelope)),
                .real(timestamp.timeIntervalSince1970), .real(timestamp.timeIntervalSince1970),
                .real(timestamp.timeIntervalSince1970)
            ]
        )
    }

    private func decodeDecision(_ row: SQLiteRow) -> CourseMappingDecision? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
              let canvasID = row.string("canvas_course_id").flatMap(UUID.init(uuidString:)),
              let siwebID = row.string("siweb_course_id").flatMap(UUID.init(uuidString:)),
              let state = row.string("decision_state").flatMap(CourseMappingDecisionState.init(rawValue:))
        else { return nil }
        return CourseMappingDecision(
            id: id, canvasCourseID: canvasID, siwebCourseID: siwebID,
            canvasName: row.string("canvas_name") ?? "Canvas course",
            canvasCode: row.string("canvas_code_key") ?? row.string("canvas_code") ?? "",
            siwebName: row.string("siweb_name") ?? "SIweb course",
            siwebCode: row.string("siweb_code_key") ?? row.string("siweb_code") ?? "",
            state: state, origin: row.string("origin") ?? "unknown",
            confidence: row.double("confidence") ?? 0, canUndo: row.int("can_undo") == 1
        )
    }
}
