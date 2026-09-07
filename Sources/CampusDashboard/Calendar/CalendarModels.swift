import Foundation

enum CalendarAccessStatus: String, Equatable, Sendable {
    case notDetermined = "not_determined"
    case denied
    case restricted
    case fullAccess = "full_access"
    case writeOnly = "write_only"
}

enum CalendarSourceKind: String, Equatable, Sendable {
    case iCloud
    case local
    case exchange
    case calDAV
    case other
}

struct CalendarSourceDescriptor: Equatable, Sendable {
    let identifier: String
    let title: String
    let kind: CalendarSourceKind
}

struct CalendarDescriptor: Equatable, Sendable {
    let identifier: String
    let title: String
    let source: CalendarSourceDescriptor
    let allowsContentModifications: Bool
}

enum ManagedCalendarSelectionKind: String, Equatable, Sendable {
    case appCreated = "app_created"
    case userSelected = "user_selected"
}

enum ManagedCalendarValidationState: String, Equatable, Sendable {
    case valid
    case permissionDenied = "permission_denied"
    case permissionRevoked = "permission_revoked"
    case missing
    case ambiguous
    case sourceChanged = "source_changed"
    case unwritable
}

struct ManagedCalendarIdentity: Equatable, Sendable {
    let internalID: UUID
    var calendarIdentifier: String
    var sourceIdentifier: String
    var sourceKind: CalendarSourceKind
    var sourceTitle: String
    var calendarTitle: String
    var selectionKind: ManagedCalendarSelectionKind
    let ownershipMarker: String
    var validationState: ManagedCalendarValidationState
    var lastVerifiedAt: Date?

    var isICloud: Bool { sourceKind == .iCloud }
}

struct CalendarBindingRecord: Equatable, Sendable {
    let id: UUID
    let objectType: String
    let objectID: String
    var eventIdentifier: String
    var externalEventIdentifier: String?
    let ownershipMarker: String
    let calendarIdentifier: String
    let calendarSourceIdentifier: String
    var syncState: String
    var lastVerifiedAt: Date?
}

struct CalendarEventDraft: Equatable, Sendable {
    let title: String
    let startsAt: Date
    let endsAt: Date
    let isAllDay: Bool
    let location: String?
    let sourceURL: URL?
    let ownershipMarker: String
}

struct CalendarStoredEvent: Equatable, Sendable {
    let identifier: String
    let externalIdentifier: String?
    let calendarIdentifier: String
    let calendarSourceIdentifier: String
    let ownershipMarker: String?
    let title: String
    let startsAt: Date
    let endsAt: Date
}

enum CampusCalendarError: Error, Equatable, CustomStringConvertible, Sendable {
    case permissionNotRequested
    case permissionDenied
    case permissionRevoked
    case calendarNotConfigured
    case calendarMissing
    case ambiguousCalendarCandidates
    case sourceChanged
    case calendarUnwritable
    case invalidSelection
    case unsupportedObjectType
    case objectMissing
    case ineligibleDate
    case unconfirmedInferredDate
    case staleBinding
    case ambiguousOwnedEvents
    case eventRecoveryUnavailable
    case ambiguousExternalIdentifier

    var description: String {
        switch self {
        case .permissionNotRequested: "Calendar access has not been requested"
        case .permissionDenied: "Calendar access was denied"
        case .permissionRevoked: "Calendar access was revoked"
        case .calendarNotConfigured: "A dedicated calendar has not been configured"
        case .calendarMissing: "The dedicated calendar identifier is no longer available"
        case .ambiguousCalendarCandidates: "Multiple matching calendars require explicit selection"
        case .sourceChanged: "The dedicated calendar source identity changed"
        case .calendarUnwritable: "The dedicated calendar is not writable"
        case .invalidSelection: "The selected calendar or source is invalid"
        case .unsupportedObjectType: "The object type is not eligible for Calendar"
        case .objectMissing: "The calendar source object no longer exists"
        case .ineligibleDate: "The object has no eligible calendar date"
        case .unconfirmedInferredDate: "An inferred date requires explicit confirmation"
        case .staleBinding: "The event binding does not match the managed calendar or ownership marker"
        case .ambiguousOwnedEvents: "Multiple app-owned event candidates require repair"
        case .eventRecoveryUnavailable: "The bound event cannot be recovered safely"
        case .ambiguousExternalIdentifier: "The external event identifier has multiple candidates"
        }
    }
}

protocol CalendarEventStore: Sendable {
    func authorizationStatus() async -> CalendarAccessStatus
    func requestFullAccess() async throws -> Bool
    func sources() async -> [CalendarSourceDescriptor]
    func calendars() async -> [CalendarDescriptor]
    func createCalendar(title: String, sourceIdentifier: String) async throws -> CalendarDescriptor
    func removeCalendar(identifier: String) async throws
    func event(identifier: String) async -> CalendarStoredEvent?
    func events(externalIdentifier: String, calendarIdentifier: String) async -> [CalendarStoredEvent]
    func events(calendarIdentifier: String, around date: Date, ownershipMarker: String) async -> [CalendarStoredEvent]
    func saveEvent(
        _ draft: CalendarEventDraft,
        calendarIdentifier: String,
        existingEventIdentifier: String?
    ) async throws -> CalendarStoredEvent
    func removeEvent(
        identifier: String,
        calendarIdentifier: String,
        calendarSourceIdentifier: String,
        ownershipMarker: String,
        externalIdentifier: String?
    ) async throws
}
