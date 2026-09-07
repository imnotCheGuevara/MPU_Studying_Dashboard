import Foundation

protocol SyncSourceReader: Sendable {
    var source: SourceKind { get }
    func read() async throws -> SyncSnapshot
}

struct CanvasSyncSourceReader: SyncSourceReader {
    let source: SourceKind = .canvas
    let service: any CanvasService
    let maximumPages: Int

    init(service: any CanvasService, maximumPages: Int = 1_000) {
        self.service = service
        self.maximumPages = max(1, maximumPages)
    }

    func read() async throws -> SyncSnapshot {
        let courseResult = try await collect { try await service.courses(pageToken: $0) }
        var taskValues: [CanvasTaskPayload] = []
        var announcementValues: [CanvasAnnouncementPayload] = []
        var tasksComplete = courseResult.isComplete
        var announcementsComplete = courseResult.isComplete

        for course in courseResult.values {
            try Task.checkCancellation()
            let tasks = try await collect {
                try await service.learningTasks(courseID: course.sourceObjectID, pageToken: $0)
            }
            taskValues.append(contentsOf: tasks.values)
            tasksComplete = tasksComplete && tasks.isComplete

            let announcements = try await collect {
                try await service.announcements(courseID: course.sourceObjectID, pageToken: $0)
            }
            announcementValues.append(contentsOf: announcements.values)
            announcementsComplete = announcementsComplete && announcements.isComplete
        }

        let courses = try stableUnique(courseResult.values, id: \CanvasCoursePayload.sourceObjectID).map {
            NormalizedCourse(
                sourceObjectID: $0.sourceObjectID, name: $0.name, code: $0.code,
                term: $0.term, timeZone: $0.timeZone ?? "UTC", sourceURL: $0.sourceURL?.absoluteString
            )
        }
        let tasks = try stableUnique(taskValues, id: \CanvasTaskPayload.sourceObjectID).map {
            NormalizedTask(
                sourceObjectID: $0.sourceObjectID, courseSourceObjectID: $0.courseSourceObjectID,
                title: $0.title, officialType: $0.officialType,
                normalizedType: deterministicTaskType($0.officialType), officialDueAt: $0.officialDueAt,
                opensAt: $0.unlockAt, locksAt: $0.lockAt, sourceURL: $0.sourceURL?.absoluteString
            )
        }
        let announcements = try stableUnique(
            announcementValues, id: \CanvasAnnouncementPayload.sourceObjectID
        ).map {
            NormalizedAnnouncement(
                sourceObjectID: $0.sourceObjectID, courseSourceObjectID: $0.courseSourceObjectID,
                title: $0.title, publishedAt: $0.publishedAt, updatedAt: $0.updatedAt,
                summary: $0.summary, contentHash: StableDigest.hash($0.summary),
                sourceURL: $0.sourceURL?.absoluteString
            )
        }
        var complete: Set<SyncObjectType> = []
        if courseResult.isComplete { complete.insert(.course) }
        if tasksComplete { complete.insert(.learningTask) }
        if announcementsComplete { complete.insert(.announcement) }
        let rawCourses = courseResult.values.map { value in
            RawSyncRecord(objectType: .course, sourceObjectID: value.sourceObjectID, fields: [
                "name": value.name, "code": value.code, "term": value.term,
                "timeZone": value.timeZone, "sourceURL": value.sourceURL?.absoluteString
            ])
        }
        let rawTasks = taskValues.map { value in
            RawSyncRecord(objectType: .learningTask, sourceObjectID: value.sourceObjectID, fields: [
                "courseSourceObjectID": value.courseSourceObjectID, "title": value.title,
                "officialType": value.officialType, "officialDueAt": rawDate(value.officialDueAt),
                "unlockAt": rawDate(value.unlockAt), "lockAt": rawDate(value.lockAt),
                "sourceURL": value.sourceURL?.absoluteString,
                "hasAssignmentOverrides": String(value.hasAssignmentOverrides)
            ])
        }
        let rawAnnouncements = announcementValues.map { value in
            RawSyncRecord(objectType: .announcement, sourceObjectID: value.sourceObjectID, fields: [
                "courseSourceObjectID": value.courseSourceObjectID, "title": value.title,
                "publishedAt": rawDate(value.publishedAt), "updatedAt": rawDate(value.updatedAt),
                "summary": value.summary, "sourceURL": value.sourceURL?.absoluteString
            ])
        }
        return SyncSnapshot(
            rawRecords: rawCourses + rawTasks + rawAnnouncements,
            courses: courses, meetings: [], tasks: tasks, announcements: announcements,
            completeObjectTypes: complete
        )
    }

    private func deterministicTaskType(_ officialType: String) -> String {
        switch officialType.lowercased() {
        case let value where value.contains("quiz"): "quiz"
        case let value where value.contains("discussion"): "discussion"
        case let value where value.contains("external"): "external_tool"
        default: "assignment"
        }
    }

