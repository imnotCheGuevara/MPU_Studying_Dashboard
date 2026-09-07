import Foundation

enum Stage10RQAData {
    static let now = date(2026, 9, 7, 10, 15)

    static var snapshot: DashboardSnapshot {
        var value = SyntheticFixtures.populated
        let course = value.courses[0]
        value.meetings += [
            CourseMeeting(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!, courseID: course.id,
                title: "Accessible Interface Research Seminar with a Deliberately Long Source-Owned Title",
                start: date(2026, 9, 7, 9, 30), end: date(2026, 9, 7, 11, 0),
                location: "Synthetic Lab 8", source: .siweb, isCancelled: false,
                sourceURL: "https://example.invalid/course-meeting"
            ),
            CourseMeeting(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!, courseID: course.id,
                title: "Early Studio", start: date(2026, 9, 7, 6, 15), end: date(2026, 9, 7, 8, 0),
                location: "Synthetic Studio", source: .siweb, isCancelled: false
            ),
            CourseMeeting(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000003")!, courseID: course.id,
                title: "Evening Workshop", start: date(2026, 9, 7, 21, 0), end: date(2026, 9, 7, 23, 0),
                location: "Synthetic Hall", source: .siweb, isCancelled: false
            )
        ]
        value.announcements.insert(Announcement(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000004")!, sourceObjectID: "qa-announcement",
            courseID: course.id, title: "Synthetic long announcement title for sidebar interaction and wrapping",
            summary: "Synthetic QA body.", publishedAt: date(2026, 9, 5, 10, 0), source: .canvas,
            isLocallyRead: false, sourceURL: "https://example.invalid/announcement"
        ), at: 0)
        return value
    }

    @MainActor
    static func databaseModel() throws -> DashboardModel {
        let database = try SQLiteDatabase(path: ":memory:")
        let accountID = "71000000-0000-0000-0000-000000000001"
        let courseID = "71000000-0000-0000-0000-000000000002"
        let meetingID = "71000000-0000-0000-0000-000000000003"
        let announcementID = "71000000-0000-0000-0000-000000000004"
        try database.execute(
            "INSERT INTO source_accounts (id,source_kind,instance_url,display_name,authorization_state,last_successful_sync,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)",
            bindings: [.text(accountID), .text("Canvas"), .text("https://example.invalid"), .text("Canvas"),
                       .text("authorized"), .real(now.timeIntervalSince1970), .real(1), .real(1)]
        )
        try database.execute(
            "INSERT INTO courses (id,source_account_id,source_object_id,name,code,term,time_zone,source_url,source_state,first_seen_at,last_seen_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            bindings: [.text(courseID), .text(accountID), .text("qa-course"), .text("Database-backed synthetic course"),
                       .text("QA-101"), .text("QA Term"), .text("Asia/Macau"), .text("https://example.invalid/course"),
                       .text("active"), .real(1), .real(1)]
        )
        try database.execute(
            "INSERT INTO course_meetings (id,course_id,source_object_id,starts_at,ends_at,is_all_day,original_time_zone,location,source_state) VALUES (?,?,?,?,?,?,?,?,?)",
            bindings: [.text(meetingID), .text(courseID), .text("qa-meeting"), .real(date(2026, 9, 7, 9, 0).timeIntervalSince1970),
                       .real(date(2026, 9, 7, 10, 30).timeIntervalSince1970), .integer(0), .text("Asia/Macau"),
                       .text("Synthetic database room"), .text("active")]
        )
        try database.execute(
            "INSERT INTO announcements (id,source_account_id,source_object_id,course_id,title,published_at,summary,content_hash,source_url,source_state,first_seen_at,last_seen_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            bindings: [.text(announcementID), .text(accountID), .text("qa-announcement"), .text(courseID),
                       .text("Database-backed synthetic announcement"), .real(date(2026, 9, 7, 8, 0).timeIntervalSince1970),
                       .text("Synthetic database QA body."), .text("qa-hash"), .text("https://example.invalid/announcement"),
                       .text("active"), .real(1), .real(1)]
        )
        let persistence = SQLitePersistenceRepository(database: database)
        return DashboardModel(
            localStateRepository: SQLiteLocalStateRepository(persistence: persistence),
            dataReader: SQLiteDashboardDataReader(database: database), now: { now },
            timeZone: TimeZone(identifier: "Asia/Macau")!
        )
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        CalendarDateMath.calendar(timeZone: TimeZone(identifier: "Asia/Macau")!)
            .date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
