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

    func testSIwebSessionInputAcceptsOnlyCookieHeaderValue() throws {
        let input = WindowsSIwebSessionInput()

        XCTAssertEqual(
            try input.normalize("  ASPSESSIONID=abc123; route=node-2  "),
            "ASPSESSIONID=abc123; route=node-2"
        )
        XCTAssertThrowsError(try input.normalize("Cookie: ASPSESSIONID=abc123"))
        XCTAssertThrowsError(try input.normalize("Authorization: Bearer secret"))
        XCTAssertThrowsError(try input.normalize("ASPSESSIONID=abc123\r\nInjected=yes"))
        XCTAssertThrowsError(try input.normalize("ASPSESSIONID=one; ASPSESSIONID=two"))
        XCTAssertThrowsError(try input.normalize("password-without-cookie-name"))
    }

    func testSIwebMergerReusesCanvasCourseAndPreservesMeetingIdentity() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let canvas = WindowsCanvasSnapshotMapper().map(
            CanvasConnectorSnapshot(
                courses: [CanvasCoursePayload(
                    sourceObjectID: "canvas-course", name: "Systems", code: "CS301", term: "Fall"
                )],
                tasks: [CanvasTaskPayload(
                    sourceObjectID: "task", courseSourceObjectID: "canvas-course", title: "Lab",
                    officialType: "assignment", officialDueAt: now.addingTimeInterval(3_600)
                )],
                announcements: []
            ),
            accountID: "canvas.example.edu",
            syncedAt: now
        )
        let payload = SIwebMeetingPayload(
            sourceObjectID: "siweb-meeting", courseSourceObjectID: "SI-CS301",
            courseName: "Systems", courseCode: "CS301", startsAt: now,
            endsAt: now.addingTimeInterval(5_400), timeZoneIdentifier: "Asia/Macau",
            location: "A101", isCancelled: false,
            parserVersion: SIwebHTMLParser.mpuVersion
        )
        let merger = WindowsSIwebSnapshotMerger()

        let first = merger.merge(SIwebSnapshot(meetings: [payload]), into: canvas, syncedAt: now)
        let second = merger.merge(SIwebSnapshot(meetings: [payload]), into: first, syncedAt: now)

        XCTAssertEqual(first.courses.count, 1)
        XCTAssertEqual(first.meetings.first?.courseID, first.courses.first?.id)
        XCTAssertEqual(first.tasks.map(\.title), ["Lab"])
        XCTAssertEqual(first.sourceHealth.map(\.source.rawValue).sorted(), ["Canvas", "SIweb"])
        XCTAssertEqual(second.meetings.first?.id, first.meetings.first?.id)
    }

    func testSIwebParserUsesSharedContractAndProducesContentHash() throws {
        let html = """
        <main data-siweb-contract="schedule-v1" data-siweb-complete="true">
          <article data-siweb-course-id="SI-CS301" data-siweb-course-name="Systems" data-siweb-course-code="CS301">
            <div data-siweb-meeting-id="m1"
                 data-siweb-start="2026-09-14T09:00:00+08:00"
                 data-siweb-end="2026-09-14T10:00:00+08:00"
                 data-siweb-location="A101"
                 data-siweb-status="scheduled"></div>
          </article>
        </main>
        """

        let result = try SIwebHTMLParser(baseURL: MPUSIwebEndpoints.operationalBaseURL)
            .parse(Data(html.utf8))

        XCTAssertEqual(result.meetings.count, 1)
        XCTAssertEqual(result.meetings.first?.courseCode, "CS301")
        XCTAssertEqual(result.meetings.first?.location, "A101")
        XCTAssertEqual(result.meetings.first?.sourceContentHash.count, 64)
    }

    func testForgettingSIwebKeepsCanvasData() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let canvas = WindowsCanvasSnapshotMapper().map(
            CanvasConnectorSnapshot(
                courses: [CanvasCoursePayload(
                    sourceObjectID: "canvas-course", name: "Systems", code: "CS301", term: "Fall"
                )],
                tasks: [], announcements: []
            ),
            accountID: "canvas.example.edu",
            syncedAt: now
        )
        let payload = SIwebMeetingPayload(
            sourceObjectID: "siweb-meeting", courseSourceObjectID: "OTHER",
            courseName: "Design", courseCode: "ART100", startsAt: now,
            endsAt: now.addingTimeInterval(3_600), timeZoneIdentifier: "Asia/Macau",
            isCancelled: false, parserVersion: SIwebHTMLParser.mpuVersion
        )
        let merger = WindowsSIwebSnapshotMerger()
        let combined = merger.merge(SIwebSnapshot(meetings: [payload]), into: canvas, syncedAt: now)

        let result = merger.removingSIweb(from: combined)

        XCTAssertEqual(result.courses.map(\.name), ["Systems"])
        XCTAssertTrue(result.meetings.isEmpty)
        XCTAssertEqual(result.sourceHealth.map(\.source), [.canvas])
    }

    func testForgettingCanvasKeepsSIwebWithoutCanvasCourseMetadata() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let canvas = WindowsCanvasSnapshotMapper().map(
            CanvasConnectorSnapshot(
                courses: [CanvasCoursePayload(
                    sourceObjectID: "canvas-course", name: "Systems", code: "CS301", term: "Fall"
                )],
                tasks: [CanvasTaskPayload(
                    sourceObjectID: "task", courseSourceObjectID: "canvas-course", title: "Lab",
                    officialType: "assignment", officialDueAt: now.addingTimeInterval(3_600)
                )],
                announcements: []
            ),
            accountID: "canvas.example.edu",
            syncedAt: now
        )
        let payload = SIwebMeetingPayload(
            sourceObjectID: "siweb-meeting", courseSourceObjectID: "SI-CS301",
            courseName: "Systems", courseCode: "CS301", startsAt: now,
            endsAt: now.addingTimeInterval(5_400), timeZoneIdentifier: "Asia/Macau",
            location: "A101", isCancelled: false,
            sourceURL: MPUSIwebEndpoints.classTimeURL,
            parserVersion: SIwebHTMLParser.mpuVersion
        )
        let merger = WindowsSIwebSnapshotMerger()
        let combined = merger.merge(SIwebSnapshot(meetings: [payload]), into: canvas, syncedAt: now)

        let result = merger.removingCanvas(from: combined)

        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertEqual(result.meetings.count, 1)
        XCTAssertEqual(result.sourceHealth.map(\.source), [.siweb])
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertEqual(result.courses.first?.sourceAccountID, WindowsSIwebSnapshotMerger.accountID)
        XCTAssertEqual(result.courses.first?.name, "Systems")
        XCTAssertEqual(result.courses.first?.code, "")
        XCTAssertEqual(result.courses.first?.term, "")
        XCTAssertEqual(result.courses.first?.sourceURL, MPUSIwebEndpoints.classTimeURL.absoluteString)

        let refreshed = merger.merge(SIwebSnapshot(meetings: [payload]), into: result, syncedAt: now)
        XCTAssertEqual(refreshed.courses.first?.id, result.courses.first?.id)
        XCTAssertEqual(refreshed.meetings.first?.id, result.meetings.first?.id)
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

    func testWindowsLanguageFollowsSupportedSystemLocale() {
        XCTAssertEqual(
            WindowsLanguage.systemDefault(preferredLanguages: ["zh-Hans-CN"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            WindowsLanguage.systemDefault(preferredLanguages: ["en-US"]),
            .english
        )
        XCTAssertEqual(
            WindowsLanguage.systemDefault(preferredLanguages: ["zh-Hant-HK"]),
            .english
        )
    }

    func testWindowsCopyLocalizesDomainLabels() {
        let english = WindowsCopy(language: .english)
        let chinese = WindowsCopy(language: .simplifiedChinese)

        XCTAssertEqual(english.priority(.medium), "Medium")
        XCTAssertEqual(chinese.priority(.medium), "中")
        XCTAssertEqual(english.taskKind(.reading), "Reading")
        XCTAssertEqual(chinese.taskKind(.reading), "阅读")
        XCTAssertEqual(chinese.sourceHealthDetail("Read-only sync completed"), "只读同步已完成")
    }

    func testInAppRemindersUseOfficialOrConfirmedDatesOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let course = SyntheticFixtures.interactionDesign
        let official = LearningTask(
            id: UUID(), sourceAccountID: "canvas", sourceObjectID: "official", courseID: course.id,
            title: "Official", kind: .assignment, officialDueAt: now.addingTimeInterval(30 * 60),
            suggestedCompleteAt: now.addingTimeInterval(10 * 60), suggestedDateConfirmed: false,
            source: .canvas, isLocallyComplete: false, localPriority: .high
        )
        let confirmed = LearningTask(
            id: UUID(), sourceAccountID: "canvas", sourceObjectID: "confirmed", courseID: course.id,
            title: "Confirmed", kind: .reading, officialDueAt: nil,
            suggestedCompleteAt: now.addingTimeInterval(2 * 24 * 60 * 60), suggestedDateConfirmed: true,
            source: .canvas, isLocallyComplete: false, localPriority: .medium
        )
        let unconfirmed = LearningTask(
            id: UUID(), sourceAccountID: "canvas", sourceObjectID: "unconfirmed", courseID: course.id,
            title: "Unconfirmed", kind: .quiz, officialDueAt: nil,
            suggestedCompleteAt: now.addingTimeInterval(20 * 60), suggestedDateConfirmed: false,
            source: .canvas, isLocallyComplete: false, localPriority: .low
        )
        let snapshot = DashboardSnapshot(
            sourceHealth: [], courses: [course], meetings: [],
            tasks: [unconfirmed, confirmed, official], announcements: [], confirmations: []
        )

        let reminders = WindowsInAppReminderEngine().reminders(in: snapshot, now: now)

        XCTAssertEqual(reminders.map(\.title), ["Official", "Confirmed"])
        XCTAssertEqual(reminders.map(\.urgency), [.dueWithinHour, .upcoming])
        XCTAssertFalse(reminders[0].usesConfirmedSuggestion)
        XCTAssertTrue(reminders[1].usesConfirmedSuggestion)
        XCTAssertEqual(reminders[0].dueAt, official.officialDueAt)
    }

    func testInAppRemindersExcludeCompletedAndOutOfWindowTasks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let course = SyntheticFixtures.interactionDesign
        func task(_ title: String, due: TimeInterval, complete: Bool = false) -> LearningTask {
            LearningTask(
                id: UUID(), sourceAccountID: "canvas", sourceObjectID: title, courseID: course.id,
                title: title, kind: .assignment, officialDueAt: now.addingTimeInterval(due),
                suggestedCompleteAt: nil, suggestedDateConfirmed: false,
                source: .canvas, isLocallyComplete: complete, localPriority: .medium
            )
        }
        let snapshot = DashboardSnapshot(
            sourceHealth: [], courses: [course], meetings: [],
            tasks: [
                task("Recent overdue", due: -2 * 24 * 60 * 60),
                task("Too old", due: -8 * 24 * 60 * 60),
                task("Too far", due: 8 * 24 * 60 * 60),
                task("Complete", due: 60 * 60, complete: true)
            ],
            announcements: [], confirmations: []
        )

        let reminders = WindowsInAppReminderEngine().reminders(in: snapshot, now: now)

        XCTAssertEqual(reminders.map(\.title), ["Recent overdue"])
        XCTAssertEqual(reminders.first?.urgency, .overdue)
    }

    @MainActor
    func testLanguageChoicePersistsAndUpdatesVisibleStatus() throws {
        let suiteName = "CampusDashboardWindowsLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let languageStore = WindowsLanguageStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CampusDashboardWindowsLanguageTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let state = WindowsDashboardState(
            configurationStore: UserDefaultsCanvasConfigurationStore(defaults: defaults),
            secretStore: FakeSecretStore(),
            siwebSecretStore: FakeSecretStore(),
            snapshotStore: WindowsSnapshotStore(fileURL: directory.appendingPathComponent("snapshot-v1.json")),
            languageStore: languageStore
        )
        state.selectLanguage(.simplifiedChinese)

        XCTAssertEqual(state.language, .simplifiedChinese)
        XCTAssertTrue(state.statusMessage.contains("预览数据"))
        XCTAssertEqual(languageStore.load(preferredLanguages: ["en-US"]), .simplifiedChinese)
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
            siwebSecretStore: FakeSecretStore(),
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
