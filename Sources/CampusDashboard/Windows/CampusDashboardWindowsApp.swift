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

    func title(_ copy: WindowsCopy) -> String {
        switch self {
        case .today: copy.text("Today", "今日")
        case .schedule: copy.text("Schedule", "日程")
        case .tasks: copy.text("Tasks", "任务")
        case .announcements: copy.text("Announcements", "公告")
        case .needsReview: copy.text("Needs Review", "待确认")
        case .settings: copy.text("Settings", "设置")
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
                Text(state.isShowingPreview
                     ? state.copy.text("Windows · preview data", "Windows · 预览数据")
                     : state.copy.text("Windows · saved source data", "Windows · 已保存来源数据"))
                    .font(.caption)
                Divider()
                List(WindowsSection.allCases, selection: $selectedSection) { section in
                    Text(section.title(state.copy))
                }
            }
            .padding(16)
            .frame(minWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSection ?? .today {
                    case .today:
                        TodayPreview(snapshot: state.snapshot, copy: state.copy)
                    case .schedule:
                        SchedulePreview(snapshot: state.snapshot, copy: state.copy)
                    case .tasks:
                        TasksPreview(snapshot: state.snapshot, copy: state.copy)
                    case .announcements:
                        AnnouncementsPreview(snapshot: state.snapshot, copy: state.copy)
                    case .needsReview:
                        NeedsReviewPreview(snapshot: state.snapshot, copy: state.copy)
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
    let copy: WindowsCopy

    private var reminders: [WindowsInAppReminder] {
        WindowsInAppReminderEngine().reminders(in: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(
                copy.text("Today", "今日"),
                subtitle: copy.text("One focused view of classes and work", "集中查看课程和任务")
            )

            HStack(spacing: 16) {
                SummaryCard(value: "\(snapshot.courses.count)", label: copy.text("Courses", "课程"))
                SummaryCard(value: "\(snapshot.tasks.filter(\.appearsInNormalTaskList).count)", label: copy.text("Tasks", "任务"))
                SummaryCard(value: "\(snapshot.announcements.filter { !$0.isLocallyRead }.count)", label: copy.text("Unread", "未读"))
            }

            Text(copy.text("In-app reminders", "应用内提醒"))
                .font(.headline)
            if reminders.isEmpty {
                ContentRow(
                    title: copy.text("Nothing urgent", "暂无紧急事项"),
                    detail: copy.text(
                        "Incomplete tasks due within seven days appear here. This beta does not run a background reminder service.",
                        "七天内到期且未完成的任务会显示在这里。此测试版不会运行后台提醒服务。"
                    )
                )
            } else {
                ForEach(Array(reminders.prefix(5)), id: \.id) { reminder in
                    ContentRow(title: reminder.title, detail: copy.reminderDetail(reminder))
                }
            }

            Text(copy.text("Courses", "课程"))
                .font(.headline)
            ForEach(Array(snapshot.courses.prefix(3)), id: \.id) { course in
                ContentRow(
                    title: course.name,
                    detail: [course.code, course.term].filter { !$0.isEmpty }.joined(separator: " · ")
                )
            }

            Text(copy.text("Priority work", "优先任务"))
                .font(.headline)
            ForEach(Array(snapshot.tasks.filter(\.appearsInNormalTaskList).prefix(2)), id: \.id) { task in
                ContentRow(
                    title: task.title,
                    detail: "\(copy.priority(task.localPriority)) · \(dateTime(task.officialDueAt))"
                )
            }
        }
    }

    private func dateTime(_ date: Date?) -> String {
        guard let date else { return copy.text("No official due date", "没有官方截止日期") }
        let formatter = DateFormatter()
        formatter.locale = copy.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct SchedulePreview: View {
    let snapshot: DashboardSnapshot
    let copy: WindowsCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(
                copy.text("Schedule", "日程"),
                subtitle: copy.text("Local in-app schedule", "仅在应用内显示的日程")
            )
            if snapshot.meetings.isEmpty {
                ContentRow(
                    title: copy.text("No timetable data on Windows yet", "Windows 版暂时没有课程表数据"),
                    detail: copy.text(
                        "Connect the SIweb read-only beta adapter in Settings to load the timetable.",
                        "可在设置中连接 SIweb 只读测试适配器，以加载课程表。"
                    )
                )
            } else {
                ForEach(snapshot.meetings, id: \.id) { meeting in
                    ContentRow(
                        title: meeting.isCancelled
                            ? "\(copy.text("Cancelled", "已取消")) · \(meeting.title)"
                            : meeting.title,
                        detail: meeting.location
                    )
                }
            }
        }
    }
}

private struct TasksPreview: View {
    let snapshot: DashboardSnapshot
    let copy: WindowsCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(
                copy.text("Tasks", "任务"),
                subtitle: copy.text("Official dates remain authoritative", "官方日期始终是最终依据")
            )
            ForEach(snapshot.tasks.filter(\.appearsInNormalTaskList), id: \.id) { task in
                ContentRow(
                    title: task.title,
                    detail: "\(copy.taskKind(task.kind)) · \(copy.priority(task.localPriority))"
                )
            }
        }
    }
}

