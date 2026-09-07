import Foundation
import UserNotifications

enum Stage07LocalTool {
    static func notificationSmokeTest(resultPath: String) async -> Int32 {
        do {
            let directory = try applicationSupportDirectory()
            let database = try SQLiteDatabase(
                path: directory.appendingPathComponent("stage-07-notification-smoke.sqlite3").path
            )
            let center = SystemUserNotificationCenterClient()
            let service = CampusNotificationService(database: database, center: center)
            let initial = await service.authorizationState()
            guard try await service.requestAccessFromUserAction() else {
                try write("PARTIAL permission=denied initial=\(initial.rawValue)", to: resultPath)
                return 4
            }
            var preferences = try service.preferences()
            preferences.enabled = true
            try await service.updatePreferences(preferences)
            let key = try await service.scheduleTestNotification(after: 3)
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
                .contains { $0.identifier == key }
            try await Task.sleep(for: .seconds(6))
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
                .contains { $0.request.identifier == key }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [key])
            preferences.enabled = false
            try await service.updatePreferences(preferences)
            let disabledBlocked: Bool
            do { _ = try await service.scheduleTestNotification(after: 2); disabledBlocked = false }
            catch { disabledBlocked = true }
            let pass = pending && delivered && disabledBlocked
            try write(
                "\(pass ? "PASS" : "PARTIAL") permission=authorized pending=\(pending ? 1 : 0) " +
                "delivered=\(delivered ? 1 : 0) disabled_blocks=\(disabledBlocked ? 1 : 0)",
                to: resultPath
            )
            return pass ? 0 : 4
        } catch {
            let value = error as NSError
            try? write(
                "PARTIAL error=notification_smoke_unavailable domain=\(safe(value.domain)) code=\(value.code)",
                to: resultPath
            )
            return 4
        }
    }

    static func backgroundSmokeTest(resultPath: String) async -> Int32 {
        do {
            let directory = try applicationSupportDirectory()
            let url = directory.appendingPathComponent("stage-07-background-smoke.sqlite3")
            try? FileManager.default.removeItem(at: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let database = try SQLiteDatabase(path: url.path)
            let notifications = CampusNotificationService(
                database: database, center: SystemUserNotificationCenterClient()
            )
            let runner = LocalSyntheticRunner()
            let scheduler = BackgroundSyncScheduler(
                database: database, runner: runner, notifications: notifications
            )
            try await scheduler.setEnabled(true, developmentInterval: 2)
            try await Task.sleep(for: .seconds(1))
            let enabledState = await scheduler.backgroundItemState()
            await scheduler.evaluate(reason: .development)
            let firstCount = await runner.count
            try await scheduler.setEnabled(false)
            await scheduler.evaluate(reason: .development)
            let disabledCount = await runner.count
            try await scheduler.setEnabled(true, developmentInterval: 2)
            try database.execute(
                "UPDATE background_schedule_state SET last_completed_at=? WHERE singleton_key=1",
                bindings: [.real(Date().addingTimeInterval(-60).timeIntervalSince1970)]
            )
            await scheduler.signalRecovery(.wakeRecovery)
            let recoveryCount = await runner.count
            try await scheduler.setEnabled(false)
            let finalState = await scheduler.backgroundItemState()
            await scheduler.stop()
            let visible = enabledState == .enabled || enabledState == .requiresApproval
            let pass = visible && firstCount == 1 && disabledCount == 1 && recoveryCount == 2 && finalState == .disabled
            try write(
                "\(pass ? "PASS" : "PARTIAL") login_item=\(enabledState.rawValue) short_interval=\(firstCount) " +
                "disabled_count=\(disabledCount) recovery_count=\(recoveryCount) final=\(finalState.rawValue)",
                to: resultPath
            )
            return pass ? 0 : 4
        } catch {
            try? write("PARTIAL error=background_smoke_unavailable", to: resultPath)
            return 4
        }
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.campusdashboard.desktop", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func write(_ value: String, to path: String) throws {
        try Data((value + "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func safe(_ value: String) -> String {
        value.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }
}

private actor LocalSyntheticRunner: ScheduledSyncRunner {
    private(set) var count = 0
    func run(trigger: SyncTrigger) async -> [ScheduledSourceResult] {
        count += 1
        return []
    }
}
