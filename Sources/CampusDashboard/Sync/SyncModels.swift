import Foundation

enum SyncObjectType: String, CaseIterable, Codable, Sendable {
    case course
    case courseMeeting = "course_meeting"
    case learningTask = "learning_task"
    case announcement
}

enum SyncSourceState: String, Codable, Sendable {
    case active
    case cancelled
}

enum SyncErrorCategory: String, Equatable, Sendable {
    case alreadyRunning = "already_running"
    case cancelled
    case unauthorized
    case forbidden
    case rateLimited = "rate_limited"
    case offline
    case temporaryServer = "temporary_server"
    case sourceChanged = "source_changed"
    case malformedResponse = "malformed_response"
    case persistence
    case unknown
}

struct SyncEngineError: Error, Equatable, Sendable {
    let category: SyncErrorCategory
    let retryable: Bool
}

struct SyncRunRecord: Equatable, Sendable {
    let id: UUID
    let sourceAccountID: UUID
    let trigger: SyncTrigger
    let fetchState: String
    let normalizeState: String
    let persistenceState: String
    let readCount: Int
    let insertedCount: Int
    let updatedCount: Int
    let cancelledCount: Int
    let startedAt: Date
    let finishedAt: Date?
    let errorCategory: SyncErrorCategory?
}

struct ChangeRecordValue: Equatable, Sendable {
    let objectType: SyncObjectType
    let objectID: String
    let fieldName: String
    let oldValue: String?
    let newValue: String?
    let discoveredAt: Date
}

struct SourceSyncOutcome: Sendable {
    let source: SourceKind
    let result: Result<SyncSummary, SyncEngineError>
}

struct SyncSourceAccount: Equatable, Sendable {
    let id: UUID
    let source: SourceKind
    let instanceURL: String
    let displayName: String
}

struct SyncSnapshot: Sendable {
    var rawRecords: [RawSyncRecord]
    var courses: [NormalizedCourse]
    var meetings: [NormalizedMeeting]
    var tasks: [NormalizedTask]
    var announcements: [NormalizedAnnouncement]
    var completeObjectTypes: Set<SyncObjectType>

    init(
        rawRecords: [RawSyncRecord] = [],
        courses: [NormalizedCourse],
        meetings: [NormalizedMeeting],
        tasks: [NormalizedTask],
        announcements: [NormalizedAnnouncement],
        completeObjectTypes: Set<SyncObjectType>
    ) {
        self.rawRecords = rawRecords
        self.courses = courses
        self.meetings = meetings
        self.tasks = tasks
        self.announcements = announcements
        self.completeObjectTypes = completeObjectTypes
    }

    var readCount: Int {
        courses.count + meetings.count + tasks.count + announcements.count
    }
}

struct NormalizedCourse: Equatable, Encodable, Sendable {
    let sourceObjectID: String
    let name: String
    let code: String
    let term: String
    let timeZone: String
    let sourceURL: String?
}

struct NormalizedMeeting: Equatable, Encodable, Sendable {
    let sourceObjectID: String
    let courseSourceObjectID: String
    let startsAt: Date
    let endsAt: Date
    let timeZone: String
    let location: String
    let sourceURL: String?
    let sourceState: SyncSourceState
    let parserVersion: String
    let contentHash: String
}

struct NormalizedTask: Equatable, Encodable, Sendable {
    let sourceObjectID: String
    let courseSourceObjectID: String
    let title: String
    let officialType: String
    let normalizedType: String
    let officialDueAt: Date?
    let opensAt: Date?
    let locksAt: Date?
    let sourceURL: String?
}

struct NormalizedAnnouncement: Equatable, Encodable, Sendable {
    let sourceObjectID: String
    let courseSourceObjectID: String
    let title: String
    let publishedAt: Date?
    let updatedAt: Date?
    let summary: String
    let contentHash: String
    let sourceURL: String?
}

struct RawSyncRecord: Codable, Sendable {
    let objectType: SyncObjectType
    let sourceObjectID: String
    let fields: [String: String?]
}

enum OutboxEnvelope: Codable, Equatable, Sendable {
    case calendarUpsert(objectType: String, objectID: String)
    case calendarRemove(objectType: String, objectID: String)
    case calendarReconcile(objectType: String, objectID: String)
    case notificationNew(key: String, objectID: String, at: Date)
    case notificationCancel(key: String)
}

extension OutboxEnvelope {
    private enum CodingKeys: String, CodingKey { case operation, objectType, objectID, key, at }
    private enum Operation: String, Codable {
        case calendarUpsert, calendarRemove, calendarReconcile, notificationNew, notificationCancel
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Operation.self, forKey: .operation) {
        case .calendarUpsert:
            self = .calendarUpsert(
                objectType: try values.decode(String.self, forKey: .objectType),
                objectID: try values.decode(String.self, forKey: .objectID)
            )
        case .calendarRemove:
            self = .calendarRemove(
                objectType: try values.decode(String.self, forKey: .objectType),
                objectID: try values.decode(String.self, forKey: .objectID)
            )
        case .calendarReconcile:
            self = .calendarReconcile(
                objectType: try values.decode(String.self, forKey: .objectType),
                objectID: try values.decode(String.self, forKey: .objectID)
            )
        case .notificationNew:
            self = .notificationNew(
                key: try values.decode(String.self, forKey: .key),
                objectID: try values.decode(String.self, forKey: .objectID),
                at: try values.decode(Date.self, forKey: .at)
            )
        case .notificationCancel:
            self = .notificationCancel(key: try values.decode(String.self, forKey: .key))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .calendarUpsert(let objectType, let objectID):
            try values.encode(Operation.calendarUpsert, forKey: .operation)
            try values.encode(objectType, forKey: .objectType)
            try values.encode(objectID, forKey: .objectID)
        case .calendarRemove(let objectType, let objectID):
            try values.encode(Operation.calendarRemove, forKey: .operation)
            try values.encode(objectType, forKey: .objectType)
            try values.encode(objectID, forKey: .objectID)
        case .calendarReconcile(let objectType, let objectID):
            try values.encode(Operation.calendarReconcile, forKey: .operation)
            try values.encode(objectType, forKey: .objectType)
            try values.encode(objectID, forKey: .objectID)
        case .notificationNew(let key, let objectID, let at):
            try values.encode(Operation.notificationNew, forKey: .operation)
            try values.encode(key, forKey: .key)
            try values.encode(objectID, forKey: .objectID)
            try values.encode(at, forKey: .at)
        case .notificationCancel(let key):
            try values.encode(Operation.notificationCancel, forKey: .operation)
            try values.encode(key, forKey: .key)
        }
    }
}
