import Foundation

protocol DashboardDataReading: Sendable {
    func loadSnapshot() throws -> DashboardSnapshot
}

final class SQLiteDashboardDataReader: DashboardDataReading, @unchecked Sendable {
    private let database: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.database = database
    }

    func loadSnapshot() throws -> DashboardSnapshot {
        let courses = try loadCourses()
        let coursesByID = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
        return DashboardSnapshot(
            sourceHealth: try loadSourceHealth(),
            courses: courses,
            meetings: try loadMeetings(courses: coursesByID),
            tasks: try loadTasks(courses: coursesByID),
            announcements: try loadAnnouncements(courses: coursesByID),
            confirmations: []
        )
    }

    private func loadSourceHealth() throws -> [SourceHealth] {
        try database.query(
            """
            SELECT sa.id, sa.source_kind, sa.authorization_state, sa.last_successful_sync,
              (SELECT sr.error_category FROM sync_runs sr
               WHERE sr.source_account_id=sa.id ORDER BY sr.started_at DESC LIMIT 1) AS latest_error
            FROM source_accounts sa
            WHERE sa.source_kind IN ('Canvas', 'SIweb')
            ORDER BY sa.source_kind
            """
        ).compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let sourceValue = row.string("source_kind"),
                  let source = SourceKind(rawValue: sourceValue) else { return nil }
            let error = row.string("latest_error")
            let authorized = row.string("authorization_state") == "authorized"
            let level: HealthLevel = error == nil && authorized ? .healthy : .warning
            return SourceHealth(
                id: id, source: source, level: level,
                detail: healthDetail(error: error, authorized: authorized),
                lastSuccessfulSync: row.double("last_successful_sync").map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    private func loadCourses() throws -> [Course] {
        try database.query(
            """
            SELECT c.id, c.source_account_id, c.source_object_id, c.name, c.code, c.term, c.source_url,
                   sa.source_kind
            FROM courses c JOIN source_accounts sa ON sa.id=c.source_account_id
            WHERE sa.source_kind IN ('Canvas', 'SIweb') AND c.source_state='active'
            ORDER BY c.name, c.id
            """
        ).compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let accountID = row.string("source_account_id"),
                  let sourceID = row.string("source_object_id"),
                  row.string("source_kind").flatMap(SourceKind.init(rawValue:)) != nil else { return nil }
            return Course(
                id: id, sourceAccountID: accountID, sourceObjectID: sourceID,
                name: row.string("name") ?? "Untitled course", code: row.string("code") ?? "",
                term: row.string("term") ?? "", colorName: colorName(for: accountID + ":" + sourceID),
                sourceURL: row.string("source_url")
            )
        }
    }

    private func loadMeetings(courses: [UUID: Course]) throws -> [CourseMeeting] {
        try database.query(
            """
            SELECT m.id, m.course_id, m.starts_at, m.ends_at, m.location, m.source_state, m.is_all_day,
                   sa.source_kind
            FROM course_meetings m
            JOIN courses c ON c.id=m.course_id
            JOIN source_accounts sa ON sa.id=c.source_account_id
            WHERE sa.source_kind IN ('Canvas', 'SIweb')
            ORDER BY m.starts_at, m.id
            """
        ).compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let courseID = row.string("course_id").flatMap(UUID.init(uuidString:)),
                  let course = courses[courseID],
                  let start = row.double("starts_at").map(Date.init(timeIntervalSince1970:)),
                  let end = row.double("ends_at").map(Date.init(timeIntervalSince1970:)),
                  let source = row.string("source_kind").flatMap(SourceKind.init(rawValue:)) else { return nil }
            let title = course.code.isEmpty ? course.name : "\(course.code) · \(course.name)"
            return CourseMeeting(
                id: id, courseID: courseID, title: title, start: start, end: end,
                location: row.string("location") ?? "", source: source,
                isCancelled: row.string("source_state") == "cancelled",
                isAllDay: row.int("is_all_day") == 1, sourceURL: course.sourceURL
            )
        }
    }

    private func loadTasks(courses: [UUID: Course]) throws -> [LearningTask] {
        try database.query(
            """
            SELECT t.id, t.source_account_id, t.source_object_id, t.course_id, t.title,
                   t.official_type, t.normalized_type, t.official_due_at,
                   t.suggested_complete_at, t.suggestion_confirmed_at, t.official_due_is_all_day,
                   t.source_url, sa.source_kind,
                   lus.is_complete, lus.priority
            FROM learning_tasks t
            JOIN source_accounts sa ON sa.id=t.source_account_id
            LEFT JOIN local_user_states lus
              ON lus.object_type='learning_task' AND lus.object_id=t.id
            WHERE sa.source_kind IN ('Canvas', 'SIweb') AND t.source_state='active'
            ORDER BY COALESCE(t.official_due_at, 253402300799), t.id
            """
        ).compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let accountID = row.string("source_account_id"),
                  let sourceID = row.string("source_object_id"),
                  let courseID = row.string("course_id").flatMap(UUID.init(uuidString:)),
                  courses[courseID] != nil,
                  let source = row.string("source_kind").flatMap(SourceKind.init(rawValue:)) else { return nil }
            return LearningTask(
                id: id, sourceAccountID: accountID, sourceObjectID: sourceID,
                courseID: courseID, title: row.string("title") ?? "Untitled task",
                kind: taskKind(row.string("normalized_type") ?? row.string("official_type") ?? ""),
                officialDueAt: row.double("official_due_at").map(Date.init(timeIntervalSince1970:)),
                suggestedCompleteAt: row.double("suggested_complete_at").map(Date.init(timeIntervalSince1970:)),
                suggestedDateConfirmed: row.double("suggestion_confirmed_at") != nil,
                source: source, isLocallyComplete: row.int("is_complete") == 1,
                localPriority: row.string("priority").flatMap(TaskPriority.init(rawValue:)) ?? .medium,
                officialDueIsAllDay: row.int("official_due_is_all_day") == 1,
                sourceURL: row.string("source_url")
            )
        }
    }

    private func loadAnnouncements(courses: [UUID: Course]) throws -> [Announcement] {
        try database.query(
            """
            SELECT a.id, a.source_object_id, a.course_id, a.title, a.summary,
                   a.published_at, a.source_url, sa.source_kind, lus.is_read
            FROM announcements a
            JOIN source_accounts sa ON sa.id=a.source_account_id
            LEFT JOIN local_user_states lus
              ON lus.object_type='announcement' AND lus.object_id=a.id
            WHERE sa.source_kind IN ('Canvas', 'SIweb') AND a.source_state='active'
            ORDER BY a.published_at DESC, a.id
            """
        ).compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let sourceID = row.string("source_object_id"),
                  let courseID = row.string("course_id").flatMap(UUID.init(uuidString:)),
                  courses[courseID] != nil,
                  let published = row.double("published_at").map(Date.init(timeIntervalSince1970:)),
                  let source = row.string("source_kind").flatMap(SourceKind.init(rawValue:)) else { return nil }
            return Announcement(
                id: id, sourceObjectID: sourceID, courseID: courseID,
                title: row.string("title") ?? "Untitled announcement",
                summary: row.string("summary") ?? "", publishedAt: published,
                source: source, isLocallyRead: row.int("is_read") == 1,
                sourceURL: row.string("source_url")
            )
        }
    }

    private func taskKind(_ value: String) -> TaskKind {
        let normalized = value.lowercased()
        if normalized.contains("quiz") { return .quiz }
        if normalized.contains("read") { return .reading }
        return .assignment
    }

    private func colorName(for value: String) -> String {
        let palette = ["indigo", "green", "orange", "blue", "purple", "teal"]
        let hash = value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    private func healthDetail(error: String?, authorized: Bool) -> String {
        if !authorized { return "Authorization needs attention." }
        switch error {
        case nil: return "Ready."
        case "unauthorized": return "Authorization needs attention."
        case "forbidden": return "The source denied this read."
        case "offline": return "The last attempt was offline."
        case "rate_limited": return "The source requested a retry delay."
        case "source_changed", "malformed_response": return "The source contract needs attention."
        default: return "The last synchronization needs attention."
        }
    }
}
