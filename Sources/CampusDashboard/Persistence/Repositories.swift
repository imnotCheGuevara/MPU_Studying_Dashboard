import Foundation

struct SourceAccountRecord: Equatable, Sendable {
    let id: UUID
    let kind: SourceKind
    let instanceURL: String
    var displayName: String
    var authorizationState: String
    var capabilitiesJSON: String
    var lastSuccessfulSync: Date?
    let createdAt: Date
    var updatedAt: Date
}

struct PersistedCourse: Equatable, Sendable {
    let id: UUID
    let sourceAccountID: UUID
    let sourceObjectID: String
    var name: String
    var code: String
    var term: String
    var timeZone: String
    var sourceURL: String?
    var sourceState: String
    let firstSeenAt: Date
    var lastSeenAt: Date
    var sourceUpdatedAt: Date?
}

struct PersistedLearningTask: Equatable, Sendable {
    let id: UUID
    let sourceAccountID: UUID
    let sourceObjectID: String
    var courseID: UUID?
    var title: String
    var officialType: String
    var normalizedType: String?
    var officialDueAt: Date?
    var officialDueTimeZone: String?
    var officialDueIsAllDay: Bool
    var suggestedCompleteAt: Date?
    var suggestionOrigin: String?
    var suggestionConfirmedAt: Date?
    var sourceState: String
    let firstSeenAt: Date
    var lastSeenAt: Date
}

struct LocalUserStateRecord: Equatable, Sendable {
    let objectType: String
    let objectID: String
    var isComplete: Bool
    var isRead: Bool
    var isHidden: Bool
    var priority: String?
    var modifiedAt: Date
}

struct OutboxWorkRecord: Equatable, Sendable {
    let id: UUID
    let kind: String
    let deduplicationKey: String
    let objectType: String
    let objectID: String
    let payload: Data
    var state: String
    var attemptCount: Int
    var availableAt: Date
    let createdAt: Date
    var updatedAt: Date
    var lastErrorCategory: String?
}

protocol PersistenceRepository: Sendable {
    @discardableResult func upsertSourceAccount(_ record: SourceAccountRecord) throws -> SourceAccountRecord
    func sourceAccounts() throws -> [SourceAccountRecord]
    func deleteSourceAccount(id: UUID) throws
    @discardableResult func upsertCourse(_ record: PersistedCourse) throws -> PersistedCourse
    func courses() throws -> [PersistedCourse]
    @discardableResult func upsertLearningTask(_ record: PersistedLearningTask) throws -> PersistedLearningTask
    func learningTasks() throws -> [PersistedLearningTask]
    func saveLocalState(_ record: LocalUserStateRecord) throws
    func localState(objectType: String, objectID: String) throws -> LocalUserStateRecord?
    @discardableResult func enqueue(_ record: OutboxWorkRecord) throws -> OutboxWorkRecord
    func pendingOutbox(now: Date) throws -> [OutboxWorkRecord]
}

