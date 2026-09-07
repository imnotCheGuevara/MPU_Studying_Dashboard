import Foundation

struct CanvasTermDTO: Decodable { let name: String? }

struct CanvasCourseDTO: Decodable {
    let id: CanvasID
    let name: String
    let courseCode: String?
    let timeZone: String?
    let htmlURL: URL?
    let term: CanvasTermDTO?

    enum CodingKeys: String, CodingKey {
        case id, name, term
        case courseCode = "course_code"
        case timeZone = "time_zone"
        case htmlURL = "html_url"
    }

    var payload: CanvasCoursePayload {
        CanvasCoursePayload(
            sourceObjectID: id.value,
            name: name,
            code: courseCode ?? "",
            term: term?.name ?? "",
            timeZone: timeZone,
            sourceURL: htmlURL
        )
    }
}

struct CanvasExternalToolDTO: Decodable { let url: URL? }

struct CanvasAssignmentDTO: Decodable {
    let id: CanvasID
    let courseID: CanvasID?
    let name: String
    let dueAt: Date?
    let unlockAt: Date?
    let lockAt: Date?
    let htmlURL: URL?
    let submissionTypes: [String]
    let quizID: CanvasID?
    let isQuizAssignment: Bool?
    let hasOverrides: Bool?
    let externalTool: CanvasExternalToolDTO?

    enum CodingKeys: String, CodingKey {
        case id, name
        case courseID = "course_id"
        case dueAt = "due_at"
        case unlockAt = "unlock_at"
        case lockAt = "lock_at"
        case htmlURL = "html_url"
        case submissionTypes = "submission_types"
        case quizID = "quiz_id"
        case isQuizAssignment = "is_quiz_assignment"
        case hasOverrides = "has_overrides"
        case externalTool = "external_tool_tag_attributes"
    }

    func payload(fallbackCourseID: String) -> CanvasTaskPayload {
        CanvasTaskPayload(
            sourceObjectID: id.value,
            courseSourceObjectID: courseID?.value ?? fallbackCourseID,
            title: name,
            officialType: classification,
            officialDueAt: dueAt,
            unlockAt: unlockAt,
            lockAt: lockAt,
            sourceURL: htmlURL,
            hasAssignmentOverrides: hasOverrides == true
        )
    }

    private var classification: String {
        if quizID != nil || submissionTypes.contains("online_quiz") { return "classic_quiz" }
        if submissionTypes.contains("external_tool") {
            let tool = externalTool?.url?.absoluteString.lowercased() ?? ""
            if isQuizAssignment == true || tool.contains("quiz-lti") || tool.contains("new_quiz") {
                return "new_quiz"
            }
            return "external_tool"
        }
        return "assignment"
    }
}

struct CanvasAnnouncementDTO: Decodable {
    let id: CanvasID
    let contextCode: String?
    let title: String
    let message: String?
    let postedAt: Date?
    let delayedPostAt: Date?
    let updatedAt: Date?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, title, message
        case contextCode = "context_code"
        case postedAt = "posted_at"
        case delayedPostAt = "delayed_post_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
    }

    func payload(fallbackCourseID: String) -> CanvasAnnouncementPayload {
        let courseID: String
        if let contextCode, contextCode.hasPrefix("course_") {
            courseID = String(contextCode.dropFirst("course_".count))
        } else {
            courseID = fallbackCourseID
        }
        return CanvasAnnouncementPayload(
            sourceObjectID: id.value,
            courseSourceObjectID: courseID,
            title: title,
            publishedAt: postedAt ?? delayedPostAt,
            updatedAt: updatedAt,
            summary: CanvasTextSanitizer.summary(message ?? ""),
            sourceURL: htmlURL
        )
    }
}

struct CanvasID: Decodable, Equatable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int64.self) { value = String(integer); return }
        if let string = try? container.decode(String.self), !string.isEmpty { value = string; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Canvas ID was not a string or integer")
    }
}

enum CanvasTextSanitizer {
    static func summary(_ html: String, limit: Int = 500) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\""]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(text.prefix(limit))
    }
}
