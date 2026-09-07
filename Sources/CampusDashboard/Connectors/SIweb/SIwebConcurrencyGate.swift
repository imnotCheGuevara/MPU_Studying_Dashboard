import Foundation

actor SIwebConcurrencyGate {
    private let limit: Int
    private var available: Int
    private var order: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    init(limit: Int) {
        self.limit = max(1, limit)
        available = max(1, limit)
    }

    func withPermit<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        try await acquire()
        do {
            try Task.checkCancellation()
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 { available -= 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                order.append(id)
                waiters[id] = continuation
            }
        } onCancel: { Task { await self.cancel(id) } }
    }

    private func cancel(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        waiter.resume(throwing: CancellationError())
    }

    private func release() {
        while let id = order.first {
            order.removeFirst()
            if let waiter = waiters.removeValue(forKey: id) { waiter.resume(); return }
        }
        available = min(limit, available + 1)
    }
}

actor SIwebRequestPacer {
    private let interval: Duration
    private let clock = ContinuousClock()
    private var nextAllowed: ContinuousClock.Instant?

    init(minimumInterval: TimeInterval) {
        interval = .seconds(max(0, minimumInterval))
    }

    func waitForTurn() async throws {
        let now = clock.now
        let scheduled = if let nextAllowed, nextAllowed > now { nextAllowed } else { now }
        // Reserve the following slot before suspending. Actor reentrancy must not
        // let multiple queued requests inherit the same start time.
        nextAllowed = scheduled.advanced(by: interval)
        if scheduled > now { try await clock.sleep(until: scheduled) }
    }
}
