import Foundation
import Testing
@testable import CampusDashboard

@Suite("External service contracts")
struct ServiceContractTests {
    @Test("Canvas fake is deterministic and read-only")
    func canvasFake() async throws {
        let payload = CanvasCoursePayload(sourceObjectID: "synthetic-course", name: "Course", code: "SYN")
        let service = FakeCanvasService(coursePage: .init(
            values: [payload], nextPageToken: nil, isCompleteSnapshot: true
        ))
        let page = try await service.courses(pageToken: nil)
        #expect(page.values == [payload])
        #expect(page.isCompleteSnapshot)
    }

    @Test("Clock and identifier fakes are deterministic")
    func deterministicDependencies() {
        let date = Date(timeIntervalSince1970: 42)
        let id = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        #expect(FixedClock(now: date).now == date)
        #expect(SequenceIDGenerator(values: [id]).next() == id)
    }

    @Test("Calendar, notifications, and AI use fake boundaries")
    func downstreamFakes() async throws {
        let calendar = FakeCalendarService()
        let notification = FakeNotificationService()
        let ai = FakeAIService()
        let commands: [CalendarCommand] = [.upsert(objectType: "learning_task", objectID: "synthetic-task")]
        _ = try await calendar.apply(commands)
        try await notification.apply([.cancel(key: "synthetic-key")])
        let suggestion = try await ai.suggest(for: AIRequest(
            title: "Synthetic", officialType: "assignment", officialDueAt: nil, minimalText: ""
        ))
        #expect(await calendar.received == [commands])
        #expect(await notification.received.count == 1)
        #expect(suggestion.suggestedCompleteAt == nil)
    }
}
