import AppKit
import SwiftUI

@main
struct CampusDashboardApp: App {
    @StateObject private var model: DashboardModel
    private let launchWidth: CGFloat
    private let launchHeight: CGFloat
    private let forcesLaunchSize: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        forcesLaunchSize = arguments.contains("--stage10r-minimum-window")
        launchWidth = forcesLaunchSize ? 980 : 1180
        launchHeight = forcesLaunchSize ? 680 : 780
        if arguments.contains("--canvas-configure") {
            exit(CanvasLocalTool.configure())
        }
        if arguments.contains("--canvas-smoke-test") {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 3
            Task.detached {
                result = await CanvasLocalTool.smokeTest()
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if arguments.contains("--siweb-configure") {
            exit(SIwebLocalTool.configure())
        }
        if arguments.contains("--siweb-authenticate") {
            exit(SIwebWebAuthenticationTool.run())
        }
        if arguments.contains("--siweb-smoke-test") {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 3
            Task.detached {
                result = await SIwebLocalTool.smokeTest()
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if let flag = arguments.firstIndex(of: "--calendar-smoke-test"),
           arguments.indices.contains(flag + 1) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 3
            Task.detached {
                result = await CalendarLocalTool.smokeTest(resultPath: arguments[flag + 1])
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if let flag = arguments.firstIndex(of: "--stage10-calendar-lifecycle"),
           arguments.indices.contains(flag + 2),
           let phase = Stage10CalendarAcceptanceTool.Phase(rawValue: arguments[flag + 1]) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 3
            Task.detached {
                result = await Stage10CalendarAcceptanceTool.run(
                    phase: phase, resultPath: arguments[flag + 2]
                )
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if let flag = arguments.firstIndex(of: "--notification-smoke-test"),
           arguments.indices.contains(flag + 1) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 4
            Task.detached {
                result = await Stage07LocalTool.notificationSmokeTest(resultPath: arguments[flag + 1])
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if let flag = arguments.firstIndex(of: "--background-smoke-test"),
           arguments.indices.contains(flag + 1) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 4
            Task.detached {
                result = await Stage07LocalTool.backgroundSmokeTest(resultPath: arguments[flag + 1])
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if let flag = arguments.firstIndex(of: "--keychain-smoke-test"),
           arguments.indices.contains(flag + 1) {
            KeychainSmokeTest.run(resultPath: arguments[flag + 1])
        }
        if let flag = arguments.firstIndex(of: "--deepseek-smoke-test"),
           arguments.indices.contains(flag + 1) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 3
            Task.detached {
                result = await DeepSeekLocalTool.smokeTest(resultPath: arguments[flag + 1])
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if let flag = arguments.firstIndex(of: "--stage12-announcement-smoke"),
           arguments.indices.contains(flag + 1) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Int32 = 3
            Task.detached {
                result = await AcademicSignalLocalTool.smokeTest(resultPath: arguments[flag + 1])
                semaphore.signal()
            }
            semaphore.wait()
            exit(result)
        }
        if arguments.contains("--stage10r-db-ui-qa"), let qaModel = try? Stage10RQAData.databaseModel() {
            _model = StateObject(wrappedValue: qaModel)
            return
        }
        if arguments.contains("--stage12-ui-qa"), let qaModel = try? Stage12QAData.databaseModel() {
            _model = StateObject(wrappedValue: qaModel)
            return
        }
        if arguments.contains("--stage10r-ui-qa") {
            _model = StateObject(wrappedValue: DashboardModel(
                scenario: .populated, snapshot: Stage10RQAData.snapshot,
                now: { Stage10RQAData.now }, timeZone: TimeZone(identifier: "Asia/Macau")!
            ))
            return
        }
        let dependencies = AppEnvironment.dependencies()
        _model = StateObject(wrappedValue: DashboardModel(
            localStateRepository: dependencies.localStateRepository,
            dataReader: dependencies.dashboardDataReader,
            calendarService: dependencies.calendarService,
            notificationService: dependencies.notificationService,
            backgroundScheduler: dependencies.backgroundScheduler,
            aiCoordinator: dependencies.aiCoordinator,
            academicSignalCoordinator: dependencies.academicSignalCoordinator,
            courseReconciliation: dependencies.courseReconciliation,
            privacyDiagnostics: dependencies.privacyDiagnostics,
            releaseReadiness: dependencies.releaseReadiness
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 680)
                .background(LaunchWindowSizer(width: launchWidth, height: launchHeight, enabled: forcesLaunchSize))
                .task { await model.startRuntimeServices() }
        }
        .defaultSize(width: launchWidth, height: launchHeight)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(model.text("Refresh")) { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isRefreshing)
                Button(model.text("Open Settings")) { model.selectedSection = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct LaunchWindowSizer: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat
    let enabled: Bool

    func makeNSView(context: Context) -> NSView {
        enabled ? SizingView(size: NSSize(width: width, height: height)) : NSView(frame: .zero)
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SizingView: NSView {
        let requestedSize: NSSize
        var applied = false
        init(size: NSSize) { requestedSize = size; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !applied, let window else { return }
            applied = true
            window.setContentSize(requestedSize)
        }
    }
}

struct RootView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $model.selectedSection) { section in
                HStack {
                    Label(model.title(for: section), systemImage: section.systemImage)
                    Spacer()
                    if section == .confirmations, model.needsReviewCount > 0 {
                        Text("\(model.needsReviewCount)").font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.secondary.opacity(0.16), in: Capsule())
                            .accessibilityLabel(model.text("Needs Review count"))
                    }
                }.tag(section)
            }
            .navigationTitle(model.text("Campus Dashboard"))
            .safeAreaInset(edge: .bottom) {
                if model.isPreviewMode {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.text("Development preview"))
                            .font(.caption.weight(.semibold))
                        Text(model.text("All records are synthetic"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } detail: {
            detail
                .toolbar { toolbar }
        }
        .sheet(isPresented: $model.isSetupAssistantPresented) {
            ReleaseSetupAssistantView(model: model)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .today: TodayView(model: model)
        case .schedule: ScheduleView(model: model)
        case .tasks: TasksView(model: model)
        case .announcements: AnnouncementsView(model: model)
        case .confirmations: ConfirmationQueueView(model: model)
        case .settings: SettingsView(model: model)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isPreviewMode {
                Picker(model.text("Preview state"), selection: scenarioBinding) {
                    ForEach(DemoScenario.allCases) { scenario in
                        Text(model.text(scenario.rawValue)).tag(scenario)
                    }
                }
                .pickerStyle(.menu)
                .help(model.text("Select a deterministic UI state"))
            }

            Button {
                Task { await model.refresh() }
            } label: {
                Label(model.text(model.isRefreshing ? "Refreshing" : "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
            .help(model.text(model.isPreviewMode ? "Refresh synthetic preview data" : "Synchronize sources and reload dashboard data"))
            .accessibilityLabel(model.text("Refresh dashboard"))
        }
    }

    private var scenarioBinding: Binding<DemoScenario> {
        Binding(
            get: { model.scenario },
            set: { scenario in model.selectScenario(scenario) }
        )
    }
}
