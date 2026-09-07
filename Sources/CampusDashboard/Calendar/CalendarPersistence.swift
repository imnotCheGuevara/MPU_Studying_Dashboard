import Foundation

final class CalendarPersistence: @unchecked Sendable {
    private let database: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.database = database
    }

    func identity() throws -> ManagedCalendarIdentity? {
        guard let row = try database.query(
            "SELECT * FROM managed_calendar_identity WHERE singleton_key = 1"
        ).first,
        let internalID = row.string("internal_id").flatMap(UUID.init(uuidString:)),
        let calendarIdentifier = row.string("calendar_identifier"),
        let sourceIdentifier = row.string("source_identifier"),
        let sourceKindValue = row.string("source_kind"),
        let sourceKind = CalendarSourceKind(rawValue: sourceKindValue),
        let sourceTitle = row.string("source_title"),
        let calendarTitle = row.string("calendar_title"),
        let selectionValue = row.string("selection_kind"),
        let selectionKind = ManagedCalendarSelectionKind(rawValue: selectionValue),
        let ownershipMarker = row.string("ownership_marker"),
        let validationValue = row.string("validation_state"),
        let validationState = ManagedCalendarValidationState(rawValue: validationValue)
        else { return nil }
        return ManagedCalendarIdentity(
            internalID: internalID,
            calendarIdentifier: calendarIdentifier,
            sourceIdentifier: sourceIdentifier,
            sourceKind: sourceKind,
            sourceTitle: sourceTitle,
            calendarTitle: calendarTitle,
            selectionKind: selectionKind,
            ownershipMarker: ownershipMarker,
            validationState: validationState,
            lastVerifiedAt: row.double("last_verified_at").map(Date.init(timeIntervalSince1970:))
        )
    }

    func saveIdentity(_ identity: ManagedCalendarIdentity) throws {
        try database.execute(
            """
            INSERT INTO managed_calendar_identity
              (singleton_key, internal_id, calendar_identifier, source_identifier, source_kind,
               source_title, calendar_title, selection_kind, ownership_marker, validation_state,
               last_verified_at)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(singleton_key) DO UPDATE SET
              internal_id=excluded.internal_id, calendar_identifier=excluded.calendar_identifier,
              source_identifier=excluded.source_identifier, source_kind=excluded.source_kind,
              source_title=excluded.source_title, calendar_title=excluded.calendar_title,
              selection_kind=excluded.selection_kind, ownership_marker=excluded.ownership_marker,
              validation_state=excluded.validation_state, last_verified_at=excluded.last_verified_at
            """,
            bindings: [
                .text(identity.internalID.uuidString), .text(identity.calendarIdentifier),
                .text(identity.sourceIdentifier), .text(identity.sourceKind.rawValue),
                .text(identity.sourceTitle), .text(identity.calendarTitle),
                .text(identity.selectionKind.rawValue), .text(identity.ownershipMarker),
                .text(identity.validationState.rawValue),
                identity.lastVerifiedAt.map { .real($0.timeIntervalSince1970) } ?? .null
            ]
        )
    }

    func updateValidation(_ state: ManagedCalendarValidationState, at date: Date?) throws {
        try database.execute(
            "UPDATE managed_calendar_identity SET validation_state = ?, last_verified_at = ? WHERE singleton_key = 1",
            bindings: [.text(state.rawValue), date.map { .real($0.timeIntervalSince1970) } ?? .null]
        )
    }

    func binding(objectType: String, objectID: String) throws -> CalendarBindingRecord? {
        try database.query(
            "SELECT * FROM calendar_bindings WHERE object_type = ? AND object_id = ?",
            bindings: [.text(objectType), .text(objectID)]
        ).compactMap(decodeBinding).first
    }

    func activeBindings() throws -> [CalendarBindingRecord] {
        try database.query(
            "SELECT * FROM calendar_bindings WHERE sync_state != 'removed' ORDER BY object_type, object_id"
        ).compactMap(decodeBinding)
    }

    func saveBinding(_ binding: CalendarBindingRecord) throws {
        try database.execute(
            """
            INSERT INTO calendar_bindings
              (id, object_type, object_id, event_identifier, external_event_identifier,
               ownership_marker, calendar_identifier, calendar_source_identifier, sync_state,
               last_verified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(object_type, object_id) DO UPDATE SET
              event_identifier=excluded.event_identifier,
              external_event_identifier=excluded.external_event_identifier,
              ownership_marker=excluded.ownership_marker,
              calendar_identifier=excluded.calendar_identifier,
              calendar_source_identifier=excluded.calendar_source_identifier,
              sync_state=excluded.sync_state,
              last_verified_at=excluded.last_verified_at
            """,
            bindings: [
                .text(binding.id.uuidString), .text(binding.objectType), .text(binding.objectID),
                .text(binding.eventIdentifier), binding.externalEventIdentifier.map(SQLiteValue.text) ?? .null,
                .text(binding.ownershipMarker), .text(binding.calendarIdentifier),
                .text(binding.calendarSourceIdentifier), .text(binding.syncState),
                binding.lastVerifiedAt.map { .real($0.timeIntervalSince1970) } ?? .null
            ]
        )
    }

    func markBindingRemoved(_ binding: CalendarBindingRecord, at date: Date) throws {
        try database.execute(
            "UPDATE calendar_bindings SET sync_state = 'removed', last_verified_at = ? WHERE id = ?",
            bindings: [.real(date.timeIntervalSince1970), .text(binding.id.uuidString)]
        )
    }

    private func decodeBinding(_ row: SQLiteRow) -> CalendarBindingRecord? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
              let objectType = row.string("object_type"), let objectID = row.string("object_id"),
              let eventIdentifier = row.string("event_identifier"),
              let ownershipMarker = row.string("ownership_marker"),
              let calendarIdentifier = row.string("calendar_identifier"),
              let sourceIdentifier = row.string("calendar_source_identifier"),
              let syncState = row.string("sync_state")
        else { return nil }
        return CalendarBindingRecord(
            id: id, objectType: objectType, objectID: objectID,
            eventIdentifier: eventIdentifier,
            externalEventIdentifier: row.string("external_event_identifier"),
            ownershipMarker: ownershipMarker, calendarIdentifier: calendarIdentifier,
            calendarSourceIdentifier: sourceIdentifier, syncState: syncState,
            lastVerifiedAt: row.double("last_verified_at").map(Date.init(timeIntervalSince1970:))
        )
    }
}
