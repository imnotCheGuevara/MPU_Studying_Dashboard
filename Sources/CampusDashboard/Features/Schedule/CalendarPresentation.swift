import Foundation

enum CalendarViewMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: Self { self }
}

enum CalendarEventKind: String, CaseIterable, Identifiable, Sendable {
    case courseMeeting
    case officialDeadline
    case confirmedInferredDeadline
    case confirmedExam

    var id: Self { self }
}

struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let objectID: UUID
    let courseID: UUID
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let kind: CalendarEventKind
    let source: SourceKind
    let location: String
    let isCancelled: Bool
    let sourceURL: String?
    let relatedSourceURL: String?

    init(id: String, objectID: UUID, courseID: UUID, title: String, start: Date, end: Date,
         isAllDay: Bool, kind: CalendarEventKind, source: SourceKind, location: String,
         isCancelled: Bool, sourceURL: String?, relatedSourceURL: String? = nil) {
        self.id = id; self.objectID = objectID; self.courseID = courseID; self.title = title
        self.start = start; self.end = end; self.isAllDay = isAllDay; self.kind = kind
        self.source = source; self.location = location; self.isCancelled = isCancelled
        self.sourceURL = sourceURL; self.relatedSourceURL = relatedSourceURL
    }
}

struct CalendarEventFilter: Equatable, Sendable {
    var courseIDs: Set<UUID> = []
    var sources: Set<SourceKind> = []
    var kinds: Set<CalendarEventKind> = []

    func includes(_ event: CalendarEvent) -> Bool {
        (courseIDs.isEmpty || courseIDs.contains(event.courseID))
            && (sources.isEmpty || sources.contains(event.source))
            && (kinds.isEmpty || kinds.contains(event.kind))
    }
}

enum CalendarPresentation {
    static func events(from snapshot: DashboardSnapshot,
                       academicSignals: [AcademicSignalRecord] = []) -> [CalendarEvent] {
        let changes = Dictionary(grouping: academicSignals.filter {
            [.confirmed, .corrected].contains($0.confirmationState) && $0.targetMeetingID != nil
        }, by: { $0.targetMeetingID! }).compactMapValues { $0.sorted { $0.updatedAt > $1.updatedAt }.first }
        let meetings = snapshot.meetings.map { meeting in
            let change = changes[meeting.id]
            let words = ((change?.evidence ?? "") + " " + (change?.adoptedKeyRequirement ?? change?.keyRequirement ?? "")).lowercased()
            let cancelled = ["cancel", "取消", "停课"].contains { words.contains($0) }
            let newStart = (!cancelled ? change?.adoptedDate : nil) ?? meeting.start
            let changedTitle = cancelled ? "[CANCELLED] · \(meeting.title)" : (newStart != meeting.start ? "[CHANGED] · \(meeting.title)" : meeting.title)
            return CalendarEvent(
                id: "meeting:\(meeting.id.uuidString)", objectID: meeting.id,
                courseID: meeting.courseID, title: changedTitle,
                start: newStart, end: max(newStart.addingTimeInterval(meeting.end.timeIntervalSince(meeting.start)), newStart.addingTimeInterval(60)),
                isAllDay: meeting.isAllDay, kind: .courseMeeting, source: meeting.source,
                location: meeting.location, isCancelled: meeting.isCancelled || cancelled,
                sourceURL: meeting.sourceURL,
                relatedSourceURL: change.flatMap { signal in snapshot.announcements.first { $0.id == signal.announcementID }?.sourceURL }
            )
        }
        let deadlines = snapshot.tasks.flatMap { task -> [CalendarEvent] in
            var result: [CalendarEvent] = []
            if let due = task.officialDueAt {
                result.append(CalendarEvent(
                    id: "official:\(task.id.uuidString)", objectID: task.id,
                    courseID: task.courseID, title: task.title, start: due,
                    end: due.addingTimeInterval(task.officialDueIsAllDay ? 86_400 : 1_800),
                    isAllDay: task.officialDueIsAllDay, kind: .officialDeadline,
                    source: task.source, location: "", isCancelled: false,
                    sourceURL: task.sourceURL
                ))
            }
            if let suggested = task.suggestedCompleteAt, task.suggestedDateConfirmed {
                result.append(CalendarEvent(
                    id: "confirmed:\(task.id.uuidString)", objectID: task.id,
                    courseID: task.courseID, title: task.title, start: suggested,
                    end: suggested.addingTimeInterval(1_800), isAllDay: false,
                    kind: .confirmedInferredDeadline, source: task.source,
                    location: "", isCancelled: false, sourceURL: task.sourceURL
                ))
            }
            return result
        }
        let confirmedSignals = academicSignals.compactMap { signal -> CalendarEvent? in
            guard [.confirmed, .corrected].contains(signal.confirmationState),
                  signal.targetMeetingID == nil,
                  let date = signal.adoptedDate ?? signal.inferredDate,
                  let announcement = snapshot.announcements.first(where: { $0.id == signal.announcementID })
            else { return nil }
            let allDay = signal.adoptedIsAllDay ?? signal.isAllDay
            return CalendarEvent(
                id: "academic-signal:\(signal.id.uuidString)", objectID: signal.id,
                courseID: announcement.courseID, title: signal.keyRequirement,
                start: date, end: date.addingTimeInterval(allDay ? 86_400 : 1_800),
                isAllDay: allDay, kind: (signal.adoptedCategory ?? signal.category) == .examTime ? .confirmedExam : .confirmedInferredDeadline,
                source: .canvas, location: "", isCancelled: false,
                sourceURL: announcement.sourceURL
            )
        }
        return (meetings + deadlines + confirmedSignals).sorted(by: stableEventOrder)
    }

