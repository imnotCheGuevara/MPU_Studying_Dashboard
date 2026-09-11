#if os(Windows)
import Foundation
import XCTest
@testable import CampusDashboardWindowsCore

final class WindowsCoreReuseTests: XCTestCase {
    func testSyntheticSnapshotUsesCanonicalDomainModel() {
        let snapshot = SyntheticFixtures.populated

        XCTAssertEqual(snapshot.courses.count, 3)
        XCTAssertEqual(snapshot.meetings.count, 3)
        XCTAssertEqual(snapshot.tasks.count, 3)
        XCTAssertEqual(snapshot.announcements.count, 2)
        XCTAssertEqual(snapshot.confirmations.count, 2)
    }

    func testPlaceholderVisibilityRuleIsReused() {
        var task = SyntheticFixtures.populated.tasks[0]

        XCTAssertTrue(task.appearsInNormalTaskList)
        task = LearningTask(
            id: task.id,
            sourceAccountID: task.sourceAccountID,
            sourceObjectID: task.sourceObjectID,
            courseID: task.courseID,
            title: task.title,
            kind: task.kind,
            officialDueAt: nil,
            suggestedCompleteAt: nil,
            suggestedDateConfirmed: false,
            source: task.source,
            isLocallyComplete: false,
            localPriority: task.localPriority,
            isPlaceholder: true
        )
        XCTAssertFalse(task.appearsInNormalTaskList)

        task.placeholderAlwaysShow = true
        XCTAssertTrue(task.appearsInNormalTaskList)
    }

    func testCanvasMapperUsesCanonicalSnapshotWithoutExternalCalendarData() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = CanvasConnectorSnapshot(
            courses: [
                CanvasCoursePayload(
                    sourceObjectID: "course-1",
                    name: "Systems",
                    code: "CS301",
                    term: "Fall"
                )
            ],
            tasks: [
                CanvasTaskPayload(
                    sourceObjectID: "task-1",
                    courseSourceObjectID: "course-1",
                    title: "Lab",
                    officialType: "assignment",
                    officialDueAt: now.addingTimeInterval(2 * 24 * 60 * 60)
                )
            ],
            announcements: [
                CanvasAnnouncementPayload(
                    sourceObjectID: "announcement-1",
                    courseSourceObjectID: "course-1",
                    title: "Welcome",
                    publishedAt: now,
                    summary: "Read the module guide"
                )
            ]
        )

        let snapshot = WindowsCanvasSnapshotMapper().map(
            source,
            accountID: "canvas.example.edu",
            syncedAt: now
        )

        XCTAssertEqual(snapshot.courses.map(\.name), ["Systems"])
        XCTAssertEqual(snapshot.tasks.map(\.title), ["Lab"])
        XCTAssertEqual(snapshot.tasks.first?.localPriority, .high)
        XCTAssertEqual(snapshot.announcements.map(\.title), ["Welcome"])
        XCTAssertTrue(snapshot.meetings.isEmpty)
        XCTAssertTrue(snapshot.confirmations.isEmpty)
        XCTAssertEqual(snapshot.sourceHealth.first?.source, .canvas)
        XCTAssertEqual(snapshot.sourceHealth.first?.level, .healthy)
    }

    func testCanvasConfigurationRequiresHTTPSAndNormalizesTrailingSlash() throws {
        let configuration = try CanvasConfiguration(baseURL: XCTUnwrap(URL(string: "https://canvas.example.edu/")))
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://canvas.example.edu")

        XCTAssertThrowsError(
            try CanvasConfiguration(baseURL: XCTUnwrap(URL(string: "http://canvas.example.edu")))
        ) { error in
            XCTAssertEqual(error as? CanvasConfigurationError, .invalidBaseURL)
        }
    }

    func testWindowsCredentialManagerRoundTrip() throws {
        let account = "canvas-test-\(UUID().uuidString)"
        let store = WindowsCredentialSecretStore(service: "com.campusdashboard.desktop.tests")
        let secret = Data("test-only-token".utf8)
        defer { try? store.remove(account: account) }

        try store.set(secret, account: account)
        XCTAssertEqual(try store.data(account: account), secret)
        try store.remove(account: account)
        XCTAssertThrowsError(try store.data(account: account)) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound)
        }
    }
}
#endif
