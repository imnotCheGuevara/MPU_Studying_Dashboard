import Foundation

/// A cancellation-safe asynchronous permit gate. Actor isolation protects the
/// queue, but the permit count—not actor non-reentrancy—bounds network work.
actor CanvasConcurrencyGate {
    private let limit: Int
    private var availablePermits: Int
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    init(limit: Int) {
        self.limit = max(1, limit)
        availablePermits = max(1, limit)
    }

    func withPermit<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        try await acquire()
        do {
            // Cancellation may race with a waiter being granted a permit.
            // Check again before any network operation can start.
            try Task.checkCancellation()
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    func queuedRequestCount() -> Int { waiters.count }

    private func acquire() async throws {
        try Task.checkCancellation()
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // If cancellation happened before this actor enqueued the
                // continuation, fail it immediately instead of orphaning it.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiterOrder.append(id)
                waiters[id] = continuation
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        waiterOrder.removeAll { $0 == id }
        continuation.resume(throwing: CancellationError())
    }

    private func release() {
        while let id = waiterOrder.first {
            waiterOrder.removeFirst()
            if let continuation = waiters.removeValue(forKey: id) {
                continuation.resume()
                return
            }
        }
        availablePermits = min(limit, availablePermits + 1)
    }
}
