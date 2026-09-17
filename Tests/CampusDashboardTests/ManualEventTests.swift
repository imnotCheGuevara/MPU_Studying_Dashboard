import Foundation
import Testing
@testable import CampusDashboard

@Suite("Manual events")
struct ManualEventTests {
    @Test("Create, edit, reopen and delete persist without Calendar work")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("test.sqlite").path
        var event = ManualEvent(start: Date(timeIntervalSince1970: 1_800_000_000))
        event.title = "Study session"
        do {
            let db = try SQLiteDatabase(path: path)
            let repo = SQLiteLocalStateRepository(persistence: SQLitePersistenceRepository(database: db))
            try repo.saveManualEvent(event)
            event.title = "Revised session"
            try repo.saveManualEvent(event)
            #expect(try repo.manualEvents() == [event])
            #expect(try db.scalarInt("SELECT COUNT(*) FROM outbox_work") == 0)
        }
        let db = try SQLiteDatabase(path: path)
        let repo = SQLiteLocalStateRepository(persistence: SQLitePersistenceRepository(database: db))
        #expect(try repo.manualEvents() == [event])
        try repo.deleteManualEvent(event.id)
        #expect(try repo.manualEvents().isEmpty)
    }

    @Test("Invalid events never replace a saved record")
    func validation() throws {
        let repo = InMemoryLocalStateRepository()
        var event = ManualEvent(start: Date())
        #expect(throws: ManualEvent.ValidationError.self) { try repo.saveManualEvent(event) }
        event.title = "Valid"
        try repo.saveManualEvent(event)
        var invalid = event
        invalid.end = invalid.start
        #expect(throws: ManualEvent.ValidationError.self) { try repo.saveManualEvent(invalid) }
        #expect(try repo.manualEvents() == [event])
    }

    @Test("Cross-midnight and exclusive all-day boundaries appear on the correct days")
    func agenda() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_800_057_600) // a UTC midnight
        let day = CalendarDateMath.calendar(timeZone: zone).startOfDay(for: start)
        var event = ManualEvent(start: day.addingTimeInterval(23 * 3600))
        event.title = "Overnight"
        event.end = day.addingTimeInterval(25 * 3600)
        func agenda(_ date: Date) -> [CalendarEvent] {
            TodayPresentation.agendaEvents(from: .empty, academicSignals: [], on: date,
                                           timeZone: zone, manualEvents: [event])
        }
        #expect(agenda(day).count == 1)
        #expect(agenda(day.addingTimeInterval(86400)).count == 1)
        event.isAllDay = true
        event.start = day
        event.end = day.addingTimeInterval(86400)
        #expect(agenda(day).count == 1)
        #expect(agenda(event.end).isEmpty)
        #expect(event.calendarEvent.source == nil)
        #expect(!CalendarEventFilter(sources: [.canvas]).includes(event.calendarEvent))
        #expect(CalendarEventFilter(kinds: [.manual]).includes(event.calendarEvent))
    }

    @Test("Local state cleanup clears manual events")
    func privacyClear() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        let repo = SQLiteLocalStateRepository(persistence: SQLitePersistenceRepository(database: db))
        var event = ManualEvent(start: Date())
        event.title = "Private event"
        try repo.saveManualEvent(event)
        _ = try PrivacyDiagnosticsService(database: db).clear(.localUserState)
        #expect(try repo.manualEvents().isEmpty)
    }
}
