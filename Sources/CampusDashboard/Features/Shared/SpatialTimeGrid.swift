import SwiftUI

struct SpatialTimeGrid: View {
    let days: [Date]
    let events: [CalendarEvent]
    let language: AppLanguage
    let timeZone: TimeZone
    let now: Date
    let showsAllDay: Bool
    let select: (CalendarEvent) -> Void

    private let configuration = TimeGridConfiguration.campusDay
    private let gutterWidth: CGFloat = 44
    private let headerHeight: CGFloat = 52
    private let allDayHeight: CGFloat = 46
    private let timedHeight: CGFloat = 720

    var body: some View {
        GeometryReader { proxy in
            let gridWidth = max(proxy.size.width - gutterWidth, CGFloat(days.count) * 66)
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    dateHeaders(width: gridWidth)
                    if showsAllDay { allDayArea(width: gridWidth) }
                    HStack(alignment: .top, spacing: 0) {
                        timeGutter
                        timedGrid(width: gridWidth)
                    }
                }
                .frame(width: gutterWidth + gridWidth)
            }
        }
        .frame(height: headerHeight + (showsAllDay ? allDayHeight : 0) + timedHeight)
        .accessibilityElement(children: .contain)
    }

    private func dateHeaders(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth)
            ForEach(days, id: \.self) { day in
                let isToday = CalendarDateMath.calendar(timeZone: timeZone).isDate(day, inSameDayAs: now)
                VStack(spacing: 2) {
                    Text(Localizer.weekday(day, width: .abbreviated, language: language, timeZone: timeZone))
                        .font(.caption.weight(.semibold))
                    Text(String(CalendarDateMath.calendar(timeZone: timeZone).component(.day, from: day)))
                        .font(.title3.weight(isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color.accentColor : .primary)
                }
                .frame(width: width / CGFloat(days.count), height: headerHeight)
                .background(isToday ? Color.accentColor.opacity(0.08) : .clear)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func allDayArea(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(Localizer.text("All-day", language: language))
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: gutterWidth, height: allDayHeight, alignment: .topTrailing)
                .padding(.top, 5)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach(allDayEvents(on: day).prefix(2)) { event in
                        Button { select(event) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: eventSymbol(event)).font(.system(size: 8))
                                Text(event.title).font(.caption2).lineLimit(1)
                            }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(eventColor(event).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(3)
                .frame(width: width / CGFloat(days.count), height: allDayHeight, alignment: .top)
                .overlay(alignment: .leading) { Divider() }
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var timeGutter: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(configuration.startHour...configuration.endHour, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .offset(y: CGFloat(hour - configuration.startHour) / CGFloat(configuration.endHour - configuration.startHour) * timedHeight - 6)
            }
        }
        .frame(width: gutterWidth, height: timedHeight, alignment: .topTrailing)
        .padding(.trailing, 5)
    }

    private func timedGrid(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            gridLines(width: width)
            ForEach(Array(days.enumerated()), id: \.offset) { dayIndex, day in
                dayEvents(day: day, dayIndex: dayIndex, width: width)
                if let fraction = TimeGridLayout.currentTimeFraction(now: now, day: day, timeZone: timeZone) {
                    Rectangle().fill(Color.red).frame(width: width / CGFloat(days.count), height: 1.5)
                        .offset(x: CGFloat(dayIndex) * width / CGFloat(days.count), y: fraction * timedHeight)
                        .accessibilityLabel(Localizer.text("Current time", language: language))
                }
            }
        }
        .frame(width: width, height: timedHeight)
        .clipped()
    }

    private func gridLines(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...(configuration.endHour - configuration.startHour), id: \.self) { index in
                Rectangle().fill(Color.secondary.opacity(0.16)).frame(width: width, height: 1)
                    .offset(y: CGFloat(index) / CGFloat(configuration.endHour - configuration.startHour) * timedHeight)
            }
            ForEach(0...days.count, id: \.self) { index in
                Rectangle().fill(Color.secondary.opacity(0.12)).frame(width: 1, height: timedHeight)
                    .offset(x: CGFloat(index) / CGFloat(days.count) * width)
            }
        }
    }

    private func dayEvents(day: Date, dayIndex: Int, width: CGFloat) -> some View {
        let placements = TimeGridLayout.placements(events: events, day: day, timeZone: timeZone)
        let columnWidth = width / CGFloat(days.count)
        return ForEach(placements) { placement in
            let laneWidth = max(18, (columnWidth - 4) / CGFloat(placement.laneCount))
            Button { select(placement.event) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        Image(systemName: eventSymbol(placement.event)).font(.system(size: 8))
                        Text(placement.event.title).font(.system(size: 10, weight: .semibold)).lineLimit(2)
                    }
                    Text(timeRange(placement)).font(.system(size: 8)).lineLimit(1)
                    if !placement.event.location.isEmpty {
                        Text(placement.event.location).font(.system(size: 8)).lineLimit(1)
                    }
                }
                .padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(placement.event.isCancelled ? .secondary : .primary)
                .background(eventColor(placement.event).opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .leading) {
                    Rectangle().fill(eventColor(placement.event)).frame(width: 3)
                }
                .overlay {
                    if placement.event.isCancelled {
                        RoundedRectangle(cornerRadius: 5).stroke(style: StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                }
            }
            .buttonStyle(.plain)
            .help(placement.event.title + " · " + timeRange(placement))
            .accessibilityLabel(eventAccessibility(placement))
            .frame(width: laneWidth, height: max(16, placement.heightFraction * timedHeight))
            .offset(
                x: CGFloat(dayIndex) * columnWidth + 2 + CGFloat(placement.lane) * laneWidth,
                y: placement.topFraction * timedHeight
            )
        }
    }

    private func allDayEvents(on day: Date) -> [CalendarEvent] {
        let cal = CalendarDateMath.calendar(timeZone: timeZone)
        return events.filter { $0.isAllDay && cal.isDate($0.start, inSameDayAs: day) }
    }

    private func timeRange(_ placement: TimeGridPlacement) -> String {
        let full = Localizer.format(placement.event.start, date: .omitted, language: language, timeZone: timeZone)
            + "–" + Localizer.format(placement.event.end, date: .omitted, language: language, timeZone: timeZone)
        let prefix = placement.clipsStart ? "↥ " : ""
        let suffix = placement.clipsEnd ? " ↧" : ""
        return prefix + full + suffix
    }

    private func eventAccessibility(_ placement: TimeGridPlacement) -> String {
        var parts = [eventKindLabel(placement.event), placement.event.title, timeRange(placement)]
        if !placement.event.location.isEmpty { parts.append(placement.event.location) }
        if placement.event.isCancelled { parts.append(Localizer.text("Cancelled", language: language)) }
        if placement.clipsStart { parts.append(Localizer.text("Clipped at visible start", language: language)) }
        if placement.clipsEnd { parts.append(Localizer.text("Clipped at visible end", language: language)) }
        return parts.joined(separator: ", ")
    }

    private func eventColor(_ event: CalendarEvent) -> Color {
        switch event.kind {
        case .manual: .green
        case .courseMeeting: event.source == .canvas ? .red : .blue
        case .officialDeadline: .red
        case .confirmedInferredDeadline: .purple
        case .confirmedExam: .orange
        case .confirmedScheduleChange: .teal
        }
    }

    private func eventSymbol(_ event: CalendarEvent) -> String {
        switch event.kind {
        case .manual: "pencil"; case .courseMeeting: "person.2"
        case .officialDeadline: "exclamationmark.circle.fill"
        case .confirmedInferredDeadline: "checkmark.sparkles"
        case .confirmedExam: "graduationcap.fill"
        case .confirmedScheduleChange: "arrow.triangle.2.circlepath"
        }
    }

    private func eventKindLabel(_ event: CalendarEvent) -> String {
        let key = switch event.kind {
        case .manual: "Manual event"; case .courseMeeting: "Course meeting"
        case .officialDeadline: "Official deadline"
        case .confirmedInferredDeadline: "Confirmed inferred deadline"
        case .confirmedExam: "Confirmed exam"
        case .confirmedScheduleChange: "Confirmed schedule change"
        }
        return Localizer.text(key, language: language)
    }
}
