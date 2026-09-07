import Foundation

actor BackgroundSyncScheduler {
    private let persistence: BackgroundPersistence
    private let runner: any ScheduledSyncRunner
    private let notifications: CampusNotificationService
    private let itemController: any BackgroundItemControlling
    private let clock: any Clock
    private var loop: Task<Void, Never>?
    private var running = false
    private var completionHandler: (@Sendable () async -> Void)?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var manualPending = false

    init(
        database: SQLiteDatabase,
        runner: any ScheduledSyncRunner,
        notifications: CampusNotificationService,
        itemController: any BackgroundItemControlling = MacOSBackgroundItemController(),
        clock: any Clock = SystemClock()
    ) {
        persistence = BackgroundPersistence(database: database)
        self.runner = runner
        self.notifications = notifications
        self.itemController = itemController
        self.clock = clock
    }

    func configuration() throws -> BackgroundScheduleConfiguration { try persistence.load() }
    func backgroundItemState() -> BackgroundItemState { itemController.state() }
    func setCompletionHandler(_ handler: (@Sendable () async -> Void)?) {
        completionHandler = handler
    }

    func setEnabled(_ enabled: Bool, developmentInterval: TimeInterval? = nil) throws {
        try itemController.setEnabled(enabled)
        let interval = developmentInterval ?? 3_600
        try persistence.setEnabled(enabled, targetInterval: interval, now: clock.now)
        if enabled { startLoop() } else { stopLoop() }
    }

    func start() async {
        guard (try? persistence.load().enabled) == true else { return }
        startLoop()
        await evaluate(reason: .launchRecovery)
    }

    func signalRecovery(_ reason: BackgroundRunReason) async {
        guard reason == .wakeRecovery || reason == .networkRecovery else { return }
        await evaluate(reason: reason)
    }

    func runManual() async -> [ScheduledSourceResult] {
        manualPending = true
        await waitUntilIdle()
        let results = await execute(reason: .manual)
        manualPending = false
        return results
    }

    func evaluate(reason: BackgroundRunReason) async {
        guard !manualPending, let state = try? persistence.load(), state.enabled else { return }
        let due = state.lastCompletedAt == nil ||
            clock.now.timeIntervalSince(state.lastCompletedAt!) >= state.targetInterval
        guard due || reason == .development else { return }
        _ = await execute(reason: reason)
    }

    private func execute(reason: BackgroundRunReason) async -> [ScheduledSourceResult] {
        guard !running else { return [] }
        running = true
        defer {
            running = false
            let waiters = idleWaiters
            idleWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        let trigger: SyncTrigger
        switch reason {
        case .manual: trigger = .manual
        case .scheduled, .development: trigger = .scheduled
        case .launchRecovery, .wakeRecovery, .networkRecovery: trigger = .recovery
        }
        try? persistence.recordStart(reason: reason, now: clock.now)
        let results = await runner.run(trigger: trigger)
        for result in results {
            try? await notifications.recordSyncResult(
                sourceAccountID: result.sourceAccountID,
                sourceName: result.sourceName,
                errorCategory: result.errorCategory
            )
        }
        try? await notifications.reconcileReminders()
        try? persistence.recordFinish(results: results, now: clock.now)
        await completionHandler?()
        return results
    }

    private func waitUntilIdle() async {
        guard running else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    func stop() { stopLoop() }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await self?.evaluate(reason: .scheduled)
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }
}
