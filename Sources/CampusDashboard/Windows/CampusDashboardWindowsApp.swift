#if os(Windows)
import DefaultBackend
import Foundation
import SwiftCrossUI

private enum WindowsSection: String, CaseIterable, Identifiable {
    case today
    case schedule
    case tasks
    case announcements
    case needsReview
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日 · Today"
        case .schedule: "日程 · Schedule"
        case .tasks: "任务 · Tasks"
        case .announcements: "公告 · Announcements"
        case .needsReview: "待确认 · Needs Review"
        case .settings: "设置 · Settings"
        }
    }
}

private struct WindowsRootView: View {
    @State private var selectedSection: WindowsSection? = .today

    private let snapshot = SyntheticFixtures.populated

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Campus Dashboard")
                    .font(.title2)
                    .emphasized()
                Text("Windows preview · synthetic data")
                    .font(.caption)
                Divider()
                List(WindowsSection.allCases, selection: $selectedSection) { section in
                    Text(section.title)
                }
            }
            .padding(16)
            .frame(minWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSection ?? .today {
                    case .today:
                        TodayPreview(snapshot: snapshot)
                    case .schedule:
                        SchedulePreview(snapshot: snapshot)
                    case .tasks:
                        TasksPreview(snapshot: snapshot)
                    case .announcements:
                        AnnouncementsPreview(snapshot: snapshot)
                    case .needsReview:
                        NeedsReviewPreview(snapshot: snapshot)
                    case .settings:
                        SettingsPreview(snapshot: snapshot)
                    }
                }
                .padding(24)
            }
        }
    }
}

private struct TodayPreview: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle("今日 · Today", subtitle: "One focused view of classes and work")

            HStack(spacing: 16) {
                SummaryCard(value: "\(snapshot.meetings.filter { !$0.isCancelled }.count)", label: "Classes")
                SummaryCard(value: "\(snapshot.tasks.filter(\.appearsInNormalTaskList).count)", label: "Tasks")
                SummaryCard(value: "\(snapshot.announcements.filter { !$0.isLocallyRead }.count)", label: "Unread")
            }

            Text("Next classes")
                .font(.headline)
            ForEach(Array(snapshot.meetings.filter { !$0.isCancelled }.prefix(2)), id: \.id) { meeting in
                ContentRow(
                    title: meeting.title,
                    detail: "\(Self.time(meeting.start))–\(Self.time(meeting.end)) · \(meeting.location)"
                )
            }

            Text("Priority work")
                .font(.headline)
            ForEach(Array(snapshot.tasks.filter(\.appearsInNormalTaskList).prefix(2)), id: \.id) { task in
                ContentRow(
                    title: task.title,
                    detail: "\(task.localPriority.rawValue) · \(Self.dateTime(task.officialDueAt))"
                )
            }
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func dateTime(_ date: Date?) -> String {
        guard let date else { return "No official due date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct SchedulePreview: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle("日程 · Schedule", subtitle: "Local in-app schedule")
            ForEach(snapshot.meetings, id: \.id) { meeting in
                ContentRow(
                    title: meeting.isCancelled ? "Cancelled · \(meeting.title)" : meeting.title,
                    detail: meeting.location
                )
            }
        }
    }
}

private struct TasksPreview: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle("任务 · Tasks", subtitle: "Official dates remain authoritative")
            ForEach(snapshot.tasks.filter(\.appearsInNormalTaskList), id: \.id) { task in
                ContentRow(title: task.title, detail: "\(task.kind.rawValue) · \(task.localPriority.rawValue)")
            }
        }
    }
}

private struct AnnouncementsPreview: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle("公告 · Announcements", subtitle: "Complete read-only source feed")
            ForEach(snapshot.announcements, id: \.id) { announcement in
                ContentRow(title: announcement.title, detail: announcement.summary)
            }
        }
    }
}

private struct NeedsReviewPreview: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle("待确认 · Needs Review", subtitle: "Inferred dates never apply automatically")
            ForEach(snapshot.confirmations, id: \.id) { candidate in
                ContentRow(title: candidate.suggestion, detail: candidate.rationale)
            }
        }
    }
}

private struct SettingsPreview: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle("设置 · Settings", subtitle: "Windows platform slice")
            ContentRow(title: "Canvas + SIweb", detail: "Read-only source boundary")
            ContentRow(title: "App schedule", detail: "Kept locally inside Campus Dashboard")
            ForEach(snapshot.sourceHealth, id: \.id) { source in
                ContentRow(title: source.source.rawValue, detail: source.detail)
            }
        }
    }
}

private struct ScreenTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title)
                .emphasized()
            Text(subtitle)
                .font(.subheadline)
        }
    }
}

private struct SummaryCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2)
                .emphasized()
            Text(label)
                .font(.caption)
        }
        .padding(12)
        .frame(minWidth: 120, alignment: .leading)
    }
}

private struct ContentRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.body)
        }
        .padding(12)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

@main
struct CampusDashboardWindowsApp: App {
    var body: some Scene {
        WindowGroup("Campus Dashboard") {
            WindowsRootView()
        }
        .defaultSize(width: 1100, height: 720)
    }
}
#endif
