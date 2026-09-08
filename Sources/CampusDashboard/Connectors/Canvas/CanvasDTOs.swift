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
struct CanvasAttachmentDTO: Decodable { let id: CanvasID? }

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
    let description: String?
    let attachments: [CanvasAttachmentDTO]?
    let annotatableAttachmentID: CanvasID?
    let placeholderEvidenceComplete: Bool

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
        case annotatableAttachmentID = "annotatable_attachment_id"
        case description, attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(CanvasID.self, forKey: .id)
        courseID = try c.decodeIfPresent(CanvasID.self, forKey: .courseID)
        name = try c.decode(String.self, forKey: .name)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        unlockAt = try c.decodeIfPresent(Date.self, forKey: .unlockAt)
        lockAt = try c.decodeIfPresent(Date.self, forKey: .lockAt)
        htmlURL = try c.decodeIfPresent(URL.self, forKey: .htmlURL)
        submissionTypes = try c.decodeIfPresent([String].self, forKey: .submissionTypes) ?? []
        quizID = try c.decodeIfPresent(CanvasID.self, forKey: .quizID)
        isQuizAssignment = try c.decodeIfPresent(Bool.self, forKey: .isQuizAssignment)
        hasOverrides = try c.decodeIfPresent(Bool.self, forKey: .hasOverrides)
        externalTool = try c.decodeIfPresent(CanvasExternalToolDTO.self, forKey: .externalTool)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        attachments = try c.decodeIfPresent([CanvasAttachmentDTO].self, forKey: .attachments)
        annotatableAttachmentID = try c.decodeIfPresent(CanvasID.self, forKey: .annotatableAttachmentID)
        placeholderEvidenceComplete = c.contains(.dueAt) && c.contains(.description)
            && c.contains(.submissionTypes) && c.contains(.quizID)
            && c.contains(.externalTool) && c.contains(.annotatableAttachmentID)
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
            hasAssignmentOverrides: hasOverrides == true,
            placeholderEvidence: TaskPlaceholderEvidence(
                isComplete: placeholderEvidenceComplete,
                hasMeaningfulDescription: Self.meaningfulText(description),
                hasAttachment: annotatableAttachmentID != nil || !(attachments ?? []).isEmpty,
                hasLinkedActivity: quizID != nil || isQuizAssignment == true || externalTool != nil
                    || submissionTypes.contains(where: { ["online_quiz", "external_tool"].contains($0) }),
                hasMeaningfulSubmission: submissionTypes.contains { !$0.isEmpty && $0 != "none" },
                hasActionableRequirement: Self.actionableTitle(name)
            )
        )
    }

    private static func meaningfulText(_ value: String?) -> Bool {
        guard let value else { return false }
        if value.range(of: #"<a\b[^>]*\bhref\s*="#,
                       options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let plain = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !plain.isEmpty
    }

    private static func actionableTitle(_ value: String) -> Bool {
        let text = value.lowercased()
        return ["offline", "reading", "read ", "prepare", "prep", "attendance", "attend",
                "线下", "阅读", "预习", "准备", "出席", "签到"].contains { text.contains($0) }
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
