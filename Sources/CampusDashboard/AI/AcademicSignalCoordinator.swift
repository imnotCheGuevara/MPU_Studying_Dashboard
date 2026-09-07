import CryptoKit
import Foundation

struct DeterministicAcademicSignalClassifier: Sendable {
    func classify(title: String, text: String) -> AcademicSignalProviderResponse {
        let combined = (title + "\n" + text).lowercased()
        var signals: [AcademicSignalSuggestion] = []
        func contains(_ terms: [String]) -> Bool { terms.contains { combined.contains($0) } }
        func evidence(_ terms: [String]) -> String {
            guard let term = terms.first(where: { combined.contains($0) }) else {
                return String((text.isEmpty ? title : text).prefix(180))
            }
            let source = title.lowercased().contains(term) ? title : text
            guard let range = source.lowercased().range(of: term) else { return String(source.prefix(180)) }
            let offset = source.distance(from: source.startIndex, to: range.lowerBound)
            let start = source.index(source.startIndex, offsetBy: max(0, offset - 60))
            return String(source[start...].prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let schedule = ["class moved", "class cancellation", "class cancelled", "class canceled", "room change", "make-up class", "schedule change", "课程取消", "取消课程", "课堂取消", "取消上课", "停课", "补课", "调课", "教室改", "上课地点", "课程安排"]
        let assignment = ["assignment due", "deadline", "submit by", "submission", "homework due", "作业截止", "提交截止", "功课截止", "请于", "ddl"]
        let exam = ["exam", "quiz", "midterm", "test time", "考试", "测验", "小测", "期中", "期末"]
        if contains(schedule) { signals.append(make(.courseScheduleChange, evidence(schedule), "Review the changed course schedule.")) }
        if contains(assignment) { signals.append(make(.assignmentDeadline, evidence(assignment), "Review the assignment submission requirement.")) }
        if contains(exam) { signals.append(make(.examTime, evidence(exam), "Review the exam or quiz arrangement.")) }
        return AcademicSignalProviderResponse(
            primaryCategory: signals.first?.category ?? .other, signals: signals
        )
    }

    private func make(
        _ category: AcademicSignalCategory, _ evidence: String, _ requirement: String
    ) -> AcademicSignalSuggestion {
        AcademicSignalSuggestion(
            category: category, evidence: evidence, keyRequirement: requirement,
            inferredDate: nil, isAllDay: false, timeZoneIdentifier: nil,
            confidence: 0.92, reason: "Matched a fixed local academic phrase.", conflicts: []
        )
    }
}

enum AcademicSignalSanitizer {
    static let maximumTitleLength = 240
    static let maximumBodyLength = 4_000
    static let maximumCourseLength = 160

    static func input(
        announcementID: String, title: String, body: String, courseName: String?,
        courseCode: String? = nil, localSection: String? = nil,
        meetingCandidates: [AcademicMeetingCandidate] = [], locale: String
    ) -> AcademicSignalInput {
        AcademicSignalInput(
            announcementID: "local-selected-announcement",
            title: clean(title, limit: maximumTitleLength),
            visibleTextExcerpt: cleanHTML(body, limit: maximumBodyLength),
            courseName: courseName.map { clean($0, limit: maximumCourseLength) },
            courseCode: courseCode.map { clean($0, limit: maximumCourseLength) },
            localSection: localSection.map { clean($0, limit: 40) },
            meetingCandidates: Array(meetingCandidates.prefix(24)),
            locale: clean(locale, limit: 24)
        )
    }

    static func cleanHTML(_ value: String, limit: Int) -> String {
        var result = value
        let blockPatterns = [
            "(?is)<!--.*?-->", "(?is)<(script|style|iframe|svg|object|embed)[^>]*>.*?</\\1>",
            "(?is)<(img|source|video|audio|link|meta)[^>]*>", "(?is)<[^>]+>"
        ]
        for pattern in blockPatterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, replacement) in entities { result = result.replacingOccurrences(of: entity, with: replacement) }
        return clean(result, limit: limit)
    }

    static func clean(_ value: String, limit: Int) -> String {
        var result = value
        let patterns = [
            "(?i)https?://[^\\s<]+", "(?i)mailto:[^\\s<]+",
            "(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            "(?i)bearer\\s+[A-Za-z0-9._~+/-]+",
            "(?i)(token|password|cookie|secret|authorization)\\s*[:=]\\s*[^\\s]+",
            "(?i)(utm_[a-z_]+|fbclid|gclid)=[^&\\s]+"
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(result.prefix(limit))
    }
}

final class AcademicSignalCoordinator: @unchecked Sendable {
    static let promptVersion = "canvas-announcement-signals-v3"
    static let schemaVersion = "3"

    private let database: SQLiteDatabase
    private let persistence: AcademicSignalPersistence
    private let settingsPersistence: AIPersistence
    private let provider: (any AcademicSignalProvider)?
    private let classifier = DeterministicAcademicSignalClassifier()
    private let clock: any Clock
    private let ids: any IDGenerator

    init(database: SQLiteDatabase, provider: (any AcademicSignalProvider)? = nil,
         clock: any Clock = SystemClock(), ids: any IDGenerator = SystemIDGenerator()) {
        self.database = database; self.persistence = AcademicSignalPersistence(database: database)
        self.settingsPersistence = AIPersistence(database: database); self.provider = provider
        self.clock = clock; self.ids = ids
    }

    func processPending(limit: Int = 100, locale: String = "source") async -> Int {
        let rows = (try? database.query(
            """
            SELECT r.id AS raw_id,r.source_account_id,r.source_object_id,r.payload,
              a.id AS announcement_id,a.title,a.summary,a.content_hash,c.name AS course_name
            FROM raw_source_records r
            JOIN source_accounts sa ON sa.id=r.source_account_id AND sa.source_kind='Canvas'
            JOIN announcements a ON a.source_account_id=r.source_account_id
              AND a.source_object_id=r.source_object_id AND a.source_state='active'
            LEFT JOIN courses c ON c.id=a.course_id
            WHERE r.object_type='announcement'
              AND r.rowid=(SELECT r2.rowid FROM raw_source_records r2
                WHERE r2.source_account_id=r.source_account_id
                  AND r2.object_type=r.object_type AND r2.source_object_id=r.source_object_id
                ORDER BY r2.fetched_at DESC,r2.rowid DESC LIMIT 1)
            ORDER BY r.fetched_at,r.id
            """
        )) ?? []
        await provider?.beginRun()
        var count = 0
        for row in rows where !Task.isCancelled {
            guard count < max(0, limit) else { break }
            guard let rawID = row.string("raw_id").flatMap(UUID.init(uuidString:)),
                  let announcementID = row.string("announcement_id").flatMap(UUID.init(uuidString:)),
                  let accountID = row.string("source_account_id"), let sourceID = row.string("source_object_id"),
                  let title = row.string("title"), let body = row.string("summary"),
                  let contentHash = row.string("content_hash") else { continue }
            let input = AcademicSignalSanitizer.input(
                announcementID: announcementID.uuidString, title: title, body: body,
                courseName: row.string("course_name"), locale: locale
            )
            if await process(rawID: rawID, announcementID: announcementID,
                             accountID: accountID, sourceID: sourceID,
                             contentHash: contentHash, input: input) { count += 1 }
        }
        return count
    }

    @discardableResult
    func process(rawID: UUID, announcementID: UUID, accountID: String, sourceID: String,
                 contentHash: String, input: AcademicSignalInput, force: Bool = false) async -> Bool {
        let providerName = provider?.providerName ?? "Local deterministic rules"
        let modelName = provider?.modelName ?? "fixed-phrases-v1"
        if !force,
           (try? persistence.analysis(
                rawSourceRecordID: rawID, contentHash: contentHash, provider: providerName,
                model: modelName, promptVersion: Self.promptVersion, schemaVersion: Self.schemaVersion
           )) != nil { return false }

        let scopedInput = (try? scopedInput(input, announcementID: announcementID)) ?? input
        let fixed = classifier.classify(title: scopedInput.title, text: scopedInput.visibleTextExcerpt)
        let localRule = try? personalizedResponse(for: announcementID, input: scopedInput)
        let deterministic = localRule?.response ?? fixed
        var output = deterministic
        var status: AcademicAnalysisStatus = .deterministicOnly
        var failure: String?
        let enabled = (try? settingsPersistence.settings()).map { $0.enabled && $0.mayUseProvider } ?? false
        if enabled, let provider {
            do {
                try provider.validateAvailability()
                let data = try await provider.academicSignals(for: scopedInput)
                let external = try AcademicSignalOutputValidator.decode(data)
                output = merge(deterministic: deterministic, external: external)
                status = .analyzed
            } catch {
                status = .failed
                if let value = error as? DeepSeekProviderError { failure = value.category.rawValue }
                else if let value = error as? AcademicSignalValidationError { failure = value.rawValue }
                else if error as? AIParsingError == .budgetExceeded { failure = "budget_exceeded" }
                else if error as? AIParsingError == .missingCredential { failure = "missing_credential" }
                else if error as? AIParsingError == .consentRequired { failure = "consent_required" }
                else { failure = AcademicSignalValidationError.other.rawValue }
            }
        } else if provider != nil { status = .disabled }

        let now = clock.now
        let analysis = AcademicAnnouncementAnalysis(
            id: ids.next(), rawSourceRecordID: rawID, announcementID: announcementID,
            sourceAccountID: accountID, sourceObjectID: sourceID, contentHash: contentHash,
            primaryCategory: output.primaryCategory, status: status,
            provider: providerName, model: modelName, promptVersion: Self.promptVersion,
            schemaVersion: Self.schemaVersion, failureCategory: failure, createdAt: now, updatedAt: now
        )
        do {
            let stored = try persistence.saveAnalysis(analysis)
            let records = output.signals.map { suggestion in
                let target = resolvedMeeting(for: suggestion, input: scopedInput)
                let audience: AcademicAudienceResolution = suggestion.category == .courseScheduleChange
                    ? (target == nil ? .pendingReview : .resolved) : .noTarget
                return AcademicSignalRecord(
                    id: ids.next(), analysisID: stored.id, announcementID: announcementID,
                    sourceAccountID: accountID, sourceObjectID: sourceID, category: suggestion.category,
                    evidence: suggestion.evidence, keyRequirement: suggestion.keyRequirement,
                    inferredDate: suggestion.inferredDate, isAllDay: suggestion.isAllDay,
                    timeZoneIdentifier: suggestion.timeZoneIdentifier, confidence: suggestion.confidence,
                    reason: suggestion.reason, conflicts: suggestion.conflicts,
                    provider: providerName, model: modelName, promptVersion: Self.promptVersion,
                    schemaVersion: Self.schemaVersion,
                    confirmationState: suggestion.inferredDate == nil && suggestion.category != .courseScheduleChange
                        ? .notRequired : .pending,
                    adoptedCategory: nil, adoptedDate: nil, adoptedIsAllDay: nil,
                    courseID: try? courseID(for: announcementID), adoptedKeyRequirement: nil,
                    adoptedTimeZoneIdentifier: nil,
                    decisionOrigin: localRule == nil ? .automated : .localSupervisedRule,
                    personalizationRuleVersion: localRule?.version,
                    targetMeetingID: target, audienceResolution: audience,
                    createdAt: now, updatedAt: now
                )
            }
            if try !persistence.hasActiveUserDecision(announcementID: announcementID) {
                try persistence.replaceActiveSignals(analysisID: stored.id, values: records)
            }
            return true
        } catch { return false }
    }

    func analyses() throws -> [AcademicAnnouncementAnalysis] { try persistence.analyses() }
    func activeSignals() throws -> [AcademicSignalRecord] { try persistence.activeSignals() }

    func reprocess(announcementID: UUID, locale: String = "source") async -> Bool {
        guard let row = try? database.query(
            """
            SELECT r.id AS raw_id,r.source_account_id,r.source_object_id,
              a.title,a.summary,a.content_hash,c.name AS course_name
            FROM announcements a
            JOIN raw_source_records r ON r.source_account_id=a.source_account_id
              AND r.source_object_id=a.source_object_id AND r.object_type='announcement'
            LEFT JOIN courses c ON c.id=a.course_id
            WHERE a.id=? ORDER BY r.fetched_at DESC LIMIT 1
            """, bindings: [.text(announcementID.uuidString)]
        ).first,
              let rawID = row.string("raw_id").flatMap(UUID.init(uuidString:)),
              let accountID = row.string("source_account_id"), let sourceID = row.string("source_object_id"),
              let title = row.string("title"), let body = row.string("summary"),
              let hash = row.string("content_hash") else { return false }
        let input = AcademicSignalSanitizer.input(
            announcementID: announcementID.uuidString, title: title, body: body,
            courseName: row.string("course_name"), locale: locale
        )
        await provider?.beginRun()
        return await process(rawID: rawID, announcementID: announcementID,
                             accountID: accountID, sourceID: sourceID,
                             contentHash: hash, input: input, force: true)
    }
    func confirm(_ id: UUID) throws { try transition(id, action: "confirm", correction: nil) }
    func reject(_ id: UUID) throws { try transition(id, action: "reject", correction: nil) }
    func correct(_ id: UUID, correction: AcademicSignalCorrection) throws {
        try transition(id, action: "correct", correction: correction)
    }
    func correctAnalysis(_ id: UUID, correction: AcademicSignalCorrection) throws {
        try persistence.correctAnalysis(id: id, correction: correction, now: clock.now,
                                        signalID: ids.next(), auditID: ids.next())
    }
    func undo(_ id: UUID) throws { try transition(id, action: "undo", correction: nil) }
    func reset(_ id: UUID) throws { try transition(id, action: "reset", correction: nil) }

    private func transition(_ id: UUID, action: String, correction: AcademicSignalCorrection?) throws {
        try persistence.transition(id: id, action: action, correction: correction,
                                   now: clock.now, auditID: ids.next())
    }

    private func courseID(for announcementID: UUID) throws -> UUID? {
        try database.query("SELECT course_id FROM announcements WHERE id=?", bindings: [.text(announcementID.uuidString)])
            .first?.string("course_id").flatMap(UUID.init(uuidString:))
    }

    private func scopedInput(_ input: AcademicSignalInput, announcementID: UUID) throws -> AcademicSignalInput {
        guard let canvas = try database.query(
            "SELECT c.id,c.code,c.name FROM announcements a JOIN courses c ON c.id=a.course_id WHERE a.id=?",
            bindings: [.text(announcementID.uuidString)]
        ).first, let canvasID = canvas.string("id"), let code = canvas.string("code") else { return input }
        var mappedIDs = try database.query(
            "SELECT siweb_course_id FROM academic_course_mappings WHERE canvas_course_id=? AND is_active=1",
            bindings: [.text(canvasID)]
        ).compactMap { $0.string("siweb_course_id") }
        if mappedIDs.isEmpty {
            let normalized = Self.normalizedCourseCode(code)
            let matches = try database.query(
                "SELECT c.id,c.code FROM courses c JOIN source_accounts s ON s.id=c.source_account_id WHERE s.source_kind='SIweb' AND c.source_state='active'"
            ).filter { Self.normalizedCourseCode($0.string("code") ?? "") == normalized }
            if matches.count == 1, let siwebID = matches[0].string("id") {
                let now = clock.now.timeIntervalSince1970
                try database.execute(
                    "INSERT OR IGNORE INTO academic_course_mappings(id,canvas_course_id,siweb_course_id,section_key,origin,is_active,created_at,updated_at) VALUES(?,?,?,?, 'exact_course_code',1,?,?)",
                    bindings: [.text(ids.next().uuidString), .text(canvasID), .text(siwebID), .text(code), .real(now), .real(now)]
                )
                mappedIDs = [siwebID]
            }
        }
        guard mappedIDs.count == 1 else {
            return AcademicSignalInput(announcementID: input.announcementID, title: input.title,
                visibleTextExcerpt: input.visibleTextExcerpt, courseName: input.courseName,
                courseCode: code, localSection: nil, meetingCandidates: [], locale: input.locale)
        }
        let rows = try database.query(
            "SELECT m.*,c.code AS course_code FROM course_meetings m JOIN courses c ON c.id=m.course_id WHERE m.course_id=? AND m.source_state='active' ORDER BY m.starts_at LIMIT 24",
            bindings: [.text(mappedIDs[0])]
        )
        let candidates = rows.compactMap { row -> AcademicMeetingCandidate? in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let start = row.double("starts_at").map(Date.init(timeIntervalSince1970:)),
                  let end = row.double("ends_at").map(Date.init(timeIntervalSince1970:)) else { return nil }
            return .init(meetingID: id, courseCode: row.string("course_code") ?? code,
                         section: code, startsAt: start, endsAt: end,
                         timeZoneIdentifier: row.string("original_time_zone") ?? "Asia/Macau",
                         location: row.string("location") ?? "")
        }
        return AcademicSignalInput(announcementID: input.announcementID, title: input.title,
            visibleTextExcerpt: input.visibleTextExcerpt, courseName: input.courseName ?? canvas.string("name"),
            courseCode: code, localSection: code, meetingCandidates: candidates, locale: input.locale)
    }

    private func resolvedMeeting(for signal: AcademicSignalSuggestion, input: AcademicSignalInput) -> UUID? {
        guard signal.category == .courseScheduleChange else { return nil }
        if input.meetingCandidates.count == 1 { return input.meetingCandidates[0].meetingID }
        guard let date = signal.inferredDate else { return nil }
        let matches = input.meetingCandidates.filter { abs($0.startsAt.timeIntervalSince(date)) <= 43_200 }
        return matches.count == 1 ? matches[0].meetingID : nil
    }

    private static func normalizedCourseCode(_ value: String) -> String {
        value.uppercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    private func personalizedResponse(
        for announcementID: UUID, input: AcademicSignalInput
    ) throws -> (response: AcademicSignalProviderResponse, version: String)? {
        guard let courseID = try courseID(for: announcementID) else { return nil }
        let title = input.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let rules = try database.query(
            "SELECT trigger_phrase,category,key_requirement,rule_version FROM academic_personalization_rules WHERE course_id=? AND is_active=1 ORDER BY updated_at DESC",
            bindings: [.text(courseID.uuidString)]
        )
        guard let rule = rules.first(where: {
            guard let trigger = $0.string("trigger_phrase"), !trigger.isEmpty else { return false }
            return title.contains(trigger)
        }), let category = rule.string("category").flatMap(AcademicSignalCategory.init(rawValue:)),
              let version = rule.string("rule_version") else { return nil }
        let suggestion = AcademicSignalSuggestion(
            category: category, evidence: String(input.title.prefix(180)),
            keyRequirement: rule.string("key_requirement") ?? "Review this academic update.",
            inferredDate: nil, isAllDay: false, timeZoneIdentifier: nil,
            confidence: 0.95, reason: "Matched a versioned course-local supervised correction.",
            conflicts: []
        )
        return (.init(primaryCategory: category, signals: [suggestion]), version)
    }

    private func merge(
        deterministic: AcademicSignalProviderResponse, external: AcademicSignalProviderResponse
    ) -> AcademicSignalProviderResponse {
        var result = deterministic.signals
        for signal in external.signals {
            if let index = result.firstIndex(where: { $0.category == signal.category }) {
                let local = result[index]
                result[index] = AcademicSignalSuggestion(
                    category: local.category,
                    evidence: local.evidence.count <= signal.evidence.count ? local.evidence : signal.evidence,
                    keyRequirement: signal.keyRequirement,
                    inferredDate: signal.inferredDate, isAllDay: signal.isAllDay,
                    timeZoneIdentifier: signal.timeZoneIdentifier,
                    confidence: max(local.confidence, signal.confidence),
                    reason: local.reason + " " + signal.reason,
                    conflicts: signal.conflicts
                )
            } else {
                result.append(signal)
            }
        }
        return AcademicSignalProviderResponse(
            primaryCategory: deterministic.signals.first?.category ?? external.primaryCategory,
            signals: result
        )
    }
}
