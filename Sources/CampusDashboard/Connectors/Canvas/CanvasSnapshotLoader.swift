import Foundation

struct CanvasConnectorSnapshot: Equatable, Sendable {
    let courses: [CanvasCoursePayload]
    let tasks: [CanvasTaskPayload]
    let announcements: [CanvasAnnouncementPayload]
}

/// Collects a bounded, connector-only read snapshot. It deliberately performs no
/// persistence, deletion inference, scheduling, or downstream side effects.
struct CanvasSnapshotLoader: Sendable {
    let service: any CanvasService
    let maximumPagesPerCollection: Int

    init(service: any CanvasService, maximumPagesPerCollection: Int = 1_000) {
        self.service = service
        self.maximumPagesPerCollection = maximumPagesPerCollection
    }

    func load() async throws -> CanvasConnectorSnapshot {
        let courses = try await collect { token in try await service.courses(pageToken: token) }
        var taskByID: [String: CanvasTaskPayload] = [:]
        var announcementByID: [String: CanvasAnnouncementPayload] = [:]
        for course in courses {
            for task in try await collect({ token in
                try await service.learningTasks(courseID: course.sourceObjectID, pageToken: token)
            }) {
                taskByID[task.sourceObjectID] = task
            }
            for announcement in try await collect({ token in
                try await service.announcements(courseID: course.sourceObjectID, pageToken: token)
            }) {
                announcementByID[announcement.sourceObjectID] = announcement
            }
        }
        return CanvasConnectorSnapshot(
            courses: stableUnique(courses, id: \.sourceObjectID),
            tasks: taskByID.values.sorted { $0.sourceObjectID < $1.sourceObjectID },
            announcements: announcementByID.values.sorted { $0.sourceObjectID < $1.sourceObjectID }
        )
    }

    private func collect<Value: Sendable>(
        _ fetch: (String?) async throws -> FetchPage<Value>
    ) async throws -> [Value] {
        var result: [Value] = []
        var token: String?
        var seenTokens: Set<String> = []
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= maximumPagesPerCollection else { throw paginationFailure() }
            let page = try await fetch(token)
            result.append(contentsOf: page.values)
            token = page.nextPageToken
            if let token, !seenTokens.insert(token).inserted { throw paginationFailure() }
        } while token != nil
        return result
    }

    private func stableUnique<Value>(_ values: [Value], id: KeyPath<Value, String>) -> [Value] {
        var byID: [String: Value] = [:]
        for value in values { byID[value[keyPath: id]] = value }
        return byID.values.sorted { $0[keyPath: id] < $1[keyPath: id] }
    }

    private func paginationFailure() -> CanvasConnectorError {
        CanvasConnectorError(
            category: .malformedResponse, retryable: false, retryAfter: nil,
            diagnostic: "Canvas pagination did not terminate safely"
        )
    }
}
