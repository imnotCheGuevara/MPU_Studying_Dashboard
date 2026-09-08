import Foundation

struct FetchPage<Value: Sendable>: Sendable {
    let values: [Value]
    let nextPageToken: String?
    let isCompleteSnapshot: Bool
}

struct CanvasCoursePayload: Equatable, Sendable {
    let sourceObjectID: String
    let name: String
    let code: String
    let term: String
    let timeZone: String?
    let sourceURL: URL?

    init(
        sourceObjectID: String,
        name: String,
        code: String,
        term: String = "",
        timeZone: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.sourceObjectID = sourceObjectID
        self.name = name
        self.code = code
        self.term = term
        self.timeZone = timeZone
        self.sourceURL = sourceURL
    }
}

struct CanvasTaskPayload: Equatable, Sendable {
    let sourceObjectID: String
    let courseSourceObjectID: String
    let title: String
    let officialType: String
    let officialDueAt: Date?
    let unlockAt: Date?
    let lockAt: Date?
    let sourceURL: URL?
    /// Canvas reports that the assignment has at least one override. This does
    /// not prove the requesting user's effective date came from an override.
    let hasAssignmentOverrides: Bool
    let placeholderEvidence: TaskPlaceholderEvidence

    init(
        sourceObjectID: String,
        courseSourceObjectID: String,
        title: String,
        officialType: String,
        officialDueAt: Date?,
        unlockAt: Date? = nil,
        lockAt: Date? = nil,
        sourceURL: URL? = nil,
        hasAssignmentOverrides: Bool = false,
        placeholderEvidence: TaskPlaceholderEvidence = .incomplete
    ) {
        self.sourceObjectID = sourceObjectID
        self.courseSourceObjectID = courseSourceObjectID
        self.title = title
        self.officialType = officialType
        self.officialDueAt = officialDueAt
        self.unlockAt = unlockAt
        self.lockAt = lockAt
        self.sourceURL = sourceURL
        self.hasAssignmentOverrides = hasAssignmentOverrides
        self.placeholderEvidence = placeholderEvidence
    }
}

struct TaskPlaceholderEvidence: Equatable, Codable, Sendable {
    let isComplete: Bool
    let hasMeaningfulDescription: Bool
    let hasAttachment: Bool
    let hasLinkedActivity: Bool
    let hasMeaningfulSubmission: Bool
    let hasActionableRequirement: Bool

    static let incomplete = Self(
        isComplete: false, hasMeaningfulDescription: false, hasAttachment: false,
        hasLinkedActivity: false, hasMeaningfulSubmission: false, hasActionableRequirement: false
    )

    func classifiesAsPlaceholder(dueAt: Date?) -> Bool {
        isComplete && dueAt == nil && !hasMeaningfulDescription && !hasAttachment
            && !hasLinkedActivity && !hasMeaningfulSubmission && !hasActionableRequirement
    }
}

struct CanvasAnnouncementPayload: Equatable, Sendable {
    let sourceObjectID: String
    let courseSourceObjectID: String
    let title: String
    let publishedAt: Date?
    let updatedAt: Date?
    let summary: String
    let sourceURL: URL?

    init(
        sourceObjectID: String,
        courseSourceObjectID: String,
        title: String,
        publishedAt: Date?,
        updatedAt: Date? = nil,
        summary: String,
        sourceURL: URL? = nil
    ) {
        self.sourceObjectID = sourceObjectID
        self.courseSourceObjectID = courseSourceObjectID
        self.title = title
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.summary = summary
        self.sourceURL = sourceURL
    }
}

struct SIwebMeetingPayload: Equatable, Sendable {
    let sourceObjectID: String
    let courseSourceObjectID: String
    let courseName: String
    let courseCode: String?
    let startsAt: Date
    let endsAt: Date
    let timeZoneIdentifier: String
    let location: String?
    let isCancelled: Bool
    let sourceURL: URL?
    let parserVersion: String
    let sourceContentHash: String

    init(
        sourceObjectID: String,
        courseSourceObjectID: String,
        courseName: String,
        courseCode: String? = nil,
        startsAt: Date,
        endsAt: Date,
        timeZoneIdentifier: String,
        location: String? = nil,
        isCancelled: Bool,
        sourceURL: URL? = nil,
        parserVersion: String,
        sourceContentHash: String = ""
    ) {
        self.sourceObjectID = sourceObjectID
        self.courseSourceObjectID = courseSourceObjectID
        self.courseName = courseName
        self.courseCode = courseCode
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.location = location
        self.isCancelled = isCancelled
        self.sourceURL = sourceURL
        self.parserVersion = parserVersion
        self.sourceContentHash = sourceContentHash
    }
}

