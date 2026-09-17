import Foundation

struct ManualEvent: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = ""
    var start: Date
    var end: Date
    var isAllDay = false
    var location = ""

    init(start: Date) {
        self.start = start
        self.end = start.addingTimeInterval(3600)
    }

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              end > start else { throw ValidationError.invalid }
    }

    enum ValidationError: Error { case invalid }

    var calendarEvent: CalendarEvent {
        CalendarEvent(id: "manual-\(id)", objectID: id, courseID: id, title: title,
                      start: start, end: end, isAllDay: isAllDay, kind: .manual,
                      source: nil, location: location, isCancelled: false, sourceURL: nil)
    }
}
