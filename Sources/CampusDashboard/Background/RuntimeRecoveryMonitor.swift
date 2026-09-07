import AppKit
import Foundation
import Network

@MainActor
final class RuntimeRecoveryMonitor {
    private let scheduler: BackgroundSyncScheduler
    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.campusdashboard.background-connectivity")
    private var wakeObserver: NSObjectProtocol?
    private var wasOffline = false

    init(scheduler: BackgroundSyncScheduler) { self.scheduler = scheduler }

    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [scheduler] _ in Task { await scheduler.signalRecovery(.wakeRecovery) } }
        networkMonitor.pathUpdateHandler = { [weak self, scheduler] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .satisfied, self.wasOffline {
                    await scheduler.signalRecovery(.networkRecovery)
                }
                self.wasOffline = path.status != .satisfied
            }
        }
        networkMonitor.start(queue: queue)
    }

    func stop() {
        networkMonitor.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
