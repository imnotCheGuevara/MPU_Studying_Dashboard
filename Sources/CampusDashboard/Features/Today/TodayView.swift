import SwiftUI

struct TodayView: View {
    @ObservedObject var model: DashboardModel
    @State private var weekAnchor: Date
    @State private var selectedEvent: CalendarEvent?

    init(model: DashboardModel) {
        self.model = model
        _weekAnchor = State(initialValue: model.now)
    }

    var body: some View {
        PageContainer(title: model.text("Today"), subtitle: weekTitle) {
            VStack(alignment: .leading, spacing: 12) {
                compactStatus
                if model.isPreviewMode && [.loading, .error, .permissionDenied].contains(model.scenario) {
                    PreviewOperationalState(model: model)
                } else if let error = model.persistenceError {
                    StatePanel(
                        icon: "exclamationmark.triangle", title: model.text("Source data unavailable"),
                        message: model.text(error) + " " + model.text("Try Refresh. If the problem continues, review source authorization in Settings."),
                        tint: .orange
                    )
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        timetable.frame(maxWidth: .infinity)
                        announcementSidebar.frame(width: 230)
                    }
                }
            }
        }
    }

    private var weekRange: CalendarRange {
        CalendarDateMath.range(for: .week, anchor: weekAnchor, timeZone: model.presentationTimeZone)
    }

    private var weekTitle: String {
        let dates = weekRange.dates
        guard let first = dates.first, let last = dates.last else { return model.todaySubtitle }
        return model.format(first, date: .abbreviated, time: .omitted) + " – "
            + model.format(last, date: .abbreviated, time: .omitted)
    }

    private var weekMeetings: [CalendarEvent] {
        CalendarPresentation.events(from: model.snapshot).filter {
            $0.kind == .courseMeeting && $0.start < weekRange.end && $0.end > weekRange.start
        }
    }

    private var timetable: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("Weekly timetable")).font(.headline)
                        Text(model.text("Monday through Sunday")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                        .help(model.text("Previous week")).accessibilityLabel(model.text("Previous week"))
                    Button(model.text("Current week")) { weekAnchor = model.now }
                    Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }
                        .help(model.text("Next week")).accessibilityLabel(model.text("Next week"))
                }
                if weekMeetings.isEmpty {
                    StatePanel(
                        icon: "calendar", title: model.text("No classes this week"),
                        message: model.text("No synchronized course meetings fall in this week."), tint: .secondary
                    )
                    .frame(minHeight: 720)
                } else {
                    SpatialTimeGrid(
                        days: weekRange.dates, events: weekMeetings, language: model.language,
                        timeZone: model.presentationTimeZone, now: model.now, showsAllDay: true
                    ) { selectedEvent = $0 }
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event, model: model)
        }
    }

    private var announcementSidebar: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.text("Unread announcements")).font(.headline)
                    Spacer()
                    Badge(text: "\(model.unreadAnnouncements.count)", color: .blue)
                }
                if model.unreadAnnouncements.isEmpty {
                    ContentUnavailableView(
                        model.text("No unread announcements"), systemImage: "megaphone",
                        description: Text(model.text("New announcements will appear here until you mark them read."))
                    )
                    .frame(minHeight: 260)
                } else {
                    ForEach(model.unreadAnnouncements.sorted(by: { $0.publishedAt > $1.publishedAt })) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                            Text(courseName(item.courseID)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(model.relativeTime(item.publishedAt)).font(.caption2).foregroundStyle(.secondary)
                                .help(model.format(item.publishedAt))
                            HStack {
                                if let value = item.sourceURL, let url = URL(string: value) {
                                    Link(model.text("Open source"), destination: url)
                                }
                                Spacer()
                                Button(model.text("Mark read")) { model.toggleAnnouncement(item.id) }
                            }.font(.caption)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                        Divider()
                    }
                }
            }
        }
        .accessibilityLabel(model.text("Unread announcements"))
    }

    private var compactStatus: some View {
        HStack(spacing: 12) {
            ForEach(statusItems, id: \.name) { item in
                HStack(spacing: 5) {
                    Circle().fill(item.good ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(item.name).font(.caption.weight(.semibold))
                    Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
            Text(model.text(model.isRefreshing ? "Refresh in progress" : "Manual refresh"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private var statusItems: [(name: String, detail: String, good: Bool)] {
        if !model.sourceHealth.isEmpty {
            return model.sourceHealth.map {
                let last = $0.lastSuccessfulSync.map { model.relativeTime($0) } ?? model.text("Never synced")
                return ($0.source, last, $0.category == .ready)
            } + [(model.text("Background sync"), model.text(model.backgroundMessage), model.backgroundConfiguration.enabled)]
        }
        return model.snapshot.sourceHealth.map {
            let last = $0.lastSuccessfulSync.map { model.relativeTime($0) } ?? model.text("Never synced")
            return ($0.source.rawValue, last, $0.level == .healthy)
        } + [(model.text("Background sync"), model.text(model.backgroundMessage), model.backgroundConfiguration.enabled)]
    }

    private func moveWeek(_ direction: Int) {
        weekAnchor = CalendarDateMath.movedAnchor(
            weekAnchor, mode: .week, direction: direction, timeZone: model.presentationTimeZone
        )
    }

    private func courseName(_ id: UUID) -> String {
        model.snapshot.course(for: id)?.name ?? model.text("Unknown course")
    }
}
