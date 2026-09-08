import Foundation

actor CampusCalendarService: CalendarService {
    private let database: SQLiteDatabase
    private let persistence: CalendarPersistence
    private let store: any CalendarEventStore
    private let clock: any Clock
    private let idGenerator: any IDGenerator

    init(
        database: SQLiteDatabase,
        store: any CalendarEventStore,
        clock: any Clock = SystemClock(),
        idGenerator: any IDGenerator = SystemIDGenerator()
    ) {
        self.database = database
        self.persistence = CalendarPersistence(database: database)
        self.store = store
        self.clock = clock
        self.idGenerator = idGenerator
    }

    func authorizationStatus() async -> CalendarAccessStatus {
        await store.authorizationStatus()
    }

    /// This is the only API that prompts for Calendar access. It is intended to
    /// be called from the user's explicit "Enable Calendar sync" action.
    func requestAccessFromUserAction() async throws -> Bool {
        try await store.requestFullAccess()
    }

    func availableSources() async throws -> [CalendarSourceDescriptor] {
        try await requireFullAccess()
        return await store.sources()
    }

    func availableWritableCalendars() async throws -> [CalendarDescriptor] {
        try await requireFullAccess()
        return await store.calendars().filter(\.allowsContentModifications)
    }

    @discardableResult
    func createDedicatedCalendar(
        sourceIdentifier: String,
        title: String = "Campus Dashboard"
    ) async throws -> ManagedCalendarIdentity {
        try await requireFullAccess()
        let sources = await store.sources()
        guard let source = sources.first(where: { $0.identifier == sourceIdentifier }) else {
            throw CampusCalendarError.invalidSelection
        }
        let calendar = try await store.createCalendar(title: title, sourceIdentifier: sourceIdentifier)
        guard calendar.allowsContentModifications, calendar.source.identifier == source.identifier else {
            throw CampusCalendarError.calendarUnwritable
        }
        return try persistIdentity(calendar: calendar, selectionKind: .appCreated)
    }

    @discardableResult
    func selectDedicatedCalendar(calendarIdentifier: String) async throws -> ManagedCalendarIdentity {
        try await requireFullAccess()
        guard let calendar = await store.calendars().first(where: { $0.identifier == calendarIdentifier }) else {
            throw CampusCalendarError.invalidSelection
        }
        guard calendar.allowsContentModifications else { throw CampusCalendarError.calendarUnwritable }
        return try persistIdentity(calendar: calendar, selectionKind: .userSelected)
    }

    /// Identifier loss is deliberately never repaired by title alone. The
    /// returned candidates are informational; recovery requires an explicit
    /// call to `selectDedicatedCalendar`.
    func recoveryCandidates() async throws -> [CalendarDescriptor] {
        try await requireFullAccess()
        guard let identity = try persistence.identity() else { return [] }
        return await store.calendars().filter {
            $0.source.identifier == identity.sourceIdentifier && $0.title == identity.calendarTitle
        }
    }

    @discardableResult
    func validateDedicatedCalendar() async throws -> ManagedCalendarValidationState {
        guard let identity = try persistence.identity() else {
            throw CampusCalendarError.calendarNotConfigured
        }
        let authorization = await store.authorizationStatus()
        guard authorization == .fullAccess else {
            let state: ManagedCalendarValidationState = authorization == .notDetermined
                ? .permissionDenied : .permissionRevoked
            try persistence.updateValidation(state, at: nil)
            return state
        }
        let calendars = await store.calendars()
        guard let calendar = calendars.first(where: { $0.identifier == identity.calendarIdentifier }) else {
            let candidates = calendars.filter {
                $0.source.identifier == identity.sourceIdentifier && $0.title == identity.calendarTitle
            }
            let state: ManagedCalendarValidationState = candidates.count > 1 ? .ambiguous : .missing
            try persistence.updateValidation(state, at: nil)
            return state
        }
        guard calendar.source.identifier == identity.sourceIdentifier else {
            try persistence.updateValidation(.sourceChanged, at: nil)
            return .sourceChanged
        }
        guard calendar.allowsContentModifications else {
            try persistence.updateValidation(.unwritable, at: nil)
            return .unwritable
        }
        try persistence.updateValidation(.valid, at: clock.now)
        return .valid
    }

    func configuredIdentity() throws -> ManagedCalendarIdentity? {
        try persistence.identity()
    }

    /// Read-only preview for the explicit review gate. It never touches EventKit.
    func previewAcademicSignal(signalID: UUID) async throws -> CalendarChangePreview {
        // Preview remains available before Calendar permission/configuration so
        // the user can review the exact operation without granting access.
        let calendarTitle = try persistence.identity()?.calendarTitle ?? "Campus Dashboard"
        guard let row = try database.query(
            """
            SELECT s.*,a.title AS announcement_title,c.name AS course_name,c.code AS course_code,
                   m.starts_at AS meeting_start,m.ends_at AS meeting_end,
                   m.is_all_day AS meeting_is_all_day,m.source_state AS meeting_state
            FROM academic_signals s JOIN announcements a ON a.id=s.announcement_id
            LEFT JOIN courses c ON c.id=COALESCE(s.course_id,a.course_id)
            LEFT JOIN course_meetings m ON m.id=s.target_meeting_id WHERE s.id=?
            """, bindings: [.text(signalID.uuidString)]
        ).first else { throw CampusCalendarError.objectMissing }

        let category = AcademicSignalCategory(rawValue: row.string("adopted_category")
            ?? row.string("category") ?? "other") ?? .other
        let targetMeetingID = row.string("target_meeting_id").flatMap(UUID.init(uuidString:))
        if category == .courseScheduleChange {
            guard row.int("is_active") == 1,
                  row.string("confirmation_state") == AcademicSignalConfirmationState.pending.rawValue,
                  row.string("audience_resolution") == AcademicAudienceResolution.resolved.rawValue,
                  row.string("meeting_state") == "active",
                  let targetMeetingID,
                  let courseID = row.string("course_id").flatMap(UUID.init(uuidString:)),
                  let date = row.double("adopted_date").map(Date.init(timeIntervalSince1970:))
                    ?? row.double("inferred_date").map(Date.init(timeIntervalSince1970:)),
                  try AcademicScheduleTargetResolver.revalidate(
                    database: database, courseID: courseID, date: date,
                    isAllDay: row.int("adopted_is_all_day").map { $0 == 1 }
                        ?? (row.int("is_all_day") == 1),
                    dateRole: row.string("schedule_date_role")
                        .flatMap(AcademicScheduleDateRole.init(rawValue:)),
                    affectedSection: row.string("affected_section"),
                    proposedTarget: row.string("proposed_target_meeting_id")
                        .flatMap(UUID.init(uuidString:)),
                    expectedTarget: targetMeetingID
                  ) == targetMeetingID else {
                throw CampusCalendarError.unconfirmedInferredDate
            }
        }
        let words = ((row.string("evidence") ?? "") + " "
            + (row.string("adopted_key_requirement") ?? row.string("key_requirement") ?? "")).lowercased()
        let isCancellation = category == .courseScheduleChange
            && ["cancel", "取消", "停课"].contains(where: words.contains)
        let semantic: AcademicEventSemantic = switch category {
        case .courseScheduleChange: isCancellation ? .courseCancellation : .makeupOrChange
        case .makeupClass: .makeupOrChange
        case .assignmentDeadline: .assignmentDeadline
        case .examTime: .exam
        case .other: .assignmentDeadline
        }
        let targetMeeting = targetMeetingID?.uuidString
        let objectType = targetMeeting == nil ? "academic_signal" : "course_meeting"
        let objectID = targetMeeting ?? signalID.uuidString
        let binding = try persistence.binding(objectType: objectType, objectID: objectID)
        let operation: CalendarPreviewOperation = isCancellation ? .cancel : (binding == nil ? .create : .update)
        let start = category == .courseScheduleChange
            ? row.double("meeting_start").map(Date.init(timeIntervalSince1970:))
            : row.double("adopted_date").map(Date.init(timeIntervalSince1970:))
                ?? row.double("inferred_date").map(Date.init(timeIntervalSince1970:))
        let existingMeetingStart = row.double("meeting_start").map(Date.init(timeIntervalSince1970:))
        let existingMeetingEnd = row.double("meeting_end").map(Date.init(timeIntervalSince1970:))
        let duration: TimeInterval
        if let existingMeetingStart, let existingMeetingEnd {
            duration = existingMeetingEnd.timeIntervalSince(existingMeetingStart)
        } else {
            duration = row.int("adopted_is_all_day") == 1
                ? 86_400 : (category == .makeupClass ? 10_800 : 1_800)
        }
        let marker = switch semantic {
        case .courseCancellation: "[CANCELLED]"
        case .makeupOrChange: category == .makeupClass ? "[MAKEUP]" : "[CHANGED]"
        case .assignmentDeadline: "[DEADLINE]"
        case .exam: "[EXAM]"
        }
        let course = [row.string("course_code"), row.string("course_name")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return CalendarChangePreview(
            id: UUID(), signalID: signalID, targetMeetingID: targetMeetingID,
            signalUpdatedAt: Date(timeIntervalSince1970: row.double("updated_at") ?? 0),
            operation: operation,
            calendarTitle: calendarTitle,
            courseTitle: course.isEmpty ? "Unassigned course" : course,
            semantic: semantic, startsAt: start, endsAt: start?.addingTimeInterval(duration),
            isAllDay: category == .courseScheduleChange
                ? row.int("meeting_is_all_day") == 1
                : row.int("adopted_is_all_day").map { $0 == 1 }
                    ?? (row.int("is_all_day") == 1),
            affectedBoundEvent: binding == nil
                ? (category == .makeupClass
                    ? "New app-owned make-up event"
                    : "Exact SIweb meeting (not yet bound)")
                : "Exact app-owned SIweb meeting event",
            undoEffect: binding == nil
                ? "Undo removes the app-owned event created from this confirmation."
                : "Undo restores the prior app-owned bound event on reconciliation.",
            displayMarker: marker
        )
    }

    /// Reconciles a reviewed signal only after its local confirmation state is persisted.
    /// Targeted schedule changes reuse the app-owned meeting binding; standalone
    /// deadlines and exams use their own app-owned signal binding. Repeated calls
    /// converge through the normal binding-aware Calendar path.
    @discardableResult
    func reconcileAcademicSignal(signalID: UUID) async throws -> CalendarCommandResult {
        guard let row = try database.query(
            "SELECT * FROM academic_signals WHERE id=? AND is_active=1",
            bindings: [.text(signalID.uuidString)]
        ).first else { throw CampusCalendarError.objectMissing }
        let category = AcademicSignalCategory(rawValue:
            row.string("adopted_category") ?? row.string("category") ?? "other"
        ) ?? .other
        if category == .courseScheduleChange {
            // Schedule changes never own standalone Calendar events. Clean up a
            // legacy one before reconciling only the exact SIweb meeting target.
            let cleanupResult = try await apply([
                .removeBoundEvent(objectType: "academic_signal", objectID: signalID.uuidString)
            ]).first
            let state = row.string("confirmation_state") ?? "pending"
            guard ["confirmed", "corrected"].contains(state),
                  row.string("audience_resolution") == AcademicAudienceResolution.resolved.rawValue,
                  let meetingID = row.string("target_meeting_id"),
                  let meetingUUID = UUID(uuidString: meetingID),
                  let courseID = row.string("course_id").flatMap(UUID.init(uuidString:)),
                  let date = row.double("adopted_date").map(Date.init(timeIntervalSince1970:))
                    ?? row.double("inferred_date").map(Date.init(timeIntervalSince1970:)),
                  try AcademicScheduleTargetResolver.revalidate(
                    database: database, courseID: courseID, date: date,
                    isAllDay: row.int("adopted_is_all_day").map { $0 == 1 }
                        ?? (row.int("is_all_day") == 1),
                    dateRole: row.string("schedule_date_role")
                        .flatMap(AcademicScheduleDateRole.init(rawValue:)),
                    affectedSection: row.string("affected_section"),
                    proposedTarget: row.string("proposed_target_meeting_id")
                        .flatMap(UUID.init(uuidString:)),
                    expectedTarget: meetingUUID
                  ) == meetingUUID else {
                guard let result = cleanupResult else { throw CampusCalendarError.objectMissing }
                return result
            }
            guard let result = try await apply([
                .upsert(objectType: "course_meeting", objectID: meetingID)
            ]).first else { throw CampusCalendarError.objectMissing }
            return result
        }
        let state = row.string("confirmation_state") ?? "pending"
        let command: CalendarCommand = ["confirmed", "corrected"].contains(state)
            ? .upsert(objectType: "academic_signal", objectID: signalID.uuidString)
            : .removeBoundEvent(objectType: "academic_signal", objectID: signalID.uuidString)
        guard let result = try await apply([command]).first else {
            throw CampusCalendarError.objectMissing
        }
        return result
    }

    /// Produces a cleanup list only after revalidating the dedicated calendar,
    /// binding identity, exact ownership marker, and currently stored event.
    /// Invalid or unrecoverable rows are deliberately excluded.
    func cleanupPreview() async throws -> [CalendarCleanupItem] {
        let identity = try await requireValidIdentity()
        var items: [CalendarCleanupItem] = []
        for binding in try persistence.activeBindings() {
            let marker = eventMarker(
                identity: identity, objectType: binding.objectType, objectID: binding.objectID
            )
            guard let event = try? await resolveBoundEvent(
                binding, marker: marker, identity: identity, markerFallbackDate: nil
            ) else { continue }
            items.append(CalendarCleanupItem(
                id: binding.id, objectType: binding.objectType, objectID: binding.objectID,
                title: event.title, startsAt: event.startsAt
            ))
        }
        return items
    }

    /// Deletes only items explicitly selected from a preview. Every binding is
    /// looked up and validated again, so a stale preview cannot broaden scope.
    @discardableResult
    func cleanupPreviewedEvents(bindingIDs: Set<UUID>) async throws -> Int {
        guard !bindingIDs.isEmpty else { return 0 }
        let candidates = try persistence.activeBindings().filter { bindingIDs.contains($0.id) }
        var removed = 0
        for binding in candidates {
            _ = try await remove(
                objectType: binding.objectType, objectID: binding.objectID,
                identity: try await requireValidIdentity()
            )
            removed += 1
        }
        return removed
    }

    func apply(_ commands: [CalendarCommand]) async throws -> [CalendarCommandResult] {
        let identity = try await requireValidIdentity()
        var results: [CalendarCommandResult] = []
        for command in commands {
            switch command {
            case .upsert(let objectType, let objectID):
                let payload = try eventDraft(objectType: objectType, objectID: objectID, identity: identity)
                if payload.isCancelled {
                    results.append(try await remove(objectType: objectType, objectID: objectID, identity: identity))
                } else {
                    results.append(try await upsert(
                        draft: payload.draft, objectType: objectType, objectID: objectID, identity: identity
                    ))
                }
            case .removeBoundEvent(let objectType, let objectID):
                results.append(try await remove(objectType: objectType, objectID: objectID, identity: identity))
            }
        }
        return results
    }

    private func persistIdentity(
        calendar: CalendarDescriptor,
        selectionKind: ManagedCalendarSelectionKind
    ) throws -> ManagedCalendarIdentity {
        let internalID = idGenerator.next()
        let identity = ManagedCalendarIdentity(
            internalID: internalID,
            calendarIdentifier: calendar.identifier,
            sourceIdentifier: calendar.source.identifier,
            sourceKind: calendar.source.kind,
            sourceTitle: calendar.source.title,
            calendarTitle: calendar.title,
            selectionKind: selectionKind,
            ownershipMarker: "campus-dashboard-calendar:\(internalID.uuidString.lowercased())",
            validationState: .valid,
            lastVerifiedAt: clock.now
        )
        try persistence.saveIdentity(identity)
        return identity
    }

    private func requireFullAccess() async throws {
        switch await store.authorizationStatus() {
        case .fullAccess: return
        case .notDetermined: throw CampusCalendarError.permissionNotRequested
        case .denied, .restricted, .writeOnly: throw CampusCalendarError.permissionDenied
        }
    }

    private func requireValidIdentity() async throws -> ManagedCalendarIdentity {
        guard let identity = try persistence.identity() else {
            throw CampusCalendarError.calendarNotConfigured
        }
        switch await store.authorizationStatus() {
        case .fullAccess: break
        case .notDetermined: throw CampusCalendarError.permissionNotRequested
        case .denied, .restricted, .writeOnly: throw CampusCalendarError.permissionRevoked
        }
        switch try await validateDedicatedCalendar() {
        case .valid: return try persistence.identity() ?? identity
        case .permissionDenied: throw CampusCalendarError.permissionDenied
        case .permissionRevoked: throw CampusCalendarError.permissionRevoked
        case .missing: throw CampusCalendarError.calendarMissing
        case .ambiguous: throw CampusCalendarError.ambiguousCalendarCandidates
        case .sourceChanged: throw CampusCalendarError.sourceChanged
        case .unwritable: throw CampusCalendarError.calendarUnwritable
        }
    }

    private func upsert(
        draft: CalendarEventDraft,
        objectType: String,
        objectID: String,
        identity: ManagedCalendarIdentity
    ) async throws -> CalendarCommandResult {
        let marker = eventMarker(identity: identity, objectType: objectType, objectID: objectID)
        let binding = try persistence.binding(objectType: objectType, objectID: objectID)
        var existingIdentifier: String?
        if let binding, binding.syncState != "removed" {
            let event = try await resolveBoundEvent(
                binding, marker: marker, identity: identity, markerFallbackDate: draft.startsAt
            )
            existingIdentifier = event.identifier
        } else {
            let candidates = await store.events(
                calendarIdentifier: identity.calendarIdentifier,
                around: draft.startsAt,
                ownershipMarker: marker
            )
            guard candidates.count <= 1 else { throw CampusCalendarError.ambiguousOwnedEvents }
            existingIdentifier = candidates.first?.identifier
        }

        let ownedDraft = CalendarEventDraft(
            title: draft.title, startsAt: draft.startsAt, endsAt: draft.endsAt,
            isAllDay: draft.isAllDay, location: draft.location, sourceURL: draft.sourceURL,
            ownershipMarker: marker
        )
        let saved = try await store.saveEvent(
            ownedDraft,
            calendarIdentifier: identity.calendarIdentifier,
            existingEventIdentifier: existingIdentifier
        )
        guard saved.calendarIdentifier == identity.calendarIdentifier,
              saved.calendarSourceIdentifier == identity.sourceIdentifier,
              saved.ownershipMarker == marker else { throw CampusCalendarError.staleBinding }
        let record = CalendarBindingRecord(
            id: binding?.id ?? idGenerator.next(), objectType: objectType, objectID: objectID,
            eventIdentifier: saved.identifier, externalEventIdentifier: saved.externalIdentifier,
            ownershipMarker: marker, calendarIdentifier: identity.calendarIdentifier,
            calendarSourceIdentifier: identity.sourceIdentifier, syncState: "synced",
            lastVerifiedAt: clock.now
        )
        try persistence.saveBinding(record)
        return CalendarCommandResult(objectID: objectID, bindingIdentifier: record.id.uuidString)
    }

    private func remove(
        objectType: String,
        objectID: String,
        identity: ManagedCalendarIdentity
    ) async throws -> CalendarCommandResult {
        guard let binding = try persistence.binding(objectType: objectType, objectID: objectID) else {
            return CalendarCommandResult(objectID: objectID, bindingIdentifier: nil)
        }
        if binding.syncState == "removed" {
            return CalendarCommandResult(objectID: objectID, bindingIdentifier: binding.id.uuidString)
        }
        let marker = eventMarker(identity: identity, objectType: objectType, objectID: objectID)
        let event = try await resolveBoundEvent(
            binding, marker: marker, identity: identity, markerFallbackDate: nil
        )
        try await store.removeEvent(
            identifier: event.identifier,
            calendarIdentifier: identity.calendarIdentifier,
            calendarSourceIdentifier: identity.sourceIdentifier,
            ownershipMarker: marker,
            externalIdentifier: event.externalIdentifier
        )
        try persistence.markBindingRemoved(binding, at: clock.now)
        return CalendarCommandResult(objectID: objectID, bindingIdentifier: binding.id.uuidString)
    }

    private func validate(
        binding: CalendarBindingRecord,
        marker: String,
        identity: ManagedCalendarIdentity
    ) throws {
        guard binding.calendarIdentifier == identity.calendarIdentifier,
              binding.calendarSourceIdentifier == identity.sourceIdentifier,
              binding.ownershipMarker == marker else { throw CampusCalendarError.staleBinding }
    }

    private func resolveBoundEvent(
        _ binding: CalendarBindingRecord,
        marker: String,
        identity: ManagedCalendarIdentity,
        markerFallbackDate: Date?
    ) async throws -> CalendarStoredEvent {
        try validate(binding: binding, marker: marker, identity: identity)
        if let event = await store.event(identifier: binding.eventIdentifier) {
            try validate(
                event: event,
                expectedExternalIdentifier: binding.externalEventIdentifier,
                marker: marker,
                identity: identity
            )
            return event
        }

        let recovered: CalendarStoredEvent
        if let externalIdentifier = binding.externalEventIdentifier, !externalIdentifier.isEmpty {
            let candidates = await store.events(
                externalIdentifier: externalIdentifier,
                calendarIdentifier: identity.calendarIdentifier
            )
            guard candidates.count <= 1 else { throw CampusCalendarError.ambiguousExternalIdentifier }
            guard let candidate = candidates.first else { throw CampusCalendarError.eventRecoveryUnavailable }
            try validate(
                event: candidate,
                expectedExternalIdentifier: externalIdentifier,
                marker: marker,
                identity: identity
            )
            recovered = candidate
        } else if let markerFallbackDate {
            let candidates = await store.events(
                calendarIdentifier: identity.calendarIdentifier,
                around: markerFallbackDate,
                ownershipMarker: marker
            )
            guard candidates.count <= 1 else { throw CampusCalendarError.ambiguousOwnedEvents }
            guard let candidate = candidates.first else { throw CampusCalendarError.eventRecoveryUnavailable }
            try validate(
                event: candidate,
                expectedExternalIdentifier: nil,
                marker: marker,
                identity: identity
            )
            recovered = candidate
        } else {
            throw CampusCalendarError.eventRecoveryUnavailable
        }

        var updated = binding
        updated.eventIdentifier = recovered.identifier
        updated.externalEventIdentifier = recovered.externalIdentifier
        updated.lastVerifiedAt = clock.now
        try persistence.saveBinding(updated)
        return recovered
    }

    private func validate(
        event: CalendarStoredEvent,
        expectedExternalIdentifier: String?,
        marker: String,
        identity: ManagedCalendarIdentity
    ) throws {
        guard event.calendarIdentifier == identity.calendarIdentifier,
              event.calendarSourceIdentifier == identity.sourceIdentifier,
              event.ownershipMarker == marker else { throw CampusCalendarError.staleBinding }
        if let expectedExternalIdentifier {
            guard event.externalIdentifier == expectedExternalIdentifier else {
                throw CampusCalendarError.staleBinding
            }
        }
    }

    private func eventMarker(
        identity: ManagedCalendarIdentity,
        objectType: String,
        objectID: String
    ) -> String {
        "\(identity.ownershipMarker):\(objectType):\(objectID)"
    }

    private struct EventPayload {
        let draft: CalendarEventDraft
        let isCancelled: Bool
    }

    private func eventDraft(
        objectType: String,
        objectID: String,
        identity: ManagedCalendarIdentity
    ) throws -> EventPayload {
        switch objectType {
        case "course_meeting": return try meetingDraft(objectID: objectID, identity: identity)
        case "learning_task": return try taskDraft(objectID: objectID, identity: identity)
        case "academic_signal": return try academicSignalDraft(objectID: objectID, identity: identity)
        default: throw CampusCalendarError.unsupportedObjectType
        }
    }

    private func meetingDraft(objectID: String, identity: ManagedCalendarIdentity) throws -> EventPayload {
        guard let row = try database.query(
            """
            SELECT m.*, c.name AS course_name, c.code AS course_code, c.source_url AS course_url
            FROM course_meetings m JOIN courses c ON c.id = m.course_id WHERE m.id = ?
            """,
            bindings: [.text(objectID)]
        ).first,
        let startsAt = row.double("starts_at").map(Date.init(timeIntervalSince1970:)),
        let endsAt = row.double("ends_at").map(Date.init(timeIntervalSince1970:)),
        let courseName = row.string("course_name"), let sourceState = row.string("source_state")
        else { throw CampusCalendarError.objectMissing }
        let code = row.string("course_code") ?? ""
        var title = code.isEmpty ? courseName : "\(code) · \(courseName)"
        var effectiveStart = startsAt
        var effectiveEnd = endsAt
        let changes = try database.query(
            """
            SELECT s.*,a.source_url AS announcement_url FROM academic_signals s
            JOIN announcements a ON a.id=s.announcement_id
            WHERE s.target_meeting_id=? AND s.is_active=1
              AND s.confirmation_state IN ('confirmed','corrected')
              AND s.audience_resolution='resolved'
              AND COALESCE(s.adopted_category,s.category)='course_schedule_change'
            ORDER BY s.updated_at DESC
            """, bindings: [.text(objectID)]
        )
        var change: SQLiteRow?
        for candidate in changes {
            guard let meetingID = UUID(uuidString: objectID),
                  let courseID = candidate.string("course_id").flatMap(UUID.init(uuidString:)),
                  let date = candidate.double("adopted_date").map(Date.init(timeIntervalSince1970:))
                    ?? candidate.double("inferred_date").map(Date.init(timeIntervalSince1970:)),
                  try AcademicScheduleTargetResolver.revalidate(
                    database: database, courseID: courseID, date: date,
                    isAllDay: candidate.int("adopted_is_all_day").map { $0 == 1 }
                        ?? (candidate.int("is_all_day") == 1),
                    dateRole: candidate.string("schedule_date_role")
                        .flatMap(AcademicScheduleDateRole.init(rawValue:)),
                    affectedSection: candidate.string("affected_section"),
                    proposedTarget: candidate.string("proposed_target_meeting_id")
                        .flatMap(UUID.init(uuidString:)),
                    expectedTarget: meetingID
                  ) != nil else { continue }
            change = candidate
            break
        }
        var signalCancelled = false
        if let change {
            let words = ((change.string("evidence") ?? "") + " "
                + (change.string("adopted_key_requirement") ?? change.string("key_requirement") ?? "")).lowercased()
            let cancelled = ["cancel", "取消", "停课"].contains { words.contains($0) }
            if cancelled {
                title = "[CANCELLED] · \(title)"
                signalCancelled = true
            }
            else if let adopted = change.double("adopted_date").map(Date.init(timeIntervalSince1970:)) {
                effectiveStart = adopted
                effectiveEnd = adopted.addingTimeInterval(endsAt.timeIntervalSince(startsAt))
                title = "[CHANGED] · \(title)"
            }
        }
        let draft = CalendarEventDraft(
            title: title, startsAt: effectiveStart, endsAt: effectiveEnd,
            isAllDay: row.int("is_all_day") == 1, location: row.string("location"),
            sourceURL: row.string("course_url").flatMap(URL.init(string:)), ownershipMarker: ""
        )
        return EventPayload(draft: draft, isCancelled: sourceState == "cancelled" || signalCancelled)
    }

    private func academicSignalDraft(objectID: String, identity: ManagedCalendarIdentity) throws -> EventPayload {
        guard let row = try database.query(
            """
            SELECT s.*,a.title AS announcement_title,a.source_url,c.code AS course_code
            FROM academic_signals s JOIN announcements a ON a.id=s.announcement_id
            LEFT JOIN courses c ON c.id=COALESCE(s.course_id,a.course_id) WHERE s.id=?
            """, bindings: [.text(objectID)]
        ).first else { throw CampusCalendarError.objectMissing }
        let state = row.string("confirmation_state") ?? "pending"
        guard ["confirmed", "corrected"].contains(state),
              let start = row.double("adopted_date").map(Date.init(timeIntervalSince1970:))
                ?? row.double("inferred_date").map(Date.init(timeIntervalSince1970:)) else {
            throw CampusCalendarError.unconfirmedInferredDate
        }
        let category = row.string("adopted_category") ?? row.string("category") ?? "other"
        guard category != AcademicSignalCategory.courseScheduleChange.rawValue else {
            throw CampusCalendarError.unconfirmedInferredDate
        }
        let marker = switch AcademicSignalCategory(rawValue: category) {
        case .examTime: "[EXAM]"
        case .makeupClass: "[MAKEUP]"
        default: "[DEADLINE]"
        }
        let rawTitle = row.string("announcement_title") ?? row.string("adopted_key_requirement") ?? "Academic update"
        let code = row.string("course_code") ?? ""
        let title = [marker, code, rawTitle].filter { !$0.isEmpty }.joined(separator: " · ")
        let allDay = row.int("adopted_is_all_day") == 1
        let duration: TimeInterval = allDay ? 86_400
            : (category == AcademicSignalCategory.makeupClass.rawValue ? 10_800 : 1_800)
        return EventPayload(draft: .init(title: title, startsAt: start,
            endsAt: start.addingTimeInterval(duration), isAllDay: allDay,
            location: nil, sourceURL: row.string("source_url").flatMap(URL.init(string:)), ownershipMarker: ""),
            isCancelled: false)
    }

    private func taskDraft(objectID: String, identity: ManagedCalendarIdentity) throws -> EventPayload {
        guard let row = try database.query(
            """
            SELECT t.*, c.name AS course_name, c.code AS course_code
            FROM learning_tasks t LEFT JOIN courses c ON c.id = t.course_id WHERE t.id = ?
            """,
            bindings: [.text(objectID)]
        ).first,
        let title = row.string("title"), let sourceState = row.string("source_state")
        else { throw CampusCalendarError.objectMissing }

        let officialDate = row.double("official_due_at").map(Date.init(timeIntervalSince1970:))
        let suggestedDate = row.double("suggested_complete_at").map(Date.init(timeIntervalSince1970:))
        let selectedDate: Date
        let isAllDay: Bool
        if let officialDate {
            selectedDate = officialDate
            isAllDay = row.int("official_due_is_all_day") == 1
        } else if let suggestedDate {
            guard row.double("suggestion_confirmed_at") != nil else {
                throw CampusCalendarError.unconfirmedInferredDate
            }
            selectedDate = suggestedDate
            isAllDay = false
        } else {
            throw CampusCalendarError.ineligibleDate
        }
        let courseCode = row.string("course_code") ?? ""
        let eventTitle = courseCode.isEmpty ? title : "\(courseCode) · \(title)"
        let end = selectedDate.addingTimeInterval(isAllDay ? 86_400 : 1_800)
        return EventPayload(
            draft: CalendarEventDraft(
                title: eventTitle, startsAt: selectedDate, endsAt: end, isAllDay: isAllDay,
                location: nil, sourceURL: row.string("source_url").flatMap(URL.init(string:)),
                ownershipMarker: ""
            ),
            isCancelled: sourceState == "cancelled"
        )
    }
}