final class SQLitePersistenceRepository: PersistenceRepository, @unchecked Sendable {
    let database: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.database = database
    }

    @discardableResult
    func upsertSourceAccount(_ record: SourceAccountRecord) throws -> SourceAccountRecord {
        try database.execute(
            """
            INSERT INTO source_accounts
              (id, source_kind, instance_url, display_name, authorization_state, capabilities_json,
               last_successful_sync, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_kind, instance_url) DO UPDATE SET
              display_name = excluded.display_name,
              authorization_state = excluded.authorization_state,
              capabilities_json = excluded.capabilities_json,
              last_successful_sync = excluded.last_successful_sync,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(record.id.uuidString), .text(record.kind.rawValue), .text(record.instanceURL),
                .text(record.displayName), .text(record.authorizationState), .text(record.capabilitiesJSON),
                date(record.lastSuccessfulSync), .real(record.createdAt.timeIntervalSince1970),
                .real(record.updatedAt.timeIntervalSince1970)
            ]
        )
        return try sourceAccounts().first {
            $0.kind == record.kind && $0.instanceURL == record.instanceURL
        }!
    }

    func sourceAccounts() throws -> [SourceAccountRecord] {
        try database.query("SELECT * FROM source_accounts ORDER BY created_at, id").compactMap { row in
            guard let id = uuid(row, "id"), let rawKind = row.string("source_kind"),
                  let kind = SourceKind(rawValue: rawKind), let instanceURL = row.string("instance_url"),
                  let displayName = row.string("display_name"),
                  let authorizationState = row.string("authorization_state"),
                  let capabilitiesJSON = row.string("capabilities_json"),
                  let createdAt = requiredDate(row, "created_at"), let updatedAt = requiredDate(row, "updated_at")
            else { return nil }
            return SourceAccountRecord(
                id: id, kind: kind, instanceURL: instanceURL, displayName: displayName,
                authorizationState: authorizationState, capabilitiesJSON: capabilitiesJSON,
                lastSuccessfulSync: optionalDate(row, "last_successful_sync"),
                createdAt: createdAt, updatedAt: updatedAt
            )
        }
    }

    func deleteSourceAccount(id: UUID) throws {
        try database.execute("DELETE FROM source_accounts WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    @discardableResult
    func upsertCourse(_ record: PersistedCourse) throws -> PersistedCourse {
        try database.execute(
            """
            INSERT INTO courses
              (id, source_account_id, source_object_id, name, code, term, time_zone, source_url,
               source_state, first_seen_at, last_seen_at, source_updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_account_id, source_object_id) DO UPDATE SET
              name = excluded.name, code = excluded.code, term = excluded.term,
              time_zone = excluded.time_zone, source_url = excluded.source_url,
              source_state = excluded.source_state, last_seen_at = excluded.last_seen_at,
              source_updated_at = excluded.source_updated_at
            """,
            bindings: [
                .text(record.id.uuidString), .text(record.sourceAccountID.uuidString),
                .text(record.sourceObjectID), .text(record.name), .text(record.code), .text(record.term),
                .text(record.timeZone), text(record.sourceURL), .text(record.sourceState),
                .real(record.firstSeenAt.timeIntervalSince1970), .real(record.lastSeenAt.timeIntervalSince1970),
                date(record.sourceUpdatedAt)
            ]
        )
        return try courses().first {
            $0.sourceAccountID == record.sourceAccountID && $0.sourceObjectID == record.sourceObjectID
        }!
    }

    func courses() throws -> [PersistedCourse] {
        try database.query("SELECT * FROM courses ORDER BY first_seen_at, id").compactMap { row in
            guard let id = uuid(row, "id"), let accountID = uuid(row, "source_account_id"),
                  let sourceObjectID = row.string("source_object_id"), let name = row.string("name"),
                  let code = row.string("code"), let term = row.string("term"),
                  let timeZone = row.string("time_zone"), let sourceState = row.string("source_state"),
                  let firstSeenAt = requiredDate(row, "first_seen_at"),
                  let lastSeenAt = requiredDate(row, "last_seen_at")
            else { return nil }
            return PersistedCourse(
                id: id, sourceAccountID: accountID, sourceObjectID: sourceObjectID, name: name,
                code: code, term: term, timeZone: timeZone, sourceURL: row.string("source_url"),
                sourceState: sourceState, firstSeenAt: firstSeenAt, lastSeenAt: lastSeenAt,
                sourceUpdatedAt: optionalDate(row, "source_updated_at")
            )
        }
    }

    @discardableResult
    func upsertLearningTask(_ record: PersistedLearningTask) throws -> PersistedLearningTask {
        try database.execute(
            """
            INSERT INTO learning_tasks
              (id, source_account_id, source_object_id, course_id, title, official_type, normalized_type,
               official_due_at, official_due_time_zone, official_due_is_all_day, suggested_complete_at,
               suggestion_origin, suggestion_confirmed_at, source_state, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_account_id, source_object_id) DO UPDATE SET
              course_id = excluded.course_id, title = excluded.title,
              official_type = excluded.official_type, normalized_type = excluded.normalized_type,
              official_due_at = excluded.official_due_at,
              official_due_time_zone = excluded.official_due_time_zone,
              official_due_is_all_day = excluded.official_due_is_all_day,
              suggested_complete_at = excluded.suggested_complete_at,
              suggestion_origin = excluded.suggestion_origin,
              suggestion_confirmed_at = excluded.suggestion_confirmed_at,
              source_state = excluded.source_state, last_seen_at = excluded.last_seen_at
            """,
            bindings: [
                .text(record.id.uuidString), .text(record.sourceAccountID.uuidString),
                .text(record.sourceObjectID), uuid(record.courseID), .text(record.title),
                .text(record.officialType), text(record.normalizedType), date(record.officialDueAt),
                text(record.officialDueTimeZone), .integer(record.officialDueIsAllDay ? 1 : 0),
                date(record.suggestedCompleteAt), text(record.suggestionOrigin),
                date(record.suggestionConfirmedAt), .text(record.sourceState),
                .real(record.firstSeenAt.timeIntervalSince1970), .real(record.lastSeenAt.timeIntervalSince1970)
            ]
        )
        return try learningTasks().first {
            $0.sourceAccountID == record.sourceAccountID && $0.sourceObjectID == record.sourceObjectID
        }!
    }

    func learningTasks() throws -> [PersistedLearningTask] {
        try database.query("SELECT * FROM learning_tasks ORDER BY first_seen_at, id").compactMap { row in
            guard let id = uuid(row, "id"), let accountID = uuid(row, "source_account_id"),
                  let sourceObjectID = row.string("source_object_id"), let title = row.string("title"),
                  let officialType = row.string("official_type"), let sourceState = row.string("source_state"),
                  let firstSeenAt = requiredDate(row, "first_seen_at"),
                  let lastSeenAt = requiredDate(row, "last_seen_at")
            else { return nil }
            return PersistedLearningTask(
                id: id, sourceAccountID: accountID, sourceObjectID: sourceObjectID,
                courseID: uuid(row, "course_id"), title: title, officialType: officialType,
                normalizedType: row.string("normalized_type"), officialDueAt: optionalDate(row, "official_due_at"),
                officialDueTimeZone: row.string("official_due_time_zone"),
                officialDueIsAllDay: row.int("official_due_is_all_day") == 1,
                suggestedCompleteAt: optionalDate(row, "suggested_complete_at"),
                suggestionOrigin: row.string("suggestion_origin"),
                suggestionConfirmedAt: optionalDate(row, "suggestion_confirmed_at"),
                sourceState: sourceState, firstSeenAt: firstSeenAt, lastSeenAt: lastSeenAt
            )
        }
    }

    func saveLocalState(_ record: LocalUserStateRecord) throws {
        try database.execute(
            """
            INSERT INTO local_user_states
              (object_type, object_id, is_complete, is_read, is_hidden, priority, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(object_type, object_id) DO UPDATE SET
              is_complete = excluded.is_complete, is_read = excluded.is_read,
              is_hidden = excluded.is_hidden, priority = excluded.priority,
              modified_at = excluded.modified_at
            """,
            bindings: [
                .text(record.objectType), .text(record.objectID), .integer(record.isComplete ? 1 : 0),
                .integer(record.isRead ? 1 : 0), .integer(record.isHidden ? 1 : 0),
                text(record.priority), .real(record.modifiedAt.timeIntervalSince1970)
            ]
        )
    }

    func localState(objectType: String, objectID: String) throws -> LocalUserStateRecord? {
        let rows = try database.query(
            "SELECT * FROM local_user_states WHERE object_type = ? AND object_id = ?",
            bindings: [.text(objectType), .text(objectID)]
        )
        guard let row = rows.first, let modifiedAt = requiredDate(row, "modified_at") else { return nil }
        return LocalUserStateRecord(
            objectType: objectType, objectID: objectID, isComplete: row.int("is_complete") == 1,
            isRead: row.int("is_read") == 1, isHidden: row.int("is_hidden") == 1,
            priority: row.string("priority"), modifiedAt: modifiedAt
        )
    }

    @discardableResult
    func enqueue(_ record: OutboxWorkRecord) throws -> OutboxWorkRecord {
        try database.execute(
            """
            INSERT INTO outbox_work
              (id, kind, deduplication_key, object_type, object_id, payload, state, attempt_count,
               available_at, created_at, updated_at, last_error_category)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(deduplication_key) DO NOTHING
            """,
            bindings: [
                .text(record.id.uuidString), .text(record.kind), .text(record.deduplicationKey),
                .text(record.objectType), .text(record.objectID), .blob(record.payload),
                .text(record.state), .integer(Int64(record.attemptCount)),
                .real(record.availableAt.timeIntervalSince1970), .real(record.createdAt.timeIntervalSince1970),
                .real(record.updatedAt.timeIntervalSince1970), text(record.lastErrorCategory)
            ]
        )
        return try outbox(deduplicationKey: record.deduplicationKey)!
    }

    func pendingOutbox(now: Date) throws -> [OutboxWorkRecord] {
        try database.query(
            "SELECT * FROM outbox_work WHERE state = 'pending' AND available_at <= ? ORDER BY created_at, id",
            bindings: [.real(now.timeIntervalSince1970)]
        ).compactMap(decodeOutbox)
    }

    private func outbox(deduplicationKey: String) throws -> OutboxWorkRecord? {
        try database.query(
            "SELECT * FROM outbox_work WHERE deduplication_key = ?",
            bindings: [.text(deduplicationKey)]
        ).compactMap(decodeOutbox).first
    }

    private func decodeOutbox(_ row: SQLiteRow) -> OutboxWorkRecord? {
        guard let id = uuid(row, "id"), let kind = row.string("kind"),
              let key = row.string("deduplication_key"), let objectType = row.string("object_type"),
              let objectID = row.string("object_id"), let payload = row.data("payload"),
              let state = row.string("state"), let attemptCount = row.int("attempt_count"),
              let availableAt = requiredDate(row, "available_at"),
              let createdAt = requiredDate(row, "created_at"), let updatedAt = requiredDate(row, "updated_at")
        else { return nil }
        return OutboxWorkRecord(
            id: id, kind: kind, deduplicationKey: key, objectType: objectType, objectID: objectID,
            payload: payload, state: state, attemptCount: Int(attemptCount), availableAt: availableAt,
            createdAt: createdAt, updatedAt: updatedAt,
            lastErrorCategory: row.string("last_error_category")
        )
    }

    private func text(_ value: String?) -> SQLiteValue { value.map(SQLiteValue.text) ?? .null }
    private func uuid(_ value: UUID?) -> SQLiteValue { value.map { .text($0.uuidString) } ?? .null }
    private func date(_ value: Date?) -> SQLiteValue { value.map { .real($0.timeIntervalSince1970) } ?? .null }
    private func uuid(_ row: SQLiteRow, _ name: String) -> UUID? { row.string(name).flatMap(UUID.init(uuidString:)) }
    private func optionalDate(_ row: SQLiteRow, _ name: String) -> Date? { row.double(name).map(Date.init(timeIntervalSince1970:)) }
    private func requiredDate(_ row: SQLiteRow, _ name: String) -> Date? { optionalDate(row, name) }
}

protocol LocalStateRepository: Sendable {
    func state(objectType: String, objectID: String) throws -> LocalUserStateRecord?
    func save(_ state: LocalUserStateRecord) throws
}

struct LocalPersistenceUnavailable: Error, CustomStringConvertible, Sendable {
    let reason: String
    var description: String { "Local persistence is unavailable: \(reason)" }
}

struct UnavailableLocalStateRepository: LocalStateRepository {
    let error: LocalPersistenceUnavailable
    func state(objectType: String, objectID: String) throws -> LocalUserStateRecord? { throw error }
    func save(_ state: LocalUserStateRecord) throws { throw error }
}

final class SQLiteLocalStateRepository: LocalStateRepository, @unchecked Sendable {
    private let persistence: SQLitePersistenceRepository

    init(persistence: SQLitePersistenceRepository) { self.persistence = persistence }
    func state(objectType: String, objectID: String) throws -> LocalUserStateRecord? {
        try persistence.localState(objectType: objectType, objectID: objectID)
    }
    func save(_ state: LocalUserStateRecord) throws { try persistence.saveLocalState(state) }
}

final class InMemoryLocalStateRepository: LocalStateRepository, @unchecked Sendable {
    private var records: [String: LocalUserStateRecord] = [:]
    private let lock = NSLock()

    func state(objectType: String, objectID: String) throws -> LocalUserStateRecord? {
        lock.withLock { records["\(objectType):\(objectID)"] }
    }

    func save(_ state: LocalUserStateRecord) throws {
        lock.withLock { records["\(state.objectType):\(state.objectID)"] = state }
    }
}
