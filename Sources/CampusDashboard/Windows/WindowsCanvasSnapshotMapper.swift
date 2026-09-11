#if os(Windows)
import Foundation

struct WindowsCanvasSnapshotMapper {
    func map(_ source: CanvasConnectorSnapshot, accountID: String, syncedAt: Date) -> DashboardSnapshot {
        var courseIDs: [String: UUID] = [:]
        let courses = source.courses.map { payload in
            let id = UUID()
            courseIDs[payload.sourceObjectID] = id
            return Course(
                id: id,
                sourceAccountID: accountID,
                sourceObjectID: payload.sourceObjectID,
                name: payload.name,
                code: payload.code,
                term: payload.term,
                colorName: "blue",
                sourceURL: payload.sourceURL?.absoluteString
            )
        }

        let tasks = source.tasks.compactMap { payload -> LearningTask? in
            guard let courseID = courseIDs[payload.courseSourceObjectID] else { return nil }
            return LearningTask(
                id: UUID(),
                sourceAccountID: accountID,
                sourceObjectID: payload.sourceObjectID,
                courseID: courseID,
                title: payload.title,
                kind: taskKind(payload.officialType),
                officialDueAt: payload.officialDueAt,
                suggestedCompleteAt: nil,
                suggestedDateConfirmed: false,
                source: .canvas,
                isLocallyComplete: false,
                localPriority: priority(payload.officialDueAt, relativeTo: syncedAt),
                sourceURL: payload.sourceURL?.absoluteString,
                isPlaceholder: payload.placeholderEvidence.classifiesAsPlaceholder(dueAt: payload.officialDueAt)
            )
        }.sorted { lhs, rhs in
            switch (lhs.officialDueAt, rhs.officialDueAt) {
            case let (left?, right?): left < right
            case (nil, nil): lhs.title < rhs.title
            case (nil, _): false
            case (_, nil): true
            }
        }

        let announcements = source.announcements.compactMap { payload -> Announcement? in
            guard let courseID = courseIDs[payload.courseSourceObjectID] else { return nil }
            return Announcement(
                id: UUID(),
                sourceObjectID: payload.sourceObjectID,
                courseID: courseID,
                title: payload.title,
                summary: payload.summary,
                publishedAt: payload.publishedAt ?? payload.updatedAt ?? .distantPast,
                source: .canvas,
                isLocallyRead: false,
                sourceURL: payload.sourceURL?.absoluteString
            )
        }.sorted { $0.publishedAt > $1.publishedAt }

        return DashboardSnapshot(
            sourceHealth: [
                SourceHealth(
                    id: UUID(),
                    source: .canvas,
                    level: .healthy,
                    detail: "Read-only sync completed",
                    lastSuccessfulSync: syncedAt
                ),
                SourceHealth(
                    id: UUID(),
                    source: .siweb,
                    level: .unavailable,
                    detail: "Windows sign-in adapter is not available yet",
                    lastSuccessfulSync: nil
                )
            ],
            courses: courses,
            meetings: [],
            tasks: tasks,
            announcements: announcements,
            confirmations: []
        )
    }

    private func taskKind(_ officialType: String) -> TaskKind {
        officialType.contains("quiz") ? .quiz : .assignment
    }

    private func priority(_ dueAt: Date?, relativeTo now: Date) -> TaskPriority {
        guard let dueAt else { return .low }
        let interval = dueAt.timeIntervalSince(now)
        if interval <= 3 * 24 * 60 * 60 { return .high }
        if interval <= 7 * 24 * 60 * 60 { return .medium }
        return .low
    }
}
#endif
