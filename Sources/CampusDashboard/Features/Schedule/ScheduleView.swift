import SwiftUI

struct ScheduleView: View {
    @ObservedObject var model: DashboardModel
    @State private var mode: CalendarViewMode = .week
    @State private var anchor: Date
    @State private var filter = CalendarEventFilter()
    @State private var selectedEvent: CalendarEvent?

    init(model: DashboardModel) {
        self.model = model
        _anchor = State(initialValue: model.now)
    }

    var body: some View {
        PageContainer(title: model.text("Schedule"), subtitle: rangeTitle) {
            VStack(alignment: .leading, spacing: 12) {
                controls
                if model.isPreviewMode && [.loading, .error, .permissionDenied].contains(model.scenario) {
                    PreviewOperationalState(model: model)
                } else if let error = model.persistenceError {
                    StatePanel(icon: "exclamationmark.triangle", title: model.text("Source data unavailable"),
                               message: model.text(error), tint: .orange)
                } else {
                    if !model.sourceHealth.filter({ $0.category != .ready }).isEmpty {
                        Label(model.text("Sync issue"), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    calendarContent
                    undatedContent
                }
            }
        }
        .sheet(item: $selectedEvent) { event in EventDetailSheet(event: event, model: model) }
    }

    private var range: CalendarRange {
        CalendarDateMath.range(for: mode, anchor: anchor, timeZone: model.presentationTimeZone)
    }

    private var events: [CalendarEvent] {
        CalendarPresentation.filteredEvents(
            from: model.snapshot, academicSignals: model.academicSignals, filter: filter
        )
    }

    private var visibleEvents: [CalendarEvent] {
        events.filter { $0.start < range.end && $0.end > range.start }
    }

    private var rangeTitle: String {
        switch mode {
        case .day: return model.format(anchor, date: .long, time: .omitted)
        case .week:
            guard let first = range.dates.first, let last = range.dates.last else { return "" }
            return model.format(first, date: .abbreviated, time: .omitted) + " – " + model.format(last, date: .abbreviated, time: .omitted)
        case .month: return Localizer.monthYear(anchor, language: model.language, timeZone: model.presentationTimeZone)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker(model.text("Calendar view"), selection: $mode) {
                ForEach(CalendarViewMode.allCases) { value in
                    Text(model.text(modeLabel(value))).tag(value)
                }
            }
            .pickerStyle(.segmented).frame(width: 250)
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .help(model.text("Previous")).accessibilityLabel(model.text("Previous"))
            Button(model.text("Return to today")) { anchor = model.now }
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .help(model.text("Next")).accessibilityLabel(model.text("Next"))
            Spacer()
            filterMenu
        }
    }

    private var filterMenu: some View {
        Menu {
            Menu(model.text("Course")) {
                ForEach(model.snapshot.courses) { course in
                    Toggle(course.name, isOn: setBinding(course.id, keyPath: \.courseIDs))
                }
            }
            Menu(model.text("Source")) {
                ForEach(SourceKind.allCases) { source in
                    Toggle(source.rawValue, isOn: setBinding(source, keyPath: \.sources))
                }
            }
            Menu(model.text("All event types")) {
                ForEach(CalendarEventKind.allCases) { kind in
                    Toggle(model.text(kindLabel(kind)), isOn: setBinding(kind, keyPath: \.kinds))
                }
            }
            Divider()
            Button(model.text("Clear filters")) { filter = CalendarEventFilter() }
        } label: {
            Label(model.text("Filters"), systemImage: filter == CalendarEventFilter() ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(model.text("Filters"))
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch mode {
        case .day, .week:
            Card {
                if visibleEvents.isEmpty {
                    Text(model.text("No synchronized events match the current range and filters."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                SpatialTimeGrid(
                    days: range.dates, events: visibleEvents, language: model.language,
                    timeZone: model.presentationTimeZone, now: model.now, showsAllDay: true
                ) { selectedEvent = $0 }
            }
        case .month:
            monthGrid
        }
    }

    private var monthGrid: some View {
        let calendar = CalendarDateMath.calendar(timeZone: model.presentationTimeZone)
        let anchorMonth = calendar.component(.month, from: anchor)
        return Card {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(range.dates.prefix(7)), id: \.self) { date in
                        Text(Localizer.weekday(date, width: .abbreviated, language: model.language, timeZone: model.presentationTimeZone))
                            .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                    }
                }
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let date = range.dates[row * 7 + column]
                            let inMonth = calendar.component(.month, from: date) == anchorMonth
                            monthCell(date: date, inMonth: inMonth)
                        }
                    }
                }
            }
        }
    }

    private func monthCell(date: Date, inMonth: Bool) -> some View {
        let calendar = CalendarDateMath.calendar(timeZone: model.presentationTimeZone)
        let dayEvents = visibleEvents.filter { calendar.isDate($0.start, inSameDayAs: date) }
        let isToday = calendar.isDate(date, inSameDayAs: model.now)
        return VStack(alignment: .leading, spacing: 3) {
            Button {
                anchor = date
                mode = .day
            } label: {
                Text(String(calendar.component(.day, from: date)))
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary))
                    .frame(width: 22, height: 22)
                    .background(isToday ? Color.accentColor : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .help(model.text("Show day"))
            ForEach(dayEvents.prefix(3)) { event in
                Button { selectedEvent = event } label: {
                    HStack(spacing: 3) {
                        Image(systemName: eventSymbol(event.kind)).font(.system(size: 7)).foregroundStyle(eventColor(event.kind))
                        Text(event.title).font(.system(size: 9)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.text(kindLabel(event.kind)) + ", " + event.title)
            }
            Spacer(minLength: 0)
        }
        .padding(5).frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(inMonth ? Color.clear : Color.secondary.opacity(0.05))
        .overlay { Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.format(date, date: .long, time: .omitted))
    }

    @ViewBuilder
    private var undatedContent: some View {
        let items = CalendarPresentation.undatedTasks(from: model.snapshot)
        if !items.isEmpty {
            DisclosureGroup(model.text("Undated items")) {
                ForEach(items) { item in
                    HStack { Text(item.title); Spacer(); Text(model.snapshot.course(for: item.courseID)?.name ?? model.text("Unknown course")).foregroundStyle(.secondary) }
                        .padding(.vertical, 3)
                }
            }
            .padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func move(_ direction: Int) {
        anchor = CalendarDateMath.movedAnchor(anchor, mode: mode, direction: direction, timeZone: model.presentationTimeZone)
    }

    private func setBinding<T: Hashable>(_ value: T, keyPath: WritableKeyPath<CalendarEventFilter, Set<T>>) -> Binding<Bool> {
        Binding(get: { filter[keyPath: keyPath].contains(value) }, set: { enabled in
            if enabled { filter[keyPath: keyPath].insert(value) } else { filter[keyPath: keyPath].remove(value) }
        })
    }

    private func modeLabel(_ value: CalendarViewMode) -> String {
        switch value { case .day: "Day"; case .week: "Week"; case .month: "Month" }
    }

    private func kindLabel(_ value: CalendarEventKind) -> String {
        switch value {
        case .courseMeeting: "Course meeting"
        case .officialDeadline: "Official deadline"
        case .confirmedInferredDeadline: "Confirmed inferred deadline"
        case .confirmedExam: "Confirmed exam"
        case .confirmedScheduleChange: "Confirmed schedule change"
        }
    }

    private func eventColor(_ kind: CalendarEventKind) -> Color {
        switch kind { case .courseMeeting: .blue; case .officialDeadline: .red; case .confirmedInferredDeadline: .purple; case .confirmedExam: .orange; case .confirmedScheduleChange: .teal }
    }

    private func eventSymbol(_ kind: CalendarEventKind) -> String {
        switch kind { case .courseMeeting: "person.2"; case .officialDeadline: "exclamationmark.circle.fill"; case .confirmedInferredDeadline: "checkmark.sparkles"; case .confirmedExam: "graduationcap.fill"; case .confirmedScheduleChange: "arrow.triangle.2.circlepath" }
    }
}

struct EventDetailSheet: View {
    let event: CalendarEvent
    @ObservedObject var model: DashboardModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.title2.weight(.semibold))
                    Badge(text: model.text(kindLabel), color: color)
                }
                Spacer()
                Button(model.text("Cancel")) { dismiss() }
            }
            detail(model.text("Time"), event.isAllDay ? model.text("All-day") : model.format(event.start) + " – " + model.format(event.end))
            if !event.location.isEmpty { detail(model.text("Location"), event.location) }
            detail(model.text("State"), model.text(event.isCancelled ? "Cancelled" : "Active"))
            detail(model.text("Source"), event.source.rawValue)
            if let value = event.sourceURL, let url = URL(string: value) {
                Link(model.text("Open original source"), destination: url)
            } else {
                Text(model.text("No source link")).font(.caption).foregroundStyle(.secondary)
            }
            if let value = event.relatedSourceURL, let url = URL(string: value) {
                Link(model.text("Open change announcement"), destination: url)
            }
        }
        .padding(24).frame(width: 480)
        .accessibilityElement(children: .contain)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value) }
    }

    private var kindLabel: String {
        switch event.kind { case .courseMeeting: "Course meeting"; case .officialDeadline: "Official deadline"; case .confirmedInferredDeadline: "Confirmed inferred deadline"; case .confirmedExam: "Confirmed exam"; case .confirmedScheduleChange: "Confirmed schedule change" }
    }
    private var color: Color {
        switch event.kind { case .courseMeeting: .blue; case .officialDeadline: .red; case .confirmedInferredDeadline: .purple; case .confirmedExam: .orange; case .confirmedScheduleChange: .teal }
    }
}
