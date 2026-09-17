import SwiftUI

struct TodayView: View {
    @ObservedObject var model: DashboardModel
    @State private var selectedEvent: CalendarEvent?

    var body: some View {
        PageContainer(title: model.text("Today"), subtitle: model.todaySubtitle) {
            VStack(alignment: .leading, spacing: 12) {
                compactStatus
                calendarDeliveryNotice
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
                        VStack(alignment: .leading, spacing: 12) {
                            todayAgenda
                            dueTodayCard
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 12) {
                            scheduleUpdatesCard
                            announcementSidebar
                        }
                        .frame(width: 300)
                    }
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event, model: model)
        }
    }

    private var agendaEvents: [CalendarEvent] {
        TodayPresentation.agendaEvents(
            from: model.snapshot, academicSignals: model.academicSignals,
            on: model.now, timeZone: model.presentationTimeZone, manualEvents: model.manualEvents
        )
    }

    private var scheduleUpdates: [AcademicSignalRecord] {
        Array(TodayPresentation.scheduleUpdates(model.academicSignals).prefix(5))
    }

    private var dueTasks: [LearningTask] {
        TodayPresentation.dueTasks(
            from: model.snapshot, on: model.now, timeZone: model.presentationTimeZone
        )
    }

    private var todayAgenda: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Today's agenda", detail: "A focused list for today", count: agendaEvents.count)
                if agendaEvents.isEmpty {
                    ContentUnavailableView(
                        model.text("Nothing scheduled today"), systemImage: "sun.max",
                        description: Text(model.text("Confirmed changes appear here automatically."))
                    )
                    .frame(minHeight: 230)
                } else {
                    ForEach(agendaEvents) { event in
                        Button { selectedEvent = event } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.isAllDay ? model.text("All-day") : model.format(event.start, date: .omitted, time: .shortened))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    if !event.isAllDay {
                                        Text(model.format(event.end, date: .omitted, time: .shortened))
                                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(width: 64, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(eventSubtitle(event)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if event.isCancelled {
                                    Badge(text: model.text("Cancelled"), color: .red)
                                } else if event.relatedSourceURL != nil || event.kind == .confirmedScheduleChange {
                                    Badge(text: model.text("Changed"), color: .teal)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private var dueTodayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Due today", detail: nil, count: dueTasks.count)
                if dueTasks.isEmpty {
                    Text(model.text("Nothing due today")).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                } else {
                    ForEach(dueTasks) { task in
                        HStack(spacing: 10) {
                            Button { model.toggleTask(task.id) } label: {
                                Image(systemName: task.isLocallyComplete ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(courseName(task.courseID)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let due = task.officialDueAt {
                                Text(task.officialDueIsAllDay ? model.text("All-day") : model.format(due, date: .omitted, time: .shortened))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var scheduleUpdatesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Schedule updates", detail: nil, count: scheduleUpdates.count)
                if scheduleUpdates.isEmpty {
                    ContentUnavailableView(
                        model.text("No schedule updates"), systemImage: "calendar.badge.checkmark",
                        description: Text(model.text("Confirmed and pending course changes appear here."))
                    )
                    .frame(minHeight: 130)
                } else {
                    ForEach(scheduleUpdates) { signal in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(signal.adoptedKeyRequirement ?? signal.keyRequirement)
                                    .font(.subheadline.weight(.semibold)).lineLimit(3)
                                Spacer()
                                Badge(text: model.text(updateState(signal)), color: updateColor(signal))
                            }
                            Text(updateCourseName(signal)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let date = signal.adoptedDate ?? signal.inferredDate {
                                Text(model.format(date)).font(.caption2).foregroundStyle(.secondary)
                            }
                            if NeedsReviewPolicy.includes(signal) {
                                Button(model.text("Review")) { model.selectedSection = .confirmations }
                                    .font(.caption)
                            } else if let url = sourceURL(signal) {
                                Link(model.text("Open change announcement"), destination: url).font(.caption)
                            }
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private var announcementSidebar: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Unread announcements", detail: nil, count: model.unreadAnnouncements.count)
                if model.unreadAnnouncements.isEmpty {
                    ContentUnavailableView(
                        model.text("No unread announcements"), systemImage: "megaphone",
                        description: Text(model.text("New announcements will appear here until you mark them read."))
                    )
                    .frame(minHeight: 170)
                } else {
                    ForEach(model.unreadAnnouncements.sorted(by: { $0.publishedAt > $1.publishedAt }).prefix(5)) { item in
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
                        Divider()
                    }
                }
            }
        }
        .accessibilityLabel(model.text("Unread announcements"))
    }

    @ViewBuilder
    private var calendarDeliveryNotice: some View {
        if model.calendarDeliverySummary.pendingCount > 0 {
            HStack(spacing: 10) {
                Image(systemName: "icloud.slash").foregroundStyle(.orange)
                Text("\(model.calendarDeliverySummary.pendingCount) \(model.text("Calendar changes waiting"))")
                    .font(.subheadline.weight(.semibold))
                Text(model.text("Calendar changes are waiting to retry. Existing iCloud events remain untouched."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.text("Open Settings")) { model.selectedSection = .settings }
            }
            .padding(12)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
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

    private func sectionHeading(_ title: String, detail: String?, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.text(title)).font(.headline)
                if let detail { Text(model.text(detail)).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Badge(text: "\(count)", color: .blue)
        }
    }

    private func eventSubtitle(_ event: CalendarEvent) -> String {
        [event.kind == .manual ? model.text("Manual event") : courseName(event.courseID), event.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func courseName(_ id: UUID) -> String {
        model.snapshot.course(for: id)?.name ?? model.text("Unknown course")
    }

    private func updateCourseName(_ signal: AcademicSignalRecord) -> String {
        if let id = signal.courseID { return courseName(id) }
        guard let announcement = model.snapshot.announcements.first(where: { $0.id == signal.announcementID }) else {
            return model.text("Unknown course")
        }
        return courseName(announcement.courseID)
    }

    private func sourceURL(_ signal: AcademicSignalRecord) -> URL? {
        model.snapshot.announcements.first(where: { $0.id == signal.announcementID })
            .flatMap { $0.sourceURL }.flatMap(URL.init(string:))
    }

    private func updateState(_ signal: AcademicSignalRecord) -> String {
        switch signal.confirmationState {
        case .confirmed: "Confirmed"
        case .corrected: "Corrected"
        default: "Pending"
        }
    }

    private func updateColor(_ signal: AcademicSignalRecord) -> Color {
        NeedsReviewPolicy.includes(signal) ? .orange : .teal
    }
}

enum TodayPresentation {
    static func agendaEvents(
        from snapshot: DashboardSnapshot,
        academicSignals: [AcademicSignalRecord],
        on date: Date,
        timeZone: TimeZone, manualEvents: [ManualEvent] = []
    ) -> [CalendarEvent] {
        let range = CalendarDateMath.range(for: .day, anchor: date, timeZone: timeZone)
        return (CalendarPresentation.events(from: snapshot, academicSignals: academicSignals) + manualEvents.map(\.calendarEvent)).sorted { $0.start < $1.start }.filter {
            $0.start < range.end && $0.end > range.start
        }
    }

    static func dueTasks(
        from snapshot: DashboardSnapshot,
        on date: Date,
        timeZone: TimeZone
    ) -> [LearningTask] {
        let calendar = CalendarDateMath.calendar(timeZone: timeZone)
        return snapshot.tasks.filter {
            !$0.isPlaceholder && $0.officialDueAt.map { calendar.isDate($0, inSameDayAs: date) } == true
        }.sorted {
            ($0.officialDueAt ?? .distantFuture, $0.id.uuidString)
                < ($1.officialDueAt ?? .distantFuture, $1.id.uuidString)
        }
    }

    static func scheduleUpdates(_ signals: [AcademicSignalRecord]) -> [AcademicSignalRecord] {
        signals.filter { signal in
            let category = signal.adoptedCategory ?? signal.category
            return [.courseScheduleChange, .makeupClass].contains(category)
                && ![.rejected, .undone, .notRequired].contains(signal.confirmationState)
        }.sorted { lhs, rhs in
            let lhsNeedsReview = NeedsReviewPolicy.includes(lhs)
            let rhsNeedsReview = NeedsReviewPolicy.includes(rhs)
            if lhsNeedsReview != rhsNeedsReview { return lhsNeedsReview }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
