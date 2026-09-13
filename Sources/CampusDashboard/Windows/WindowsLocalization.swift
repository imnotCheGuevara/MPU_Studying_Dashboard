#if os(Windows)
import Foundation

enum WindowsLanguage: String, CaseIterable, Equatable, Sendable {
    case english
    case simplifiedChinese

    static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        guard let preferred = preferredLanguages.first?.lowercased() else { return .english }
        if preferred.hasPrefix("zh-hans") || preferred.hasPrefix("zh-cn") || preferred.hasPrefix("zh-sg") {
            return .simplifiedChinese
        }
        return .english
    }
}

final class WindowsLanguageStore: @unchecked Sendable {
    private static let languageKey = "WindowsLanguage"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(preferredLanguages: [String] = Locale.preferredLanguages) -> WindowsLanguage {
        guard let rawValue = defaults.string(forKey: Self.languageKey),
              let saved = WindowsLanguage(rawValue: rawValue)
        else {
            return .systemDefault(preferredLanguages: preferredLanguages)
        }
        return saved
    }

    func save(_ language: WindowsLanguage) {
        defaults.set(language.rawValue, forKey: Self.languageKey)
    }
}

struct WindowsCopy: Sendable {
    let language: WindowsLanguage

    func text(_ english: String, _ simplifiedChinese: String) -> String {
        language == .simplifiedChinese ? simplifiedChinese : english
    }

    var locale: Locale {
        Locale(identifier: language == .simplifiedChinese ? "zh_Hans_CN" : "en_US")
    }

    var previewStatus: String {
        text(
            "Preview data is active. Connect Canvas for a live read-only sync.",
            "当前显示预览数据。连接 Canvas 后可进行实时只读同步。"
        )
    }

    var offlineStatus: String {
        text(
            "Saved Canvas data is available offline. Sync to refresh it.",
            "已保存的 Canvas 数据可离线查看。同步即可刷新数据。"
        )
    }

    var unreadableSnapshotStatus: String {
        text(
            "Saved Canvas data could not be loaded. Preview data is active.",
            "无法读取已保存的 Canvas 数据，当前显示预览数据。"
        )
    }

    var syncingStatus: String {
        text("Syncing Canvas read-only data…", "正在同步 Canvas 只读数据……")
    }

    func syncedStatus(courses: Int, tasks: Int, announcements: Int) -> String {
        text(
            "Canvas synced and saved for offline use: \(courses) courses, \(tasks) tasks, \(announcements) announcements.",
            "Canvas 已同步并保存供离线使用：\(courses) 门课程、\(tasks) 项任务、\(announcements) 条公告。"
        )
    }

    var snapshotSaveFailedStatus: String {
        text(
            "Canvas synced, but its offline copy could not be saved.",
            "Canvas 已同步，但无法保存离线副本。"
        )
    }

    func syncFailedStatus(_ detail: String) -> String {
        text("Canvas sync failed: \(detail)", "Canvas 同步失败：\(detail)")
    }

    var removalPartialStatus: String {
        text(
            "Some saved Canvas data could not be removed. Close the app and try again.",
            "部分 Canvas 数据无法删除。请关闭应用后重试。"
        )
    }

    var removedStatus: String {
        text(
            "Canvas credentials and offline data removed. Preview data is active.",
            "Canvas 凭据和离线数据已删除，当前显示预览数据。"
        )
    }

    func priority(_ priority: TaskPriority) -> String {
        switch priority {
        case .low: text("Low", "低")
        case .medium: text("Medium", "中")
        case .high: text("High", "高")
        }
    }

    func taskKind(_ kind: TaskKind) -> String {
        switch kind {
        case .assignment: text("Assignment", "作业")
        case .quiz: text("Quiz", "测验")
        case .reading: text("Reading", "阅读")
        }
    }

    func sourceHealthDetail(_ detail: String) -> String {
        guard language == .simplifiedChinese else { return detail }
        switch detail {
        case "Read-only sync completed": return "只读同步已完成"
        case "Windows sign-in adapter is not available yet": return "Windows 登录适配器尚未完成"
        default: return detail
        }
    }

    func reminderDetail(_ reminder: WindowsInAppReminder) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let due = formatter.string(from: reminder.dueAt)
        let source = reminder.usesConfirmedSuggestion
            ? text("confirmed suggestion", "已确认的建议日期")
            : text("official date", "官方日期")

        switch reminder.urgency {
        case .overdue:
            return text("Overdue · \(due) · \(source)", "已逾期 · \(due) · \(source)")
        case .dueWithinHour:
            return text("Due within 1 hour · \(due) · \(source)", "1 小时内到期 · \(due) · \(source)")
        case .dueToday:
            return text("Due within 24 hours · \(due) · \(source)", "24 小时内到期 · \(due) · \(source)")
        case .upcoming:
            return text("Due within 7 days · \(due) · \(source)", "7 天内到期 · \(due) · \(source)")
        }
    }
}
#endif
