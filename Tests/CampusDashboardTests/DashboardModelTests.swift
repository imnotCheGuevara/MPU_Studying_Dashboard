import Testing
@testable import CampusDashboard

@MainActor
@Suite("Dashboard model")
struct DashboardModelTests {
    @Test("Synthetic fixtures are populated and use composite identity parts")
    func syntheticFixtureContents() {
        let snapshot = SyntheticFixtures.populated

        #expect(snapshot.courses.count == 3)
        #expect(snapshot.meetings.count == 3)
        #expect(snapshot.tasks.count == 3)
        #expect(snapshot.announcements.count == 2)
        #expect(snapshot.confirmations.count == 2)
        #expect(snapshot.courses.allSatisfy { !$0.sourceAccountID.isEmpty && !$0.sourceObjectID.isEmpty })
        #expect(snapshot.tasks.allSatisfy { !$0.sourceAccountID.isEmpty && !$0.sourceObjectID.isEmpty })
    }

    @Test("Every required primary page is available")
    func requiredSections() {
        #expect(AppSection.allCases == [.today, .schedule, .tasks, .announcements, .confirmations, .settings])
    }

    @Test("Every important preview state is intentionally selectable")
    func requiredScenarios() {
        #expect(DemoScenario.allCases == [.populated, .empty, .loading, .error, .permissionDenied])
    }

    @Test("Selecting the empty scenario clears all fixture collections")
    func emptyScenario() {
        let model = DashboardModel(scenario: .populated)
        model.selectScenario(.empty)
        #expect(model.snapshot == .empty)
    }

    @Test("Selecting sample data restores the synthetic fixture")
    func populatedScenario() {
        let model = DashboardModel(scenario: .empty)
        model.selectScenario(.populated)
        #expect(model.snapshot == SyntheticFixtures.populated)
    }

    @Test("Local completion never changes source identity or official date")
    func localTaskStateIsSeparate() throws {
        let model = DashboardModel(scenario: .populated)
        let before = try #require(model.snapshot.tasks.first)
        model.toggleTask(before.id)
        let after = try #require(model.snapshot.tasks.first)
        #expect(before.isLocallyComplete != after.isLocallyComplete)
        #expect(before.sourceAccountID == after.sourceAccountID)
        #expect(before.sourceObjectID == after.sourceObjectID)
        #expect(before.officialDueAt == after.officialDueAt)
    }

    @Test("An inferred date stays separate and unconfirmed")
    func suggestedDateIsSeparate() throws {
        let task = try #require(SyntheticFixtures.populated.tasks.first { $0.officialDueAt == nil })
        #expect(task.suggestedCompleteAt != nil)
        #expect(!task.suggestedDateConfirmed)
    }

    @Test("Manual refresh recovers an error without an external dependency")
    func refreshRecovery() async {
        let model = DashboardModel(scenario: .error)
        await model.refresh()
        #expect(model.scenario == .populated)
        #expect(model.refreshCount == 1)
        #expect(!model.isRefreshing)
    }

    @Test("Settings language selection localizes primary navigation")
    func languageSelection() {
        let model = DashboardModel()
        #expect(model.title(for: .settings) == "Settings")

        model.language = .simplifiedChinese

        #expect(model.title(for: .today) == "今日")
        #expect(model.title(for: .settings) == "设置")
        #expect(model.text("Permission denied") == "权限被拒绝")
    }
}
