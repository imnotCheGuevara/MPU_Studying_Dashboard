#if os(Windows)
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

public struct CampusDashboardWindowsRootView: View {
    @State private var selectedSection: WindowsSection? = .today
    @State private var state = WindowsDashboardState()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Campus Dashboard")
                    .font(.title2)
                    .emphasized()
                Text(state.isShowingPreview ? "Windows · preview data" : "Windows · Canvas connected")
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
                        TodayPreview(snapshot: state.snapshot)
                    case .schedule:
                        SchedulePreview(snapshot: state.snapshot)
                    case .tasks:
                        TasksPreview(snapshot: state.snapshot)
                    case .announcements:
                        AnnouncementsPreview(snapshot: state.snapshot)
                    case .needsReview:
                        NeedsReviewPreview(snapshot: state.snapshot)
                    case .settings:
                        SettingsView(state: state)
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
                SummaryCard(value: "\(snapshot.courses.count)", label: "Courses")
                SummaryCard(value: "\(snapshot.tasks.filter(\.appearsInNormalTaskList).count)", label: "Tasks")
                SummaryCard(value: "\(snapshot.announcements.filter { !$0.isLocallyRead }.count)", label: "Unread")
            }

            Text("Courses")
                .font(.headline)
            ForEach(Array(snapshot.courses.prefix(3)), id: \.id) { course in
                ContentRow(
                    title: course.name,
                    detail: [course.code, course.term].filter { !$0.isEmpty }.joined(separator: " · ")
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
            if snapshot.meetings.isEmpty {
                ContentRow(
                    title: "No timetable data on Windows yet",
                    detail: "SIweb sign-in is intentionally disabled until a safe Windows adapter is available."
                )
            } else {
                ForEach(snapshot.meetings, id: \.id) { meeting in
                    ContentRow(
                        title: meeting.isCancelled ? "Cancelled · \(meeting.title)" : meeting.title,
                        detail: meeting.location
                    )
                }
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

private struct SettingsView: View {
    let state: WindowsDashboardState

    private var baseURLBinding: Binding<String> {
        Binding { state.canvasBaseURL } set: { state.canvasBaseURL = $0 }
    }

    private var tokenBinding: Binding<String> {
        Binding { state.canvasToken } set: { state.canvasToken = $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle("设置 · Settings", subtitle: "Connect Canvas with read-only access")
            Text("Canvas HTTPS URL")
                .font(.headline)
            TextField("https://canvas.example.edu", text: baseURLBinding)
                .frame(maxWidth: 560)
            Text("Canvas access token")
                .font(.headline)
            SecureField(
                state.hasSavedCanvasToken ? "Saved securely — leave blank to reuse" : "Paste token once",
                text: tokenBinding
            )
            .frame(maxWidth: 560)

            HStack(spacing: 12) {
                Button(state.isSyncing ? "Syncing…" : "Save and sync") {
                    Task { await state.synchronizeCanvas() }
                }
                .disabled(state.isSyncing)
                Button("Forget Canvas") {
                    state.forgetCanvas()
                }
                .disabled(state.isSyncing || !state.hasSavedCanvasToken)
            }

            Text(state.statusMessage)
                .font(.subheadline)
            ContentRow(
                title: "Windows privacy boundary",
                detail: "Token: Windows Credential Manager · Data: read-only Canvas · No iCloud, Apple Calendar, Outlook, or external calendar writes"
            )
            ForEach(state.snapshot.sourceHealth, id: \.id) { source in
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

#endif
