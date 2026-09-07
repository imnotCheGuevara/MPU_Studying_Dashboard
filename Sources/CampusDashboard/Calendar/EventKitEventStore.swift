@preconcurrency import EventKit
import Foundation

actor EventKitEventStore: CalendarEventStore {
    private let eventStore: EKEventStore
    private static let markerPrefix = "Campus Dashboard ownership: "

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationStatus() -> CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess, .authorized: .fullAccess
        @unknown default: .denied
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func sources() -> [CalendarSourceDescriptor] {
        eventStore.sources.map(sourceDescriptor).sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func calendars() -> [CalendarDescriptor] {
        eventStore.calendars(for: .event).map(calendarDescriptor).sorted { lhs, rhs in
            if lhs.title == rhs.title { return lhs.identifier < rhs.identifier }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func createCalendar(title: String, sourceIdentifier: String) throws -> CalendarDescriptor {
        guard let source = eventStore.sources.first(where: { $0.sourceIdentifier == sourceIdentifier }) else {
            throw CampusCalendarError.invalidSelection
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = title
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        return calendarDescriptor(calendar)
    }

    func removeCalendar(identifier: String) throws {
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else { return }
        try eventStore.removeCalendar(calendar, commit: true)
    }

    func event(identifier: String) -> CalendarStoredEvent? {
        guard let event = eventStore.event(withIdentifier: identifier) else { return nil }
        return storedEvent(event)
    }

    func events(externalIdentifier: String, calendarIdentifier: String) -> [CalendarStoredEvent] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else { return [] }
        let sourceIdentifier = calendar.source.sourceIdentifier
        return eventStore.calendarItems(withExternalIdentifier: externalIdentifier).compactMap { item in
            guard let event = item as? EKEvent,
                  event.calendar.calendarIdentifier == calendarIdentifier,
                  event.calendar.source.sourceIdentifier == sourceIdentifier else { return nil }
            return storedEvent(event)
        }
    }

    func events(
        calendarIdentifier: String,
        around date: Date,
        ownershipMarker: String
    ) -> [CalendarStoredEvent] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else { return [] }
        let predicate = eventStore.predicateForEvents(
            withStart: date.addingTimeInterval(-172_800),
            end: date.addingTimeInterval(172_800),
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate).filter {
            marker(from: $0.notes) == ownershipMarker
        }.map(storedEvent)
    }

    func saveEvent(
        _ draft: CalendarEventDraft,
        calendarIdentifier: String,
        existingEventIdentifier: String?
    ) throws -> CalendarStoredEvent {
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier),
              calendar.allowsContentModifications else {
            throw CampusCalendarError.calendarUnwritable
        }
        let event: EKEvent
        if let existingEventIdentifier {
            guard let existing = eventStore.event(withIdentifier: existingEventIdentifier) else {
                throw CampusCalendarError.eventRecoveryUnavailable
            }
            guard existing.calendar.calendarIdentifier == calendarIdentifier,
                  existing.calendar.source.sourceIdentifier == calendar.source.sourceIdentifier,
                  marker(from: existing.notes) == draft.ownershipMarker else {
                throw CampusCalendarError.staleBinding
            }
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
        }
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.startsAt
        event.endDate = draft.endsAt
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.url = draft.sourceURL
        event.notes = Self.markerPrefix + draft.ownershipMarker
        try eventStore.save(event, span: .thisEvent, commit: true)
        return storedEvent(event)
    }

    func removeEvent(
        identifier: String,
        calendarIdentifier: String,
        calendarSourceIdentifier: String,
        ownershipMarker: String,
        externalIdentifier: String?
    ) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw CampusCalendarError.eventRecoveryUnavailable
        }
        guard event.calendar.calendarIdentifier == calendarIdentifier,
              event.calendar.source.sourceIdentifier == calendarSourceIdentifier,
              marker(from: event.notes) == ownershipMarker else {
            throw CampusCalendarError.staleBinding
        }
        if let externalIdentifier {
            guard event.calendarItemExternalIdentifier == externalIdentifier else {
                throw CampusCalendarError.staleBinding
            }
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    private func calendarDescriptor(_ calendar: EKCalendar) -> CalendarDescriptor {
        CalendarDescriptor(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            source: sourceDescriptor(calendar.source),
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    private func sourceDescriptor(_ source: EKSource) -> CalendarSourceDescriptor {
        CalendarSourceDescriptor(
            identifier: source.sourceIdentifier,
            title: source.title,
            kind: sourceKind(source)
        )
    }

    private func sourceKind(_ source: EKSource) -> CalendarSourceKind {
        switch source.sourceType {
        case .local: return .local
        case .exchange: return .exchange
        case .calDAV:
            return source.title.localizedCaseInsensitiveContains("icloud") ? .iCloud : .calDAV
        case .mobileMe: return .iCloud
        default: return .other
        }
    }

    private func storedEvent(_ event: EKEvent) -> CalendarStoredEvent {
        CalendarStoredEvent(
            identifier: event.calendarItemIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarSourceIdentifier: event.calendar.source.sourceIdentifier,
            ownershipMarker: marker(from: event.notes),
            title: event.title ?? "",
            startsAt: event.startDate,
            endsAt: event.endDate
        )
    }

    private func marker(from notes: String?) -> String? {
        guard let notes, notes.hasPrefix(Self.markerPrefix) else { return nil }
        return String(notes.dropFirst(Self.markerPrefix.count))
    }
}
