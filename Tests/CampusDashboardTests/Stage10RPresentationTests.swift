import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 10R timetable and calendar presentation")
struct Stage10RPresentationTests {
    let macau = TimeZone(identifier: "Asia/Macau")!

    @Test("Proportional placement, duration, clipping, and deterministic overlap lanes")
    func proportionalOverlapAndClipping() throws {
        let day = date(2026, 9, 7, 0, 0)
        let events = [
            event("b", start: date(2026, 9, 7, 9, 30), end: date(2026, 9, 7, 11, 0)),
            event("a", start: date(2026, 9, 7, 9, 0), end: date(2026, 9, 7, 10, 30)),
            event("early", start: date(2026, 9, 7, 6, 0), end: date(2026, 9, 7, 8, 0)),
            event("late", start: date(2026, 9, 7, 21, 0), end: date(2026, 9, 7, 23, 0))
        ]
        let first = TimeGridLayout.placements(events: events, day: day, timeZone: macau)
        let second = TimeGridLayout.placements(events: events.reversed(), day: day, timeZone: macau)

        #expect(first.map { "\($0.event.id):\($0.lane):\($0.laneCount)" } == second.map { "\($0.event.id):\($0.lane):\($0.laneCount)" })
        let a = try #require(first.first { $0.event.id == "a" })
        #expect(abs(a.topFraction - 2.0 / 15.0) < 0.0001)
        #expect(abs(a.heightFraction - 1.5 / 15.0) < 0.0001)
        #expect(a.lane == 0 && a.laneCount == 2)
        #expect(first.first { $0.event.id == "b" }?.lane == 1)
        #expect(first.first { $0.event.id == "early" }?.clipsStart == true)
        #expect(first.first { $0.event.id == "late" }?.clipsEnd == true)
    }

    @Test("Cross-midnight events split safely across adjacent days")
    func crossMidnight() {
        let item = event("night", start: date(2026, 9, 7, 21, 30), end: date(2026, 9, 8, 8, 30))
        let monday = TimeGridLayout.placements(events: [item], day: date(2026, 9, 7), timeZone: macau)
        let tuesday = TimeGridLayout.placements(events: [item], day: date(2026, 9, 8), timeZone: macau)
        #expect(monday.count == 1 && monday[0].clipsEnd)
        #expect(tuesday.count == 1 && tuesday[0].clipsStart)
        #expect(monday[0].heightFraction > 0 && tuesday[0].heightFraction > 0)
    }

    @Test("Week is always Monday through Sunday and navigation is stable")
    func mondayWeekAndNavigation() {
        let saturday = date(2026, 9, 5)
        let range = CalendarDateMath.range(for: .week, anchor: saturday, timeZone: macau)
        let calendar = CalendarDateMath.calendar(timeZone: macau)
        #expect(range.dates.count == 7)
        #expect(calendar.component(.weekday, from: range.dates[0]) == 2)
        #expect(calendar.component(.weekday, from: range.dates[6]) == 1)
        let next = CalendarDateMath.movedAnchor(saturday, mode: .week, direction: 1, timeZone: macau)
        #expect(CalendarDateMath.startOfWeek(containing: next, timeZone: macau) == calendar.date(byAdding: .day, value: 7, to: range.start))
    }