    static func filteredEvents(
        from snapshot: DashboardSnapshot, filter: CalendarEventFilter
    ) -> [CalendarEvent] {
        events(from: snapshot).filter(filter.includes)
    }

    static func filteredEvents(
        from snapshot: DashboardSnapshot, academicSignals: [AcademicSignalRecord],
        filter: CalendarEventFilter
    ) -> [CalendarEvent] {
        events(from: snapshot, academicSignals: academicSignals).filter(filter.includes)
    }

    static func undatedTasks(from snapshot: DashboardSnapshot) -> [LearningTask] {
        snapshot.tasks.filter { $0.officialDueAt == nil && !($0.suggestedDateConfirmed && $0.suggestedCompleteAt != nil) }
    }

    private static func stableEventOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        return lhs.id < rhs.id
    }
}

struct CalendarRange: Equatable, Sendable {
    let start: Date
    let end: Date
    let dates: [Date]
}

enum CalendarDateMath {
    static func calendar(timeZone: TimeZone) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = timeZone
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    static func startOfWeek(containing date: Date, timeZone: TimeZone) -> Date {
        let cal = calendar(timeZone: timeZone)
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: day)
        let daysFromMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysFromMonday, to: day)!
    }

    static func range(for mode: CalendarViewMode, anchor: Date, timeZone: TimeZone) -> CalendarRange {
        let cal = calendar(timeZone: timeZone)
        switch mode {
        case .day:
            let start = cal.startOfDay(for: anchor)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return CalendarRange(start: start, end: end, dates: [start])
        case .week:
            let start = startOfWeek(containing: anchor, timeZone: timeZone)
            let dates = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
            return CalendarRange(start: start, end: cal.date(byAdding: .day, value: 7, to: start)!, dates: dates)
        case .month:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchor))!
            let gridStart = startOfWeek(containing: monthStart, timeZone: timeZone)
            let dates = (0..<42).map { cal.date(byAdding: .day, value: $0, to: gridStart)! }
            return CalendarRange(start: gridStart, end: cal.date(byAdding: .day, value: 42, to: gridStart)!, dates: dates)
        }
    }

    static func movedAnchor(
        _ anchor: Date, mode: CalendarViewMode, direction: Int, timeZone: TimeZone
    ) -> Date {
        let cal = calendar(timeZone: timeZone)
        let component: Calendar.Component = mode == .month ? .month : .day
        let amount = mode == .week ? 7 * direction : direction
        return cal.date(byAdding: component, value: amount, to: anchor) ?? anchor
    }
}

struct TimeGridConfiguration: Equatable, Sendable {
    let startHour: Int
    let endHour: Int

    static let campusDay = TimeGridConfiguration(startHour: 7, endHour: 22)
    var duration: TimeInterval { TimeInterval((endHour - startHour) * 3_600) }
}

struct TimeGridPlacement: Identifiable, Equatable, Sendable {
    let event: CalendarEvent
    let day: Date
    let clippedStart: Date
    let clippedEnd: Date
    let topFraction: Double
    let heightFraction: Double
    let lane: Int
    let laneCount: Int
    let clipsStart: Bool
    let clipsEnd: Bool

    var id: String { "\(event.id):\(day.timeIntervalSince1970)" }
}

enum TimeGridLayout {
    static func placements(
        events: [CalendarEvent], day: Date, timeZone: TimeZone,
        configuration: TimeGridConfiguration = .campusDay
    ) -> [TimeGridPlacement] {
        let cal = CalendarDateMath.calendar(timeZone: timeZone)
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let visibleStart = cal.date(byAdding: .hour, value: configuration.startHour, to: dayStart)!
        let visibleEnd = cal.date(byAdding: .hour, value: configuration.endHour, to: dayStart)!
        let candidates = events.filter {
            !$0.isAllDay && $0.start < dayEnd && $0.end > dayStart && $0.start < visibleEnd && $0.end > visibleStart
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }

        struct Assigned { let event: CalendarEvent; let lane: Int; let group: Int }
        var assigned: [Assigned] = []
        var active: [(end: Date, lane: Int)] = []
        var group = -1
        var groupLaneCounts: [Int: Int] = [:]
        for event in candidates {
            active.removeAll { $0.end <= event.start }
            if active.isEmpty { group += 1 }
            let used = Set(active.map(\.lane))
            let lane = (0...).first { !used.contains($0) }!
            active.append((event.end, lane))
            assigned.append(Assigned(event: event, lane: lane, group: group))
            groupLaneCounts[group] = max(groupLaneCounts[group, default: 0], lane + 1)
        }

        return assigned.map { value in
            let start = max(value.event.start, visibleStart)
            let end = min(value.event.end, visibleEnd)
            return TimeGridPlacement(
                event: value.event, day: day, clippedStart: start, clippedEnd: end,
                topFraction: start.timeIntervalSince(visibleStart) / configuration.duration,
                heightFraction: max(0, end.timeIntervalSince(start) / configuration.duration),
                lane: value.lane, laneCount: groupLaneCounts[value.group] ?? 1,
                clipsStart: value.event.start < visibleStart,
                clipsEnd: value.event.end > visibleEnd
            )
        }
    }

    static func currentTimeFraction(
        now: Date, day: Date, timeZone: TimeZone,
        configuration: TimeGridConfiguration = .campusDay
    ) -> Double? {
        let cal = CalendarDateMath.calendar(timeZone: timeZone)
        guard cal.isDate(now, inSameDayAs: day) else { return nil }
        let start = cal.date(byAdding: .hour, value: configuration.startHour, to: cal.startOfDay(for: day))!
        let fraction = now.timeIntervalSince(start) / configuration.duration
        return (0...1).contains(fraction) ? fraction : nil
    }
}
