import Foundation

final class AIPersistence: @unchecked Sendable {
    private let database: SQLiteDatabase

    init(database: SQLiteDatabase) { self.database = database }

    func settings() throws -> AIAssistanceSettings {
        guard let row = try database.query("SELECT * FROM ai_settings WHERE singleton_key=1").first,
              let rawProvider = row.string("provider_kind"),
              let provider = AIProviderKind(rawValue: rawProvider),
              let updated = row.double("updated_at")
        else { throw DatabaseError.step("AI settings are unavailable") }
        return AIAssistanceSettings(
            enabled: row.int("enabled") == 1, providerKind: provider,
            providerDisclosure: row.string("provider_disclosure"),
            transmittedFields: row.string("transmitted_fields"),
            retentionPolicy: row.string("retention_policy"),
            consentedAt: row.double("consented_at").map(Date.init(timeIntervalSince1970:)),
            consentVersion: row.string("consent_version"),
            consentSignature: row.string("consent_signature"),
            schoolPolicyConfirmed: row.int("school_policy_confirmed") == 1,
            providerModel: row.string("provider_model"),
            perRunRequestBudget: Int(row.int("per_run_request_budget") ?? 10),
            dailyRequestBudget: Int(row.int("daily_request_budget") ?? 50),
            perRunTokenBudget: Int(row.int("per_run_token_budget") ?? 20_000),
            dailyTokenBudget: Int(row.int("daily_token_budget") ?? 100_000),
            directHTTPSForDeepSeek: row.int("deepseek_direct_https") == 1,
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    func saveSettings(_ value: AIAssistanceSettings) throws {
        guard value.providerKind != .external || !value.enabled || value.mayUseProvider else {
            throw AIParsingError.consentRequired
        }
        try database.execute(
            """
            UPDATE ai_settings SET enabled=?, provider_kind=?, provider_disclosure=?,
              transmitted_fields=?, retention_policy=?, consented_at=?, consent_version=?,
              consent_signature=?, school_policy_confirmed=?, provider_model=?,
              per_run_request_budget=?, daily_request_budget=?, per_run_token_budget=?,
              daily_token_budget=?, deepseek_direct_https=?, updated_at=?
            WHERE singleton_key=1
            """,
            bindings: [
                .integer(value.enabled ? 1 : 0), .text(value.providerKind.rawValue),
                value.providerDisclosure.map(SQLiteValue.text) ?? .null,
                value.transmittedFields.map(SQLiteValue.text) ?? .null,
                value.retentionPolicy.map(SQLiteValue.text) ?? .null,
                value.consentedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                value.consentVersion.map(SQLiteValue.text) ?? .null,
                value.consentSignature.map(SQLiteValue.text) ?? .null,
                .integer(value.schoolPolicyConfirmed ? 1 : 0),
                value.providerModel.map(SQLiteValue.text) ?? .null,
                .integer(Int64(value.perRunRequestBudget)),
                .integer(Int64(value.dailyRequestBudget)),
                .integer(Int64(value.perRunTokenBudget)),
                .integer(Int64(value.dailyTokenBudget)),
                .integer(value.directHTTPSForDeepSeek ? 1 : 0),
                .real(value.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    @discardableResult
    func save(_ record: AIParseRecord, output: Data?) throws -> AIParseRecord {
        try database.execute(
            """
            INSERT INTO ai_parse_results
              (id, raw_source_record_id, input_hash, provider, model, prompt_version, schema_version,
               suggested_type, normalized_title, official_date_echo, suggested_date, confidence,
               rationale, has_conflict, confirmation_state, created_at, target_object_type,
               target_object_id, related_object_ids_json, action_items_json, change_summary,
               output_json, failure_category, source_summary, source_url, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(raw_source_record_id, input_hash, model, prompt_version, schema_version)
            DO UPDATE SET failure_category=excluded.failure_category, updated_at=excluded.updated_at
            """,
            bindings: [
                .text(record.id.uuidString), .text(record.rawSourceRecordID.uuidString),
                .text(record.inputHash), .text(record.provider), .text(record.model),
                .text(record.promptVersion), .text(record.schemaVersion),
                record.suggestedType.map(SQLiteValue.text) ?? .null,
                record.normalizedTitle.map(SQLiteValue.text) ?? .null,
                record.officialDateEcho.map { .real($0.timeIntervalSince1970) } ?? .null,
                record.suggestedDate.map { .real($0.timeIntervalSince1970) } ?? .null,
                .real(record.confidence), .text(record.rationale),
                .integer(record.hasConflict ? 1 : 0), .text(record.confirmationState.rawValue),
                .real(record.createdAt.timeIntervalSince1970), .text(record.targetObjectType),
                .text(record.targetObjectID), .text(json(record.relatedObjectIDs)),
                .text(json(record.actionItems)), .text(record.changeSummary),
                output.map(SQLiteValue.blob) ?? .null,
                record.failureCategory.map(SQLiteValue.text) ?? .null,
                .text(record.sourceSummary), record.sourceURL.map(SQLiteValue.text) ?? .null,
                .real(record.updatedAt.timeIntervalSince1970)
            ]
        )
        let matches = try database.query(
            """
            SELECT * FROM ai_parse_results
            WHERE raw_source_record_id=? AND input_hash=? AND model=?
              AND prompt_version=? AND schema_version=?
            """,
            bindings: [
                .text(record.rawSourceRecordID.uuidString), .text(record.inputHash),
                .text(record.model), .text(record.promptVersion), .text(record.schemaVersion)
            ]
        )
        guard let stored = matches.first.flatMap(decode) else {
            throw DatabaseError.step("AI parse result could not be reloaded")
        }
        return stored
    }

    func records(states: Set<AIConfirmationState>? = nil) throws -> [AIParseRecord] {
        let all = try database.query("SELECT * FROM ai_parse_results ORDER BY created_at, id").compactMap(decode)
        guard let states else { return all }
        return all.filter { states.contains($0.confirmationState) }
    }

    func productionRecords(states: Set<AIConfirmationState>? = nil) throws -> [AIParseRecord] {
        try records(states: states).filter {
            ProductionAIResultPolicy.includes(provider: $0.provider, model: $0.model)
        }
    }

    func record(id: UUID) throws -> AIParseRecord? {
        try database.query("SELECT * FROM ai_parse_results WHERE id=?", bindings: [.text(id.uuidString)]).first.flatMap(decode)
    }

    func updateState(id: UUID, state: AIConfirmationState, at: Date) throws {
        try database.execute(
            "UPDATE ai_parse_results SET confirmation_state=?, updated_at=? WHERE id=?",
            bindings: [.text(state.rawValue), .real(at.timeIntervalSince1970), .text(id.uuidString)]
        )
    }

    func setAdoptedValues(
        id: UUID, title: String?, type: String?, date: Date?, at: Date
    ) throws {
        try database.execute(
            """
            UPDATE ai_parse_results SET adopted_normalized_title=?, adopted_type=?,
              adopted_date=?, updated_at=? WHERE id=?
            """,
            bindings: [
                title.map(SQLiteValue.text) ?? .null,
                type.map(SQLiteValue.text) ?? .null,
                date.map { .real($0.timeIntervalSince1970) } ?? .null,
                .real(at.timeIntervalSince1970), .text(id.uuidString)
            ]
        )
    }

    func addAudit(_ audit: AIConfirmationAuditRecord) throws {
        let correction = audit.correction.flatMap { try? JSONEncoder.iso8601.encode($0) }
        try database.execute(
            """
            INSERT INTO ai_confirmation_audit
              (id, parse_result_id, action, previous_state, new_state, correction_json, occurred_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(audit.id.uuidString), .text(audit.parseResultID.uuidString),
                .text(audit.action.rawValue), .text(audit.previousState.rawValue),
                .text(audit.newState.rawValue), correction.map(SQLiteValue.blob) ?? .null,
                .real(audit.occurredAt.timeIntervalSince1970)
            ]
        )
    }

    func audits(parseResultID: UUID) throws -> [AIConfirmationAuditRecord] {
        try database.query(
            "SELECT * FROM ai_confirmation_audit WHERE parse_result_id=? ORDER BY occurred_at, rowid",
            bindings: [.text(parseResultID.uuidString)]
        ).compactMap { row in
            guard let idText = row.string("id"), let id = UUID(uuidString: idText),
                  let actionRaw = row.string("action"), let action = AIConfirmationAction(rawValue: actionRaw),
                  let oldRaw = row.string("previous_state"), let old = AIConfirmationState(rawValue: oldRaw),
                  let newRaw = row.string("new_state"), let new = AIConfirmationState(rawValue: newRaw),
                  let timestamp = row.double("occurred_at") else { return nil }
            let correction = row.data("correction_json").flatMap {
                try? JSONDecoder.iso8601.decode(AIConfirmationCorrection.self, from: $0)
            }
            return AIConfirmationAuditRecord(
                id: id, parseResultID: parseResultID, action: action,
                previousState: old, newState: new, correction: correction,
                occurredAt: Date(timeIntervalSince1970: timestamp)
            )
        }
    }

    func auditCount(parseResultID: UUID) throws -> Int {
        try database.scalarInt(
            "SELECT COUNT(*) AS value FROM ai_confirmation_audit WHERE parse_result_id='\(parseResultID.uuidString)'"
        )
    }

    func applySuggestion(
        _ record: AIParseRecord, correction: AIConfirmationCorrection?, confirmedAt: Date,
        transitionSequence: Int
    ) throws {
        guard record.targetObjectType == "learning_task" else { return }
        let targetRows = try database.query(
            "SELECT * FROM learning_tasks WHERE id=?", bindings: [.text(record.targetObjectID)]
        )
        guard let target = targetRows.first else { throw AIParsingError.missingTarget }
        let type = correction == nil ? record.suggestedType : correction?.suggestedType
        let date = correction == nil ? record.suggestedDate : correction?.suggestedDate
        try database.execute(
            """
            INSERT INTO ai_applied_values
              (parse_result_id, previous_normalized_type, previous_suggested_complete_at,
               previous_suggestion_origin, previous_suggestion_confirmed_at, applied_at, restored_at)
            VALUES (?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(parse_result_id) DO UPDATE SET
              previous_normalized_type=excluded.previous_normalized_type,
              previous_suggested_complete_at=excluded.previous_suggested_complete_at,
              previous_suggestion_origin=excluded.previous_suggestion_origin,
              previous_suggestion_confirmed_at=excluded.previous_suggestion_confirmed_at,
              applied_at=excluded.applied_at, restored_at=NULL
            """,
            bindings: [
                .text(record.id.uuidString), target.string("normalized_type").map(SQLiteValue.text) ?? .null,
                target.double("suggested_complete_at").map(SQLiteValue.real) ?? .null,
                target.string("suggestion_origin").map(SQLiteValue.text) ?? .null,
                target.double("suggestion_confirmed_at").map(SQLiteValue.real) ?? .null,
                .real(confirmedAt.timeIntervalSince1970)
            ]
        )
        try database.execute(
            """
            UPDATE learning_tasks SET normalized_type=COALESCE(normalized_type, ?),
              suggestion_origin=CASE
                WHEN suggested_complete_at IS NULL AND ? IS NOT NULL THEN 'ai_inferred'
                ELSE suggestion_origin END,
              suggestion_confirmed_at=CASE
                WHEN suggested_complete_at IS NULL AND ? IS NOT NULL THEN ?
                ELSE suggestion_confirmed_at END,
              suggested_complete_at=COALESCE(suggested_complete_at, ?)
            WHERE id=?
            """,
            bindings: [
                type.map(SQLiteValue.text) ?? .null,
                date.map { .real($0.timeIntervalSince1970) } ?? .null,
                date.map { .real($0.timeIntervalSince1970) } ?? .null,
                .real(confirmedAt.timeIntervalSince1970),
                date.map { .real($0.timeIntervalSince1970) } ?? .null,
                .text(record.targetObjectID)
            ]
        )
        if date != nil, target.double("suggested_complete_at") == nil {
            let envelope = OutboxEnvelope.calendarReconcile(
                objectType: "learning_task", objectID: record.targetObjectID
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let payload = try encoder.encode(envelope)
            let timestamp = confirmedAt.timeIntervalSince1970
            try database.execute(
                """
                INSERT INTO outbox_work
                  (id, kind, deduplication_key, object_type, object_id, payload, state,
                   attempt_count, available_at, created_at, updated_at)
                VALUES (?, 'calendar', ?, 'learning_task', ?, ?, 'pending', 0, ?, ?, ?)
                ON CONFLICT(deduplication_key) DO NOTHING
                """,
                bindings: [
                    .text(UUID().uuidString),
                    .text(calendarDeduplicationKey(
                        record: record, transitionSequence: transitionSequence
                    )),
                    .text(record.targetObjectID), .blob(payload), .real(timestamp),
                    .real(timestamp), .real(timestamp)
                ]
            )
        }
    }

    func undoSuggestion(
        _ record: AIParseRecord, restoredAt: Date, transitionSequence: Int
    ) throws {
        guard record.targetObjectType == "learning_task" else { return }
        guard let applied = try database.query(
            "SELECT * FROM ai_applied_values WHERE parse_result_id=? AND restored_at IS NULL",
            bindings: [.text(record.id.uuidString)]
        ).first else { throw AIParsingError.invalidTransition }
        try database.execute(
            """
            UPDATE learning_tasks SET
              normalized_type=?, suggested_complete_at=?, suggestion_origin=?, suggestion_confirmed_at=?
            WHERE id=?
            """,
            bindings: [
                applied.string("previous_normalized_type").map(SQLiteValue.text) ?? .null,
                applied.double("previous_suggested_complete_at").map(SQLiteValue.real) ?? .null,
                applied.string("previous_suggestion_origin").map(SQLiteValue.text) ?? .null,
                applied.double("previous_suggestion_confirmed_at").map(SQLiteValue.real) ?? .null,
                .text(record.targetObjectID)
            ]
        )
        try database.execute(
            "UPDATE ai_applied_values SET restored_at=? WHERE parse_result_id=?",
            bindings: [.real(restoredAt.timeIntervalSince1970), .text(record.id.uuidString)]
        )
        try enqueueCalendarReconciliation(
            record: record, at: restoredAt, transitionSequence: transitionSequence
        )
    }

    private func enqueueCalendarReconciliation(
        record: AIParseRecord, at: Date, transitionSequence: Int
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = try encoder.encode(OutboxEnvelope.calendarReconcile(
            objectType: "learning_task", objectID: record.targetObjectID
        ))
        let timestamp = at.timeIntervalSince1970
        try database.execute(
            """
            INSERT INTO outbox_work
              (id, kind, deduplication_key, object_type, object_id, payload, state,
               attempt_count, available_at, created_at, updated_at)
            VALUES (?, 'calendar', ?, 'learning_task', ?, ?, 'pending', 0, ?, ?, ?)
            ON CONFLICT(deduplication_key) DO NOTHING
            """,
            bindings: [
                .text(UUID().uuidString),
                .text(calendarDeduplicationKey(
                    record: record, transitionSequence: transitionSequence
                )),
                .text(record.targetObjectID), .blob(payload), .real(timestamp),
                .real(timestamp), .real(timestamp)
            ]
        )
    }

    private func calendarDeduplicationKey(
        record: AIParseRecord, transitionSequence: Int
    ) -> String {
        "calendar:learning_task:\(record.targetObjectID):ai:\(record.id.uuidString.lowercased()):transition:\(transitionSequence)"
    }

    private func decode(_ row: SQLiteRow) -> AIParseRecord? {
        guard let idText = row.string("id"), let id = UUID(uuidString: idText),
              let rawText = row.string("raw_source_record_id"), let rawID = UUID(uuidString: rawText),
              let objectType = row.string("target_object_type"), let objectID = row.string("target_object_id"),
              let inputHash = row.string("input_hash"), let provider = row.string("provider"),
              let model = row.string("model"), let prompt = row.string("prompt_version"),
              let schema = row.string("schema_version"), let confidence = row.double("confidence"),
              let rationale = row.string("rationale"), let stateRaw = row.string("confirmation_state"),
              let state = AIConfirmationState(rawValue: stateRaw), let created = row.double("created_at")
        else { return nil }
        return AIParseRecord(
            id: id, rawSourceRecordID: rawID, targetObjectType: objectType, targetObjectID: objectID,
            inputHash: inputHash, provider: provider, model: model, promptVersion: prompt,
            schemaVersion: schema, suggestedType: row.string("suggested_type"),
            normalizedTitle: row.string("normalized_title"),
            officialDateEcho: row.double("official_date_echo").map(Date.init(timeIntervalSince1970:)),
            suggestedDate: row.double("suggested_date").map(Date.init(timeIntervalSince1970:)),
            relatedObjectIDs: strings(row.string("related_object_ids_json")),
            actionItems: strings(row.string("action_items_json")), confidence: confidence,
            rationale: rationale, hasConflict: row.int("has_conflict") == 1,
            changeSummary: row.string("change_summary") ?? "", confirmationState: state,
            failureCategory: row.string("failure_category"),
            adoptedNormalizedTitle: row.string("adopted_normalized_title"),
            adoptedType: row.string("adopted_type"),
            adoptedDate: row.double("adopted_date").map(Date.init(timeIntervalSince1970:)),
            sourceSummary: row.string("source_summary") ?? "",
            sourceURL: row.string("source_url"),
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? created)
        )
    }

    private func json(_ strings: [String]) -> String {
        String(data: (try? JSONEncoder().encode(strings)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    private func strings(_ value: String?) -> [String] {
        guard let data = value?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
