#if os(Windows)
import XCTest
@testable import CampusDashboardWindows

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
}
#endif
