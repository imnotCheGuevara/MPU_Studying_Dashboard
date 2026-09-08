import Foundation

/// The only path from announcement text to a SIweb meeting identity. Provider
/// values are proposals: every field is rechecked against local, read-only data.
enum AcademicScheduleTargetResolver {
    private static let timedTolerance: TimeInterval = 5 * 60

    static func resolve(
        signal: AcademicSignalSuggestion, input: AcademicSignalInput
    ) -> UUID? {
        guard signal.category == .courseScheduleChange,
              signal.scheduleDateRole == .affectedMeeting,
              signal.conflicts.isEmpty,
              let date = signal.inferredDate,
              let proposedID = signal.proposedTargetMeetingID,
              sectionsMatch(signal.affectedSection, input.localSection),
              let candidate = input.meetingCandidates.first(where: { $0.meetingID == proposedID }),
              sectionsMatch(signal.affectedSection, candidate.section),
              let candidateBase = CourseIdentityNormalizer.baseCode(
                CourseIdentityNormalizer.normalizedFullCode(candidate.courseCode)
              ),
              let inputCode = input.courseCode,
              let inputBase = CourseIdentityNormalizer.baseCode(
                CourseIdentityNormalizer.normalizedFullCode(inputCode)
              ),
              candidateBase == inputBase,
              dateMatches(date, isAllDay: signal.isAllDay, candidate: candidate)
        else { return nil }
        return proposedID
    }

    /// Resolves a user-authored repair from the selected course and date. The
    /// caller must persist the returned meeting's section and ID as the new
    /// proposal before presenting a confirmation preview.
    static func resolveCorrection(
        database: SQLiteDatabase, courseID: UUID?, date: Date?, isAllDay: Bool,
        expectedTarget: UUID? = nil
    ) throws -> UUID? {
        try uniqueMeeting(
            database: database, courseID: courseID, date: date,
            isAllDay: isAllDay, expectedTarget: expectedTarget
        )?.meetingID
    }

    /// Revalidates every persisted targeting claim. A matching date by itself
    /// is never sufficient: role, section, proposed ID, resolved ID, and the
    /// current SIweb meeting must all still agree.
    static func revalidate(
        database: SQLiteDatabase, courseID: UUID?, date: Date?, isAllDay: Bool,
        dateRole: AcademicScheduleDateRole?, affectedSection: String?,
        proposedTarget: UUID?, expectedTarget: UUID?
    ) throws -> UUID? {
        guard dateRole == .affectedMeeting,
              let affectedSection,
              let proposedTarget,
              let expectedTarget,
              proposedTarget == expectedTarget,
              let meeting = try uniqueMeeting(
                database: database, courseID: courseID, date: date,
                isAllDay: isAllDay, expectedTarget: expectedTarget
              ),
              sectionsMatch(affectedSection, meeting.section)
        else { return nil }
        return meeting.meetingID
    }

    private static func uniqueMeeting(
        database: SQLiteDatabase, courseID: UUID?, date: Date?, isAllDay: Bool,
        expectedTarget: UUID?
    ) throws -> AcademicMeetingCandidate? {
        guard let courseID, let date else { return nil }
        let course = try database.query(
            "SELECT c.id,c.code,sa.source_kind FROM courses c JOIN source_accounts sa ON sa.id=c.source_account_id WHERE c.id=? AND c.source_state='active'",
            bindings: [.text(courseID.uuidString)]
        ).first
        guard let course else { return nil }

        let siwebIDs: [String]
        if course.string("source_kind")?.lowercased() == "siweb" {
            siwebIDs = [courseID.uuidString]
        } else {
            siwebIDs = try database.query(
                "SELECT siweb_course_id FROM academic_course_mappings WHERE canvas_course_id=? AND is_active=1 AND decision_state='confirmed'",
                bindings: [.text(courseID.uuidString)]
            ).compactMap { $0.string("siweb_course_id") }
        }
        guard siwebIDs.count == 1 else { return nil }
        let rows = try database.query(
            """
            SELECT m.id,m.starts_at,m.ends_at,m.original_time_zone,c.code AS course_code
            FROM course_meetings m JOIN courses c ON c.id=m.course_id
            WHERE m.course_id=? AND m.source_state='active'
            """, bindings: [.text(siwebIDs[0])]
        )
        let candidates = rows.compactMap { row -> AcademicMeetingCandidate? in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let start = row.double("starts_at").map(Date.init(timeIntervalSince1970:)),
                  let end = row.double("ends_at").map(Date.init(timeIntervalSince1970:)) else { return nil }
            let code = row.string("course_code") ?? ""
            return AcademicMeetingCandidate(
                meetingID: id, courseCode: code,
                section: CourseIdentityNormalizer.sectionIdentifier(code),
                startsAt: start, endsAt: end,
                timeZoneIdentifier: row.string("original_time_zone") ?? "Asia/Macau",
                location: ""
            )
        }
        let matches = candidates.filter { dateMatches(date, isAllDay: isAllDay, candidate: $0) }
        guard matches.count == 1 else { return nil }
        if let expectedTarget, matches[0].meetingID != expectedTarget { return nil }
        return matches[0]
    }

    static func dateMatches(
        _ date: Date, isAllDay: Bool, candidate: AcademicMeetingCandidate
    ) -> Bool {
        if isAllDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: candidate.timeZoneIdentifier) ?? .gmt
            return calendar.isDate(date, inSameDayAs: candidate.startsAt)
        }
        return abs(candidate.startsAt.timeIntervalSince(date)) <= timedTolerance
    }

    private static func sectionsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = CourseIdentityNormalizer.sectionIdentifier(lhs),
              let rhs = CourseIdentityNormalizer.sectionIdentifier(rhs) else { return false }
        return lhs == rhs
    }
}
