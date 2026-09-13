import Foundation

enum SourceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case canvas = "Canvas"
    case siweb = "SIweb"

    var id: Self { self }

    init?(databaseValue: String) {
        switch databaseValue.lowercased() {
        case "canvas": self = .canvas
        case "siweb": self = .siweb
        default: return nil
        }
    }
}

enum HealthLevel: String, Codable, Sendable {
    case healthy
    case warning
    case unavailable

    var label: String {
        switch self {
        case .healthy: "Healthy"
        case .warning: "Needs attention"
        case .unavailable: "Unavailable"
        }
    }
}

struct SourceHealth: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let source: SourceKind
    let level: HealthLevel
    let detail: String
    let lastSuccessfulSync: Date?
}

struct Course: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sourceAccountID: String
    let sourceObjectID: String
    let name: String
    let code: String
    let term: String
    let colorName: String
    let sourceURL: String?

    init(id: UUID, sourceAccountID: String, sourceObjectID: String, name: String, code: String,
         term: String, colorName: String, sourceURL: String? = nil) {
        self.id = id; self.sourceAccountID = sourceAccountID; self.sourceObjectID = sourceObjectID
        self.name = name; self.code = code; self.term = term; self.colorName = colorName; self.sourceURL = sourceURL
    }
}

struct CourseMeeting: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let courseID: UUID
    let title: String
    let start: Date
    let end: Date
    let location: String
    let source: SourceKind
    let isCancelled: Bool
    let isAllDay: Bool
    let sourceURL: String?

    init(id: UUID, courseID: UUID, title: String, start: Date, end: Date, location: String,
         source: SourceKind, isCancelled: Bool, isAllDay: Bool = false, sourceURL: String? = nil) {
        self.id = id; self.courseID = courseID; self.title = title; self.start = start; self.end = end
        self.location = location; self.source = source; self.isCancelled = isCancelled
        self.isAllDay = isAllDay; self.sourceURL = sourceURL
    }
}

enum TaskKind: String, CaseIterable, Codable, Sendable {
    case assignment = "Assignment"
    case quiz = "Quiz"
    case reading = "Reading"
}

enum TaskPriority: String, CaseIterable, Codable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

struct LearningTask: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sourceAccountID: String
    let sourceObjectID: String
    let courseID: UUID
    let title: String
    let kind: TaskKind
    let officialDueAt: Date?
    let suggestedCompleteAt: Date?
    let suggestedDateConfirmed: Bool
    let source: SourceKind
    var isLocallyComplete: Bool
    var localPriority: TaskPriority
    let officialDueIsAllDay: Bool
    let sourceURL: String?
    let isPlaceholder: Bool
    var placeholderAlwaysShow: Bool

    init(id: UUID, sourceAccountID: String, sourceObjectID: String, courseID: UUID, title: String,
         kind: TaskKind, officialDueAt: Date?, suggestedCompleteAt: Date?, suggestedDateConfirmed: Bool,
         source: SourceKind, isLocallyComplete: Bool, localPriority: TaskPriority,
         officialDueIsAllDay: Bool = false, sourceURL: String? = nil,
         isPlaceholder: Bool = false, placeholderAlwaysShow: Bool = false) {
        self.id = id; self.sourceAccountID = sourceAccountID; self.sourceObjectID = sourceObjectID
        self.courseID = courseID; self.title = title; self.kind = kind; self.officialDueAt = officialDueAt
        self.suggestedCompleteAt = suggestedCompleteAt; self.suggestedDateConfirmed = suggestedDateConfirmed
        self.source = source; self.isLocallyComplete = isLocallyComplete; self.localPriority = localPriority
        self.officialDueIsAllDay = officialDueIsAllDay; self.sourceURL = sourceURL
        self.isPlaceholder = isPlaceholder; self.placeholderAlwaysShow = placeholderAlwaysShow
    }

    var appearsInNormalTaskList: Bool { !isPlaceholder || placeholderAlwaysShow }
}

struct Announcement: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sourceObjectID: String
    let courseID: UUID
    let title: String
    let summary: String
    let publishedAt: Date
    let source: SourceKind
    var isLocallyRead: Bool
    let sourceURL: String?

    init(id: UUID, sourceObjectID: String, courseID: UUID, title: String, summary: String,
         publishedAt: Date, source: SourceKind, isLocallyRead: Bool, sourceURL: String? = nil) {
        self.id = id; self.sourceObjectID = sourceObjectID; self.courseID = courseID
        self.title = title; self.summary = summary; self.publishedAt = publishedAt
        self.source = source; self.isLocallyRead = isLocallyRead; self.sourceURL = sourceURL
    }
}

enum ConfirmationKind: String, CaseIterable, Codable, Sendable {
    case inferredDate = "Inferred date"
    case normalizedType = "Type suggestion"
    case relatedItem = "Related item"
    case actionItem = "Action item"
}

struct ConfirmationCandidate: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let courseID: UUID
    let kind: ConfirmationKind
    let sourceSummary: String
    let suggestion: String
    let confidence: Double
    let rationale: String
}

struct DashboardSnapshot: Equatable, Codable, Sendable {
    var sourceHealth: [SourceHealth]
    var courses: [Course]
    var meetings: [CourseMeeting]
    var tasks: [LearningTask]
    var announcements: [Announcement]
    var confirmations: [ConfirmationCandidate]

    static let empty = DashboardSnapshot(
        sourceHealth: [], courses: [], meetings: [], tasks: [], announcements: [], confirmations: []
    )

    func course(for id: UUID) -> Course? {
        courses.first { $0.id == id }
    }
}