    private func collect<Value: Equatable & Sendable>(
        _ fetch: (String?) async throws -> FetchPage<Value>
    ) async throws -> (values: [Value], isComplete: Bool) {
        var values: [Value] = []
        var token: String?
        var seenTokens: Set<String> = []
        var pages = 0
        var finalComplete = false
        repeat {
            try Task.checkCancellation()
            pages += 1
            guard pages <= maximumPages else { throw SyncEngineError(category: .malformedResponse, retryable: false) }
            let page = try await fetch(token)
            values.append(contentsOf: page.values)
            token = page.nextPageToken
            if let token, !seenTokens.insert(token).inserted {
                throw SyncEngineError(category: .malformedResponse, retryable: false)
            }
            if token == nil { finalComplete = page.isCompleteSnapshot }
        } while token != nil
        return (values, finalComplete)
    }
}

struct SIwebSyncSourceReader: SyncSourceReader {
    let source: SourceKind = .siweb
    let service: any SIwebService
    let maximumPages: Int

    init(service: any SIwebService, maximumPages: Int = 100) {
        self.service = service
        self.maximumPages = max(1, maximumPages)
    }

    func read() async throws -> SyncSnapshot {
        var values: [SIwebMeetingPayload] = []
        var token: String?
        var seenTokens: Set<String> = []
        var pages = 0
        var isComplete = false
        repeat {
            try Task.checkCancellation()
            pages += 1
            guard pages <= maximumPages else { throw SyncEngineError(category: .malformedResponse, retryable: false) }
            let page = try await service.meetings(pageToken: token)
            values.append(contentsOf: page.values)
            token = page.nextPageToken
            if let token, !seenTokens.insert(token).inserted {
                throw SyncEngineError(category: .malformedResponse, retryable: false)
            }
            if token == nil { isComplete = page.isCompleteSnapshot }
        } while token != nil

        let unique = try stableUnique(values, id: \SIwebMeetingPayload.sourceObjectID)
        var courseByID: [String: NormalizedCourse] = [:]
        for meeting in unique {
            let course = NormalizedCourse(
                sourceObjectID: meeting.courseSourceObjectID, name: meeting.courseName,
                code: meeting.courseCode ?? "", term: "", timeZone: meeting.timeZoneIdentifier,
                sourceURL: meeting.sourceURL?.absoluteString
            )
            if let existing = courseByID[course.sourceObjectID], existing != course {
                throw SyncEngineError(category: .sourceChanged, retryable: false)
            }
            courseByID[course.sourceObjectID] = course
        }
        let meetings = unique.map {
            NormalizedMeeting(
                sourceObjectID: $0.sourceObjectID, courseSourceObjectID: $0.courseSourceObjectID,
                startsAt: $0.startsAt, endsAt: $0.endsAt, timeZone: $0.timeZoneIdentifier,
                location: $0.location ?? "", sourceURL: $0.sourceURL?.absoluteString,
                sourceState: $0.isCancelled ? .cancelled : .active,
                parserVersion: $0.parserVersion, contentHash: $0.sourceContentHash
            )
        }
        let complete: Set<SyncObjectType> = isComplete ? [.course, .courseMeeting] : []
        let rawRecords = unique.map { value in
            RawSyncRecord(objectType: .courseMeeting, sourceObjectID: value.sourceObjectID, fields: [
                "courseSourceObjectID": value.courseSourceObjectID, "courseName": value.courseName,
                "courseCode": value.courseCode, "startsAt": rawDate(value.startsAt),
                "endsAt": rawDate(value.endsAt), "timeZone": value.timeZoneIdentifier,
                "location": value.location, "isCancelled": String(value.isCancelled),
                "sourceURL": value.sourceURL?.absoluteString, "parserVersion": value.parserVersion,
                "sourceContentHash": value.sourceContentHash
            ])
        }
        return SyncSnapshot(
            rawRecords: rawRecords,
            courses: courseByID.values.sorted { $0.sourceObjectID < $1.sourceObjectID },
            meetings: meetings, tasks: [], announcements: [], completeObjectTypes: complete
        )
    }
}

private func rawDate(_ value: Date?) -> String? {
    value.map { String(format: "%.6f", $0.timeIntervalSince1970) }
}

private func stableUnique<Value: Equatable>(
    _ values: [Value], id: KeyPath<Value, String>
) throws -> [Value] {
    var byID: [String: Value] = [:]
    for value in values {
        let key = value[keyPath: id]
        if let existing = byID[key], existing != value {
            throw SyncEngineError(category: .malformedResponse, retryable: false)
        }
        byID[key] = value
    }
    return byID.values.sorted { $0[keyPath: id] < $1[keyPath: id] }
}

enum StableDigest {
    static func hash(_ value: String) -> String {
        // Stable FNV-1a is sufficient for local change/deduplication identity; it is not used for secrets.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
