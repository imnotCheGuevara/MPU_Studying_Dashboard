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

    func testSnapshotStoreRoundTripsCanonicalDataAndRemovesIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusDashboardWindowsTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("snapshot-v1.json")
        let store = WindowsSnapshotStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = SyntheticFixtures.populated
        try store.save(expected, now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(try store.load(), expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try store.remove()
        XCTAssertNil(try store.load())
    }

    func testSnapshotStoreRejectsCorruptDataWithoutReturningPartialContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusDashboardWindowsTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("snapshot-v1.json")
        let store = WindowsSnapshotStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? WindowsSnapshotStoreError, .unreadableArchive)
        }
    }

    func testDefaultSnapshotLocationUsesLocalAppData() {
        let url = WindowsSnapshotStore.defaultFileURL(
            environment: ["LOCALAPPDATA": "C:\\Users\\Test\\AppData\\Local"]
        )

        XCTAssertEqual(url.lastPathComponent, "snapshot-v1.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "CampusDashboard")
    }

    @MainActor
    func testDashboardStateRestoresSnapshotAfterRestartAndForgetRemovesIt() throws {
        let suiteName = "CampusDashboardWindowsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configurationStore = UserDefaultsCanvasConfigurationStore(defaults: defaults)
        let secrets = FakeSecretStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusDashboardWindowsTests-\(UUID().uuidString)", isDirectory: true)
        let snapshotStore = WindowsSnapshotStore(fileURL: directory.appendingPathComponent("snapshot-v1.json"))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        try configurationStore.saveBaseURL(XCTUnwrap(URL(string: "https://canvas.example.edu")))
        try secrets.set(Data("test-only-token".utf8), account: CanvasConfiguration.tokenAccount)
        try snapshotStore.save(SyntheticFixtures.populated)

        let state = WindowsDashboardState(
            configurationStore: configurationStore,
            secretStore: secrets,
            snapshotStore: snapshotStore
        )

        XCTAssertFalse(state.isShowingPreview)
        XCTAssertEqual(state.snapshot, SyntheticFixtures.populated)
        XCTAssertTrue(state.hasSavedCanvasToken)
        XCTAssertEqual(state.canvasBaseURL, "https://canvas.example.edu")

        state.forgetCanvas()

        XCTAssertTrue(state.isShowingPreview)
        XCTAssertNil(try snapshotStore.load())
        XCTAssertThrowsError(try secrets.data(account: CanvasConfiguration.tokenAccount))
        XCTAssertThrowsError(try configurationStore.load())
    }
}
#endif
