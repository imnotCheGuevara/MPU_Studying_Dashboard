import SwiftUI

struct ManualEventEditor: View {
    @ObservedObject var model: DashboardModel
    @State var event: ManualEvent
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar {
        CalendarDateMath.calendar(timeZone: model.presentationTimeZone)
    }

    private var earliestEnd: Date {
        event.isAllDay ? calendar.startOfDay(for: event.start) : event.start
    }

    private var validEnd: Bool {
        event.isAllDay
            ? calendar.startOfDay(for: event.end) >= calendar.startOfDay(for: event.start)
            : event.end > event.start
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.text("Manual event")).font(.title2.bold())
            Form {
                TextField(model.text("Event title"), text: $event.title)
                Toggle(model.text("All-day"), isOn: $event.isAllDay)
                DatePicker(model.text("Starts"), selection: $event.start,
                           displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker(model.text("Ends"), selection: $event.end,
                           in: earliestEnd...,
                           displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                TextField(model.text("Location"), text: $event.location)
            }
            .environment(\.timeZone, model.presentationTimeZone)
            if event.isAllDay {
                Text(model.text("The end date is included.")).font(.caption).foregroundStyle(.secondary)
            }
            Text(model.text("Saved in Dashboard only.")).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(model.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.text("Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validEnd)
            }
        }
        .padding(24).frame(width: 460)
        .onChange(of: event.start) { _, _ in
            event.end = earliestEnd
            error = nil
        }
        .onChange(of: event.isAllDay) { _, _ in
            if !validEnd { event.end = earliestEnd }
            error = nil
        }
        .onAppear {
            // Stored all-day end is exclusive; the editor shows the last included date.
            if event.isAllDay { event.end = calendar.date(byAdding: .day, value: -1, to: event.end) ?? event.end }
        }
    }

    private func save() {
        var value = event
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.location = value.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isAllDay {
            value.start = calendar.startOfDay(for: value.start)
            value.end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: value.end)) ?? value.end
        }
        do { try value.validate() }
        catch { self.error = model.text("Enter a title and an end time after the start."); return }
        do { try model.saveManualEvent(value); dismiss() }
        catch { self.error = model.text("Event could not be saved. Please try again.") }
    }
}