protocol CanvasService: Sendable {
    func courses(pageToken: String?) async throws -> FetchPage<CanvasCoursePayload>
    func learningTasks(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasTaskPayload>
    func announcements(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasAnnouncementPayload>
}

protocol SIwebService: Sendable {
    func meetings(pageToken: String?) async throws -> FetchPage<SIwebMeetingPayload>
}

enum SyncTrigger: String, Sendable { case manual, scheduled, recovery }

struct SyncSummary: Equatable, Sendable {
    let source: SourceKind
    let readCount: Int
    let insertedCount: Int
    let updatedCount: Int
    let cancelledCount: Int
}

protocol SyncService: Sendable {
    func synchronize(source: SourceKind, trigger: SyncTrigger) async throws -> SyncSummary
}

enum CalendarCommand: Equatable, Sendable {
    case upsert(objectType: String, objectID: String)
    case removeBoundEvent(objectType: String, objectID: String)
}

struct CalendarCommandResult: Equatable, Sendable {
    let objectID: String
    let bindingIdentifier: String?
}

protocol CalendarService: Sendable {
    func apply(_ commands: [CalendarCommand]) async throws -> [CalendarCommandResult]
}

enum NotificationCommand: Equatable, Sendable {
    case schedule(key: String, objectID: String, at: Date)
    case cancel(key: String)
}

protocol NotificationService: Sendable {
    func apply(_ commands: [NotificationCommand]) async throws
}

struct AIRequest: Equatable, Sendable {
    let title: String
    let officialType: String
    let officialDueAt: Date?
    let minimalText: String
}

struct AISuggestion: Equatable, Sendable {
    let normalizedTitle: String?
    let suggestedType: String?
    let suggestedCompleteAt: Date?
    let confidence: Double
    let rationale: String
}

protocol AIService: Sendable {
    func suggest(for request: AIRequest) async throws -> AISuggestion
}

protocol Clock: Sendable { var now: Date { get } }
protocol IDGenerator: Sendable { func next() -> UUID }

struct SystemClock: Clock { var now: Date { Date() } }
struct SystemIDGenerator: IDGenerator { func next() -> UUID { UUID() } }

struct FixedClock: Clock {
    let now: Date
}

final class SequenceIDGenerator: IDGenerator, @unchecked Sendable {
    private var values: [UUID]
    private let lock = NSLock()

    init(values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.withLock {
            precondition(!values.isEmpty, "SequenceIDGenerator exhausted")
            return values.removeFirst()
        }
    }
}

actor FakeCanvasService: CanvasService {
    var coursePage: FetchPage<CanvasCoursePayload>
    var taskPages: [String: FetchPage<CanvasTaskPayload>]
    var announcementPages: [String: FetchPage<CanvasAnnouncementPayload>]

    init(
        coursePage: FetchPage<CanvasCoursePayload> = .init(values: [], nextPageToken: nil, isCompleteSnapshot: true),
        taskPages: [String: FetchPage<CanvasTaskPayload>] = [:],
        announcementPages: [String: FetchPage<CanvasAnnouncementPayload>] = [:]
    ) {
        self.coursePage = coursePage
        self.taskPages = taskPages
        self.announcementPages = announcementPages
    }

    func courses(pageToken: String?) async throws -> FetchPage<CanvasCoursePayload> { coursePage }
    func learningTasks(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasTaskPayload> {
        taskPages[courseID] ?? .init(values: [], nextPageToken: nil, isCompleteSnapshot: true)
    }
    func announcements(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasAnnouncementPayload> {
        announcementPages[courseID] ?? .init(values: [], nextPageToken: nil, isCompleteSnapshot: true)
    }
}

actor FakeSIwebService: SIwebService {
    var page: FetchPage<SIwebMeetingPayload>

    init(page: FetchPage<SIwebMeetingPayload> = .init(values: [], nextPageToken: nil, isCompleteSnapshot: true)) {
        self.page = page
    }

    func meetings(pageToken: String?) async throws -> FetchPage<SIwebMeetingPayload> { page }
}

actor FakeSyncService: SyncService {
    var summaries: [SourceKind: SyncSummary]

    init(summaries: [SourceKind: SyncSummary] = [:]) { self.summaries = summaries }

    func synchronize(source: SourceKind, trigger: SyncTrigger) async throws -> SyncSummary {
        summaries[source] ?? SyncSummary(
            source: source, readCount: 0, insertedCount: 0, updatedCount: 0, cancelledCount: 0
        )
    }
}

actor FakeCalendarService: CalendarService {
    private(set) var received: [[CalendarCommand]] = []
    func apply(_ commands: [CalendarCommand]) async throws -> [CalendarCommandResult] {
        received.append(commands)
        return commands.map { command in
            switch command {
            case .upsert(_, let objectID), .removeBoundEvent(_, let objectID):
                CalendarCommandResult(objectID: objectID, bindingIdentifier: nil)
            }
        }
    }
}

actor FakeNotificationService: NotificationService {
    private(set) var received: [[NotificationCommand]] = []
    func apply(_ commands: [NotificationCommand]) async throws { received.append(commands) }
}

actor FakeAIService: AIService {
    let result: AISuggestion

    init(result: AISuggestion = .init(
        normalizedTitle: nil, suggestedType: nil, suggestedCompleteAt: nil,
        confidence: 0, rationale: "Synthetic no-op suggestion"
    )) {
        self.result = result
    }

    func suggest(for request: AIRequest) async throws -> AISuggestion { result }
}
