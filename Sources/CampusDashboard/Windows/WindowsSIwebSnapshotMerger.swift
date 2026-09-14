#if os(Windows)
import Foundation

struct WindowsSIwebSnapshotMerger {
    static let accountID = "siweb.mpu"

    func merge(_ source: SIwebSnapshot, into current: DashboardSnapshot, syncedAt: Date) -> DashboardSnapshot {
        let canvasCourses = current.courses.filter { $0.sourceAccountID != Self.accountID }
        let priorSIwebCourses = Dictionary(
            current.courses.filter { $0.sourceAccountID == Self.accountID }.map { ($0.sourceObjectID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let priorMeetingIDs = Dictionary(
            current.meetings.filter { $0.source == .siweb }.map { (meetingKey($0), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        var courseBySourceID: [String: Course] = [:]
        var newSIwebCourses: [Course] = []
        for payload in source.meetings {
            guard courseBySourceID[payload.courseSourceObjectID] == nil else { continue }
            if let prior = priorSIwebCourses[payload.courseSourceObjectID] {
                let refreshed = Course(
                    id: prior.id,
                    sourceAccountID: Self.accountID,
                    sourceObjectID: payload.courseSourceObjectID,
                    name: payload.courseName,
                    code: payload.courseCode ?? "",
                    term: prior.term,
                    colorName: prior.colorName,
                    sourceURL: payload.sourceURL?.absoluteString
                )
                courseBySourceID[payload.courseSourceObjectID] = refreshed
                newSIwebCourses.append(refreshed)
            } else if let matched = matchingCourse(for: payload, in: canvasCourses) {
                courseBySourceID[payload.courseSourceObjectID] = matched
            } else {
                let course = Course(
                    id: UUID(),
                    sourceAccountID: Self.accountID,
                    sourceObjectID: payload.courseSourceObjectID,
                    name: payload.courseName,
                    code: payload.courseCode ?? "",
                    term: "",
                    colorName: "teal",
                    sourceURL: payload.sourceURL?.absoluteString
                )
                courseBySourceID[payload.courseSourceObjectID] = course
                newSIwebCourses.append(course)
            }
        }

        let meetings = source.meetings.compactMap { payload -> CourseMeeting? in
            guard let course = courseBySourceID[payload.courseSourceObjectID] else { return nil }
            let candidate = CourseMeeting(
                id: UUID(),
                courseID: course.id,
                title: payload.courseName,
                start: payload.startsAt,
                end: payload.endsAt,
                location: payload.location ?? "",
                source: .siweb,
                isCancelled: payload.isCancelled,
                sourceURL: payload.sourceURL?.absoluteString
            )
            return CourseMeeting(
                id: priorMeetingIDs[meetingKey(candidate)] ?? candidate.id,
                courseID: candidate.courseID,
                title: candidate.title,
                start: candidate.start,
                end: candidate.end,
                location: candidate.location,
                source: candidate.source,
                isCancelled: candidate.isCancelled,
                isAllDay: candidate.isAllDay,
                sourceURL: candidate.sourceURL
            )
        }.sorted { $0.start < $1.start }

        var result = current
        result.sourceHealth = current.sourceHealth.filter { $0.source != .siweb } + [
            SourceHealth(
                id: UUID(), source: .siweb, level: .healthy,
                detail: "Read-only sync completed", lastSuccessfulSync: syncedAt
            )
        ]
        result.courses = canvasCourses + newSIwebCourses.sorted { $0.name < $1.name }
        result.meetings = current.meetings.filter { $0.source != .siweb } + meetings
        return result
    }

    func preservingSIweb(from current: DashboardSnapshot, in canvas: DashboardSnapshot) -> DashboardSnapshot {
        let siwebHealth = current.sourceHealth.filter { $0.source == .siweb }
        let oldCourses = Dictionary(uniqueKeysWithValues: current.courses.map { ($0.id, $0) })
        var retainedSIwebCourses: [Course] = []
        var mappedMeetings: [CourseMeeting] = []

        for meeting in current.meetings where meeting.source == .siweb {
            guard let oldCourse = oldCourses[meeting.courseID] else { continue }
            let course = matchingCourse(named: oldCourse.name, code: oldCourse.code, in: canvas.courses)
                ?? oldCourse
            if course.sourceAccountID == Self.accountID,
               !retainedSIwebCourses.contains(where: { $0.id == course.id }) {
                retainedSIwebCourses.append(course)
            }
            mappedMeetings.append(CourseMeeting(
                id: meeting.id, courseID: course.id, title: meeting.title,
                start: meeting.start, end: meeting.end, location: meeting.location,
                source: .siweb, isCancelled: meeting.isCancelled,
                isAllDay: meeting.isAllDay, sourceURL: meeting.sourceURL
            ))
        }

        var result = canvas
        result.sourceHealth = canvas.sourceHealth.filter { $0.source != .siweb } + siwebHealth
        result.courses += retainedSIwebCourses
        result.meetings = mappedMeetings.sorted { $0.start < $1.start }
        return result
    }

    func removingSIweb(from current: DashboardSnapshot) -> DashboardSnapshot {
        var result = current
        result.sourceHealth.removeAll { $0.source == .siweb }
        result.meetings.removeAll { $0.source == .siweb }
        let referencedCourseIDs = Set(
            result.meetings.map(\.courseID)
                + result.tasks.map(\.courseID)
                + result.announcements.map(\.courseID)
                + result.confirmations.map(\.courseID)
        )
        result.courses.removeAll {
            $0.sourceAccountID == Self.accountID && !referencedCourseIDs.contains($0.id)
        }
        return result
    }

    func removingCanvas(from current: DashboardSnapshot) -> DashboardSnapshot {
        var result = current
        result.sourceHealth.removeAll { $0.source == .canvas }
        result.tasks.removeAll { $0.source == .canvas }
        result.announcements.removeAll { $0.source == .canvas }
        let retainedMeetings = result.meetings.filter { $0.source != .canvas }
        let retainedCourseIDs = Set(retainedMeetings.map(\.courseID))
        result.meetings = retainedMeetings
        result.confirmations.removeAll { !retainedCourseIDs.contains($0.courseID) }
        result.courses.removeAll {
            $0.sourceAccountID != Self.accountID && !retainedCourseIDs.contains($0.id)
        }
        return result
    }

    private func matchingCourse(for payload: SIwebMeetingPayload, in courses: [Course]) -> Course? {
        matchingCourse(named: payload.courseName, code: payload.courseCode ?? "", in: courses)
    }

    private func matchingCourse(named name: String, code: String, in courses: [Course]) -> Course? {
        let normalizedCode = normalize(code)
        if !normalizedCode.isEmpty,
           let exactCode = courses.first(where: { normalize($0.code) == normalizedCode }) {
            return exactCode
        }
        let normalizedName = normalize(name)
        return courses.first { normalize($0.name) == normalizedName }
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    private func meetingKey(_ meeting: CourseMeeting) -> String {
        [
            meeting.courseID.uuidString,
            String(Int64(meeting.start.timeIntervalSince1970 * 1_000)),
            String(Int64(meeting.end.timeIntervalSince1970 * 1_000)),
            meeting.location,
            meeting.sourceURL ?? ""
        ].joined(separator: "\u{1f}")
    }
}
#endif