private struct AnnouncementsPreview: View {
    let snapshot: DashboardSnapshot
    let copy: WindowsCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(
                copy.text("Announcements", "公告"),
                subtitle: copy.text("Complete read-only source feed", "完整的只读来源信息流")
            )
            ForEach(snapshot.announcements, id: \.id) { announcement in
                ContentRow(title: announcement.title, detail: announcement.summary)
            }
        }
    }
}

private struct NeedsReviewPreview: View {
    let snapshot: DashboardSnapshot
    let copy: WindowsCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(
                copy.text("Needs Review", "待确认"),
                subtitle: copy.text("Inferred dates never apply automatically", "推断日期绝不会自动应用")
            )
            ForEach(snapshot.confirmations, id: \.id) { candidate in
                ContentRow(title: candidate.suggestion, detail: candidate.rationale)
            }
        }
    }
}

private struct SettingsView: View {
    let state: WindowsDashboardState
    @Environment(\.openURL) private var openURL

    private var baseURLBinding: Binding<String> {
        Binding { state.canvasBaseURL } set: { state.canvasBaseURL = $0 }
    }

    private var tokenBinding: Binding<String> {
        Binding { state.canvasToken } set: { state.canvasToken = $0 }
    }

    private var siwebSessionBinding: Binding<String> {
        Binding { state.siwebSession } set: { state.siwebSession = $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(
                state.copy.text("Settings", "设置"),
                subtitle: state.copy.text("Connect read-only school sources", "以只读方式连接学校数据来源")
            )
            Text(state.copy.text("Language", "语言"))
                .font(.headline)
            HStack(spacing: 12) {
                Button("English") { state.selectLanguage(.english) }
                    .disabled(state.language == .english)
                Button("简体中文") { state.selectLanguage(.simplifiedChinese) }
                    .disabled(state.language == .simplifiedChinese)
            }
            Text(state.copy.text("Canvas HTTPS URL", "Canvas HTTPS 地址"))
                .font(.headline)
            TextField("https://canvas.example.edu", text: baseURLBinding)
                .frame(maxWidth: 560)
            Text(state.copy.text("Canvas access token", "Canvas 访问令牌"))
                .font(.headline)
            SecureField(
                state.hasSavedCanvasToken
                    ? state.copy.text("Saved securely — leave blank to reuse", "已安全保存——留空即可继续使用")
                    : state.copy.text("Paste token once", "只需粘贴一次令牌"),
                text: tokenBinding
            )
            .frame(maxWidth: 560)

            HStack(spacing: 12) {
                Button(state.isSyncing
                       ? state.copy.text("Syncing…", "正在同步……")
                       : state.copy.text("Save and sync", "保存并同步")) {
                    Task { await state.synchronizeCanvas() }
                }
                .disabled(state.isSyncing)
                Button(state.copy.text("Forget Canvas", "忘记 Canvas")) {
                    state.forgetCanvas()
                }
                .disabled(state.isSyncing || (!state.hasSavedCanvasToken && state.isShowingPreview))
            }
            Divider()
            Text(state.copy.text("SIweb timetable · advanced beta", "SIweb 课程表 · 高级测试版"))
                .font(.headline)
            Text(state.copy.text(
                "1. Open SIweb and sign in normally. 2. In browser Developer Tools > Network, reload the timetable page and select time_stud.asp. 3. Under Request Headers, copy only the value after Cookie:. Never paste it into chat, logs, or an issue.",
                "1. 打开 SIweb 并正常登录。2. 在浏览器开发者工具 > 网络中重新加载课程表，并选择 time_stud.asp。3. 在请求标头中只复制 Cookie: 后面的值。绝不要把它粘贴到聊天、日志或 Issue。"
            ))
                .font(.body)
            Button(state.copy.text("Open SIweb in browser", "在浏览器中打开 SIweb")) {
                openURL(MPUSIwebEndpoints.publishedEntryURL)
            }
            SecureField(
                state.hasSavedSIwebSession
                    ? state.copy.text("Saved securely — leave blank to reuse", "已安全保存——留空即可继续使用")
                    : state.copy.text("Cookie value: name=value; name2=value2", "Cookie 值：name=value; name2=value2"),
                text: siwebSessionBinding
            )
            .frame(maxWidth: 560)
            HStack(spacing: 12) {
                Button(state.isSyncing
                       ? state.copy.text("Syncing…", "正在同步……")
                       : state.copy.text("Save session and sync", "保存会话并同步")) {
                    Task { await state.synchronizeSIweb() }
                }
                .disabled(state.isSyncing)
                Button(state.copy.text("Forget SIweb", "忘记 SIweb")) {
                    state.forgetSIweb()
                }
                .disabled(state.isSyncing || !state.hasSavedSIwebSession)
            }

            Text(state.statusMessage)
                .font(.subheadline)
            ContentRow(
                title: state.copy.text("Windows privacy boundary", "Windows 隐私边界"),
                detail: state.copy.text(
                    "Canvas token and SIweb session: Windows Credential Manager · Offline data: local app folder · Read-only sources · No iCloud, Apple Calendar, Outlook, or external calendar writes",
                    "Canvas 令牌和 SIweb 会话：Windows 凭据管理器 · 离线数据：本地应用文件夹 · 数据来源只读 · 不使用 iCloud、Apple 日历、Outlook，也不写入任何外部日历"
                )
            )
            ForEach(state.snapshot.sourceHealth, id: \.id) { source in
                ContentRow(title: source.source.rawValue, detail: state.copy.sourceHealthDetail(source.detail))
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