    @Test("DST boundaries keep seven local dates and day ranges use local calendar boundaries")
    func dstBoundaries() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let calendar = CalendarDateMath.calendar(timeZone: newYork)
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let week = CalendarDateMath.range(for: .week, anchor: spring, timeZone: newYork)
        #expect(week.dates.count == 7)
        #expect(Set(week.dates.map { calendar.component(.day, from: $0) }).count == 7)
        let day = CalendarDateMath.range(for: .day, anchor: spring, timeZone: newYork)
        #expect(day.end.timeIntervalSince(day.start) == 23 * 3_600)
    }

    @Test("Month grid contains six Monday-first weeks across both month boundaries")
    func monthGridBoundaries() {
        let range = CalendarDateMath.range(for: .month, anchor: date(2026, 1, 15), timeZone: macau)
        let calendar = CalendarDateMath.calendar(timeZone: macau)
        #expect(range.dates.count == 42)
        #expect(calendar.dateComponents([.year, .month, .day], from: range.dates.first!) == DateComponents(year: 2025, month: 12, day: 29))
        #expect(calendar.dateComponents([.year, .month, .day], from: range.dates.last!) == DateComponents(year: 2026, month: 2, day: 8))
    }

    @Test("Formal calendar excludes unconfirmed inference and supports filters and all-day details")
    func eligibilityFiltersAndAllDay() {
        let courseID = UUID()
        let official = task(courseID: courseID, id: UUID(), official: date(2026, 9, 7, 12), suggested: nil, confirmed: false, allDay: true)
        let unconfirmed = task(courseID: courseID, id: UUID(), official: nil, suggested: date(2026, 9, 8, 12), confirmed: false)
        let confirmed = task(courseID: courseID, id: UUID(), official: nil, suggested: date(2026, 9, 9, 12), confirmed: true)
        let snapshot = DashboardSnapshot(sourceHealth: [], courses: [course(courseID)], meetings: [], tasks: [official, unconfirmed, confirmed], announcements: [], confirmations: [])
        let events = CalendarPresentation.events(from: snapshot)
        #expect(events.count == 2)
        #expect(!events.contains { $0.objectID == unconfirmed.id })
        #expect(events.first { $0.objectID == official.id }?.isAllDay == true)
        let filter = CalendarEventFilter(courseIDs: [], sources: [.canvas], kinds: [.confirmedInferredDeadline])
        #expect(CalendarPresentation.filteredEvents(from: snapshot, filter: filter).map(\.objectID) == [confirmed.id])
        #expect(CalendarPresentation.undatedTasks(from: snapshot).map(\.id) == [unconfirmed.id])
    }

    @Test("Selected event presentation retains accessible detail and original source link")
    func eventSelectionDetails() throws {
        let courseID = UUID()
        let meeting = CourseMeeting(
            id: UUID(), courseID: courseID, title: "Source meeting", start: date(2026, 9, 7, 9),
            end: date(2026, 9, 7, 10, 30), location: "原始地点 · Salle 3", source: .siweb,
            isCancelled: true, sourceURL: "https://source.invalid/meeting?q=原始"
        )
        let snapshot = DashboardSnapshot(
            sourceHealth: [], courses: [course(courseID)], meetings: [meeting], tasks: [],
            announcements: [], confirmations: []
        )

        let selected = try #require(CalendarPresentation.events(from: snapshot).first)
        #expect(selected.objectID == meeting.id)
        #expect(selected.start == meeting.start && selected.end == meeting.end)
        #expect(selected.location == "原始地点 · Salle 3")
        #expect(selected.isCancelled)
        #expect(selected.source == .siweb)
        #expect(selected.sourceURL == "https://source.invalid/meeting?q=原始")
    }

    private func event(_ id: String, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(id: id, objectID: UUID(), courseID: UUID(), title: id, start: start, end: end,
                      isAllDay: false, kind: .courseMeeting, source: .siweb, location: "", isCancelled: false, sourceURL: nil)
    }

    private func course(_ id: UUID) -> Course {
        Course(id: id, sourceAccountID: "account", sourceObjectID: "course", name: "原始课程 Économie", code: "原码", term: "原学期", colorName: "blue", sourceURL: "https://source.invalid/course?q=原始")
    }

    private func task(courseID: UUID, id: UUID, official: Date?, suggested: Date?, confirmed: Bool, allDay: Bool = false) -> LearningTask {
        LearningTask(id: id, sourceAccountID: "account", sourceObjectID: id.uuidString, courseID: courseID,
                     title: "原始任务 Résumé", kind: .assignment, officialDueAt: official,
                     suggestedCompleteAt: suggested, suggestedDateConfirmed: confirmed, source: .canvas,
                     isLocallyComplete: false, localPriority: .medium, officialDueIsAllDay: allDay,
                     sourceURL: "https://source.invalid/task?q=原始")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        CalendarDateMath.calendar(timeZone: macau).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

@MainActor
@Suite("Stage 10R localization and source preservation")
struct Stage10RLocalizationTests {
    let macau = TimeZone(identifier: "Asia/Macau")!

    @Test("Explicit UI QA database model crosses the production SQLite reader boundary")
    func databaseBackedQAModel() async throws {
        let model = try Stage10RQAData.databaseModel()
        #expect(!model.isPreviewMode)
        #expect(model.snapshot == .empty)

        await model.startRuntimeServices()

        #expect(model.persistenceError == nil)
        #expect(model.snapshot.courses.map(\.name) == ["Database-backed synthetic course"])
        #expect(model.snapshot.meetings.count == 1)
        #expect(model.snapshot.meetings[0].sourceURL == "https://example.invalid/course")
        #expect(model.snapshot.announcements.map(\.title) == ["Database-backed synthetic announcement"])
        #expect(model.snapshot.announcements[0].sourceURL == "https://example.invalid/announcement")
    }

    @Test("English and Simplified Chinese dates, months, weekdays, and relative time use selected locale")
    func localeFormatting() {
        let calendar = CalendarDateMath.calendar(timeZone: macau)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!
        #expect(Localizer.weekday(date, language: .english, timeZone: macau).lowercased().contains("monday"))
        #expect(Localizer.weekday(date, language: .simplifiedChinese, timeZone: macau).contains("星期一"))
        #expect(Localizer.monthYear(date, language: .english, timeZone: macau).contains("September"))
        #expect(Localizer.monthYear(date, language: .simplifiedChinese, timeZone: macau).contains("9月"))
        #expect(Localizer.relative(date.addingTimeInterval(-3_600), relativeTo: date, language: .english).contains("hour"))
        #expect(Localizer.relative(date.addingTimeInterval(-3_600), relativeTo: date, language: .simplifiedChinese).contains("小时"))
    }

    @Test("Required navigation, status, error, dialog, help, accessibility, and empty-state keys have Chinese values")
    func localizationInventory() {
        let keys = [
            "Today", "Schedule", "Tasks", "Announcements", "Settings", "Day", "Week", "Month",
            "Previous week", "Next week", "Current week", "Return to today", "Filters", "Event details",
            "Ready", "Needs attention", "Cancelled", "permission_denied", "Dashboard data is temporarily unavailable. Existing source data was not replaced.",
            "Refresh", "Refresh in progress", "Confirm separate destructive operation", "Cancel", "Save correction",
            "Select a deterministic UI state", "Synchronize sources and reload dashboard data", "Refresh dashboard",
            "No classes this week", "No scheduled items", "No unread announcements", "Permission denied",
            "Calendar permission was revoked. Existing bindings are preserved and no event will be touched."
        ]
        for key in keys {
            #expect(Localizer.simplifiedChinese[key] != nil, "Missing zh-Hans value for \(key)")
            #expect(Localizer.text(key, language: .simplifiedChinese) != key, "Untranslated zh-Hans value for \(key)")
            #expect(Localizer.text(key, language: .english) == key)
        }
        let enumKeys = SourceHealthCategory.allCasesForLocalization
            + AIConfirmationState.allCasesForLocalization
            + ["not_determined", "denied", "restricted", "full_access", "write_only",
               "enabled", "disabled", "requires_approval", "unavailable", "valid", "missing", "ambiguous", "unwritable"]
        for key in enumKeys {
            #expect(Localizer.text(key, language: .simplifiedChinese) != key, "Missing enum/status mapping for \(key)")
        }
    }

    @Test("Language switching preserves every source-owned field and URL")
    func sourceTextPreserved() {
        let courseID = UUID()
        let course = Course(id: courseID, sourceAccountID: "acct", sourceObjectID: "id", name: "原文 Économie",
                            code: "代碼-01", term: "原学期", colorName: "blue", sourceURL: "https://source.invalid/c?q=原文")
        let meeting = CourseMeeting(
            id: UUID(), courseID: courseID, title: "教師课程名", start: Date(), end: Date().addingTimeInterval(3_600),
            location: "原始地点 · Salle 3", source: .siweb, isCancelled: false,
            sourceURL: "https://source.invalid/m?q=原文"
        )
        let task = LearningTask(
            id: UUID(), sourceAccountID: "acct", sourceObjectID: "task", courseID: courseID,
            title: "原始任务 Résumé", kind: .assignment, officialDueAt: Date(), suggestedCompleteAt: nil,
            suggestedDateConfirmed: false, source: .canvas, isLocallyComplete: false, localPriority: .medium,
            sourceURL: "https://source.invalid/t?q=原文"
        )
        let announcement = Announcement(id: UUID(), sourceObjectID: "a", courseID: courseID,
            title: "教師原文 — déjà vu", summary: "不得翻译的正文", publishedAt: Date(), source: .canvas,
            isLocallyRead: false, sourceURL: "https://source.invalid/a?q=原文")
        let model = DashboardModel(snapshot: DashboardSnapshot(
            sourceHealth: [], courses: [course], meetings: [meeting], tasks: [task],
            announcements: [announcement], confirmations: []
        ))
        let before = model.snapshot
        model.language = .simplifiedChinese
        #expect(model.snapshot == before)
        #expect(model.snapshot.courses[0].name == "原文 Économie")
        #expect(model.snapshot.meetings[0].title == "教師课程名")
        #expect(model.snapshot.meetings[0].location == "原始地点 · Salle 3")
        #expect(model.snapshot.meetings[0].sourceURL == "https://source.invalid/m?q=原文")
        #expect(model.snapshot.tasks[0].title == "原始任务 Résumé")
        #expect(model.snapshot.tasks[0].sourceURL == "https://source.invalid/t?q=原文")
        #expect(model.snapshot.announcements[0].title == "教師原文 — déjà vu")
        #expect(model.snapshot.announcements[0].summary == "不得翻译的正文")
        #expect(model.snapshot.announcements[0].sourceURL == "https://source.invalid/a?q=原文")
    }

    @Test("Announcement read state persists locally without changing source identity or content")
    func announcementReadStateIsLocal() throws {
        let repository = InMemoryLocalStateRepository()
        let courseID = UUID()
        let announcement = Announcement(id: UUID(), sourceObjectID: "remote-announcement-7", courseID: courseID,
            title: "Teacher source title", summary: "Teacher source body", publishedAt: Date(), source: .canvas,
            isLocallyRead: false, sourceURL: "https://source.invalid/announcement/7")
        let snapshot = DashboardSnapshot(sourceHealth: [], courses: [], meetings: [], tasks: [], announcements: [announcement], confirmations: [])
        let first = DashboardModel(snapshot: snapshot, localStateRepository: repository)
        first.toggleAnnouncement(announcement.id)
        let second = DashboardModel(snapshot: snapshot, localStateRepository: repository)

        #expect(second.snapshot.announcements[0].isLocallyRead)
        #expect(second.snapshot.announcements[0].sourceObjectID == "remote-announcement-7")
        #expect(second.snapshot.announcements[0].title == "Teacher source title")
        #expect(second.snapshot.announcements[0].summary == "Teacher source body")
        #expect(second.snapshot.announcements[0].sourceURL == "https://source.invalid/announcement/7")
    }
}

private extension SourceHealthCategory {
    static let allCasesForLocalization = [
        "ready", "not_configured", "authorization_required", "permission_denied", "offline",
        "rate_limited", "source_changed", "service_unavailable", "cancelled", "failed"
    ]
}

private extension AIConfirmationState {
    static let allCasesForLocalization = ["pending", "confirmed", "corrected", "rejected", "undone", "failed"]
}
