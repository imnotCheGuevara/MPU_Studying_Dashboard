import Foundation
import Testing
@testable import CampusDashboard

@Suite("Canvas read-only connector")
struct CanvasConnectorTests {
    @Test("Courses decode across safe Link pagination")
    func pagination() async throws {
        let next = "https://canvas.invalid/api/v1/courses?page=2&per_page=100"
        let transport = StubCanvasTransport(outcomes: [
            .response(status: 200, data: fixture("courses-page-1"), headers: [
                "Link": "<\(next)>; rel=\"next\", <https://canvas.invalid/api/v1/courses?page=2>; rel=\"last\"",
                "X-Rate-Limit-Remaining": "699.5", "X-Request-Cost": "0.5"
            ]),
            .response(status: 200, data: fixture("courses-page-2"), headers: [:])
        ])
        let connector = try makeConnector(transport: transport)

        let first = try await connector.courses(pageToken: nil)
        #expect(await connector.rateLimitSnapshot() == CanvasRateLimitSnapshot(remaining: 699.5, requestCost: 0.5))
        let second = try await connector.courses(pageToken: first.nextPageToken)

        #expect(first.values.map(\.sourceObjectID) == ["31001"])
        #expect(first.nextPageToken == next)
        #expect(!first.isCompleteSnapshot)
        #expect(second.values.map(\.sourceObjectID) == ["31002"])
        #expect(second.isCompleteSnapshot)
        #expect(await transport.requests.count == 2)
        #expect(await connector.rateLimitSnapshot() == CanvasRateLimitSnapshot(remaining: nil, requestCost: nil))
    }

    @Test("Assignments use current-user effective dates and classify quiz-like work")
    func assignmentsAndOverrides() async throws {
        let transport = StubCanvasTransport(outcomes: [
            .response(status: 200, data: fixture("assignments"), headers: [:])
        ])
        let connector = try makeConnector(transport: transport)
        let page = try await connector.learningTasks(courseID: "31001", pageToken: nil)

        #expect(page.values.count == 5)
        #expect(page.values.first { $0.sourceObjectID == "41001" }?.officialDueAt == nil)
        #expect(page.values.first { $0.sourceObjectID == "41002" }?.officialType == "classic_quiz")
        #expect(page.values.first { $0.sourceObjectID == "41003" }?.officialType == "new_quiz")
        #expect(page.values.first { $0.sourceObjectID == "41004" }?.officialType == "external_tool")
        let overridden = page.values.first { $0.sourceObjectID == "41005" }
        #expect(overridden?.officialDueAt == isoDate("2026-09-15T14:00:00Z"))
        #expect(overridden?.hasAssignmentOverrides == true)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.contains(URLQueryItem(name: "override_assignment_dates", value: "true")) == true)
    }

    @Test("Concurrent calls never exceed the configured network limit")
    func boundedNetworkConcurrency() async throws {
        let transport = ControlledConcurrencyTransport()
        let connector = try makeConnector(transport: transport, maximumConcurrentRequests: 2)
        let tasks = (0..<8).map { _ in
            Task { try await connector.courses(pageToken: nil) }
        }

        await transport.waitUntilStarted(2)
        for _ in 0..<200 { await Task.yield() }
        #expect(await transport.startedCount == 2)
        #expect(await transport.maximumObservedConcurrency == 2)

        await transport.releaseAll()
        for task in tasks { _ = try await task.value }
        #expect(await transport.startedCount == 8)
        #expect(await transport.maximumObservedConcurrency <= 2)
    }

    @Test("Cancelling a queued gate waiter neither starts work nor leaks a permit")
    func gateCancellationSafety() async throws {
        let gate = CanvasConcurrencyGate(limit: 1)
        let blocker = GateOperationBlocker()
        let secondOperation = OperationFlag()

        let first = Task {
            try await gate.withPermit {
                await blocker.run()
                return 1
            }
        }
        await blocker.waitUntilStarted()

        let second = Task {
            try await gate.withPermit {
                await secondOperation.markRun()
                return 2
            }
        }
        #expect(await waitUntilQueued(gate, count: 1))
        second.cancel()
        let secondResult = await second.result
        switch secondResult {
        case .failure(let error): #expect(error is CancellationError)
        case .success: Issue.record("A cancelled gate waiter unexpectedly ran")
        }
        #expect(!(await secondOperation.didRun))

        await blocker.releaseAll()
        #expect(try await first.value == 1)
        #expect(try await gate.withPermit { 3 } == 3)
    }

    @Test("Announcements decode publication metadata and sanitized summaries")
    func announcements() async throws {
        let transport = StubCanvasTransport(outcomes: [
            .response(status: 200, data: fixture("announcements"), headers: [:])
        ])
        let connector = try makeConnector(transport: transport)
        let page = try await connector.announcements(courseID: "31001", pageToken: nil)
        let item = try #require(page.values.first)

        #expect(item.courseSourceObjectID == "31001")
        #expect(item.publishedAt == isoDate("2026-09-01T02:00:00Z"))
        #expect(item.updatedAt == isoDate("2026-09-01T03:00:00Z"))
        #expect(item.summary == "Bring a fictional prototype next week.")
        #expect(await transport.requests.first?.url?.path == "/api/v1/courses/31001/discussion_topics")
    }

    @Test("Malformed responses fail closed without response content")
    func malformedAndRedacted() async throws {
        let privateMarker = "PRIVATE-STUDENT-CONTENT"
        let body = Data((String(data: fixture("malformed"), encoding: .utf8)! + privateMarker).utf8)
        let transport = StubCanvasTransport(outcomes: [
            .response(status: 200, data: body, headers: [:])
        ])
        let connector = try makeConnector(transport: transport, token: "SECRET-AUTHORIZATION-MARKER")
        do {
            _ = try await connector.courses(pageToken: nil)
            Issue.record("Expected malformed response")
        } catch let error as CanvasConnectorError {
            #expect(error.category == .malformedResponse)
            #expect(!error.description.contains(privateMarker))
            #expect(!error.description.contains("SECRET-AUTHORIZATION-MARKER"))
            #expect(!error.description.contains("canvas.invalid"))
        }
    }

    @Test("401, 403, 404, 429, and 5xx have explicit retry classifications")
    func statusClassification() async throws {
        let cases: [(Int, CanvasErrorCategory, Bool, Int)] = [
            (401, .unauthorized, false, 1),
            (403, .forbidden, false, 1),
            (404, .notFound, false, 1),
            (429, .rateLimited, true, 3),
            (503, .serverUnavailable, true, 3)
        ]
        for (status, category, retryable, attempts) in cases {
            let sleeper = RecordingSleeper()
            let jitter = SequenceRetryJitter(values: [1.5, 1.5])
            let transport = StubCanvasTransport(outcomes: (0..<attempts).map { _ in
                .response(status: status, data: Data("PRIVATE ERROR BODY".utf8), headers: ["Retry-After": "0"])
            })
            let connector = try makeConnector(transport: transport, sleeper: sleeper, jitter: jitter)
            do {
                _ = try await connector.courses(pageToken: nil)
                Issue.record("Expected HTTP failure \(status)")
            } catch let error as CanvasConnectorError {
                #expect(error.category == category)
                #expect(error.retryable == retryable)
                #expect(!error.description.contains("PRIVATE ERROR BODY"))
            }
            #expect(await transport.requests.count == attempts)
            #expect(await sleeper.delays.count == max(0, attempts - 1))
            #expect(jitter.callCount == 0)
        }
    }

    @Test("Timeouts retry within the configured bound")
    func timeout() async throws {
        let transport = StubCanvasTransport(outcomes: [.urlError(.timedOut), .urlError(.timedOut)])
        let connector = try makeConnector(transport: transport, maximumAttempts: 2)
        do {
            _ = try await connector.courses(pageToken: nil)
            Issue.record("Expected timeout")
        } catch let error as CanvasConnectorError {
            #expect(error.category == .timedOut)
            #expect(error.retryable)
        }
        #expect(await transport.requests.count == 2)
    }

    @Test("Retry backoff uses injected jitter and remains capped")
    func boundedJitteredBackoff() async throws {
        let sleeper = RecordingSleeper()
        let jitter = SequenceRetryJitter(values: [0.5, 1.5, 1.5, 1.5, 1.5])
        let transport = StubCanvasTransport(outcomes: (0..<6).map { _ in
            .response(status: 503, data: Data(), headers: [:])
        })
        let connector = try makeConnector(
            transport: transport,
            sleeper: sleeper,
            jitter: jitter,
            maximumAttempts: 6,
            maximumBackoff: 8
        )

        do {
            _ = try await connector.courses(pageToken: nil)
            Issue.record("Expected retry exhaustion")
        } catch let error as CanvasConnectorError {
            #expect(error.category == .serverUnavailable)
        }
        #expect(await sleeper.delays == [0.5, 3, 6, 8, 8])
        #expect(jitter.callCount == 5)
    }

    @Test("Unsafe cross-origin pagination is rejected before transport")
    func unsafePagination() async throws {
        let transport = StubCanvasTransport(outcomes: [])
        let connector = try makeConnector(transport: transport)
        do {
            _ = try await connector.courses(pageToken: "https://attacker.invalid/api/v1/courses?page=2")
            Issue.record("Expected unsafe pagination failure")
        } catch let error as CanvasConnectorError {
            #expect(error.category == .unsafePagination)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Every network operation is a read-only GET with Keychain authorization")
    func readOnlyRequests() async throws {
        let transport = StubCanvasTransport(outcomes: [
            .response(status: 200, data: Data("[]".utf8), headers: [:]),
            .response(status: 200, data: Data("[]".utf8), headers: [:]),
            .response(status: 200, data: Data("[]".utf8), headers: [:])
        ])
        let connector = try makeConnector(transport: transport)
        _ = try await connector.courses(pageToken: nil)
        _ = try await connector.learningTasks(courseID: "31001", pageToken: nil)
        _ = try await connector.announcements(courseID: "31001", pageToken: nil)

        let requests = await transport.requests
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true })
    }

    @Test("Repeated sanitized fixture snapshots are stable and duplicate-free")
    func idempotentFixtureSnapshot() async throws {
        let courses: [CanvasCourseDTO] = try fixtureDecoder().decode(
            [CanvasCourseDTO].self, from: fixture("courses-page-1")
        )
        let assignments: [CanvasAssignmentDTO] = try fixtureDecoder().decode(
            [CanvasAssignmentDTO].self, from: fixture("assignments")
        )
        let announcements: [CanvasAnnouncementDTO] = try fixtureDecoder().decode(
            [CanvasAnnouncementDTO].self, from: fixture("announcements")
        )
        let service = DuplicateFixtureCanvasService(
            courses: courses.map(\.payload),
            tasks: assignments.map { $0.payload(fallbackCourseID: "31001") },
            announcements: announcements.map { $0.payload(fallbackCourseID: "31001") }
        )
        let loader = CanvasSnapshotLoader(service: service)
        let first = try await loader.load()
        let second = try await loader.load()

        #expect(first == second)
        #expect(first.courses.count == 1)
        #expect(first.tasks.count == 5)
        #expect(first.announcements.count == 1)
    }

    @Test("Configuration accepts only credential-free HTTPS base URLs")
    func configurationValidation() throws {
        _ = try CanvasConfiguration(baseURL: URL(string: "https://canvas.invalid")!)
        #expect(try CanvasLocalTool.validatedConfiguration("https://canvas.invalid/").baseURL.absoluteString == "https://canvas.invalid")
        #expect(throws: CanvasConfigurationError.self) {
            _ = try CanvasConfiguration(baseURL: URL(string: "http://canvas.invalid")!)
        }
        #expect(throws: CanvasConfigurationError.self) {
            _ = try CanvasConfiguration(baseURL: URL(string: "https://user:secret@canvas.invalid")!)
        }
        #expect(throws: CanvasConfigurationError.self) {
            _ = try CanvasLocalTool.validatedConfiguration("synthetic-token-shaped-input")
        }
    }

    private func makeConnector(
        transport: any CanvasHTTPTransport,
        sleeper: RecordingSleeper = RecordingSleeper(),
        jitter: any CanvasRetryJitter = SequenceRetryJitter(values: [1]),
        maximumAttempts: Int = 3,
        maximumBackoff: TimeInterval = 8,
        maximumConcurrentRequests: Int = 1,
        token: String = "synthetic-token-material"
    ) throws -> CanvasAPIConnector {
        let secrets = FakeSecretStore()
        try secrets.set(Data(token.utf8), account: CanvasConfiguration.tokenAccount)
        return CanvasAPIConnector(
            configuration: try CanvasConfiguration(baseURL: URL(string: "https://canvas.invalid")!),
            secretStore: secrets,
            transport: transport,
            sleeper: sleeper,
            jitter: jitter,
            maximumAttempts: maximumAttempts,
            maximumBackoff: maximumBackoff,
            maximumConcurrentRequests: maximumConcurrentRequests
        )
    }
}

private enum StubOutcome: Sendable {
    case response(status: Int, data: Data, headers: [String: String])
    case urlError(URLError.Code)
}

private actor StubCanvasTransport: CanvasHTTPTransport {
    private var outcomes: [StubOutcome]
    private(set) var requests: [URLRequest] = []

    init(outcomes: [StubOutcome]) { self.outcomes = outcomes }

    func send(_ request: URLRequest) async throws -> CanvasHTTPResult {
        requests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        switch outcomes.removeFirst() {
        case .urlError(let code): throw URLError(code)
        case .response(let status, let data, let headers):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
            )!
            return CanvasHTTPResult(data: data, response: response)
        }
    }
}

private actor RecordingSleeper: CanvasRetrySleeper {
    private(set) var delays: [TimeInterval] = []
    func sleep(for delay: TimeInterval) async throws { delays.append(delay) }
}

private final class SequenceRetryJitter: CanvasRetryJitter, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double]
    private var calls = 0

    init(values: [Double]) { self.values = values }

    var callCount: Int { lock.withLock { calls } }

    func multiplier() -> Double {
        lock.withLock {
            calls += 1
            return values.isEmpty ? 1 : values.removeFirst()
        }
    }
}

private actor ControlledConcurrencyTransport: CanvasHTTPTransport {
    private(set) var startedCount = 0
    private(set) var maximumObservedConcurrency = 0
    private var activeCount = 0
    private var released = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var startObservers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func send(_ request: URLRequest) async throws -> CanvasHTTPResult {
        startedCount += 1
        activeCount += 1
        maximumObservedConcurrency = max(maximumObservedConcurrency, activeCount)
        let ready = startObservers.filter { startedCount >= $0.count }
        startObservers.removeAll { startedCount >= $0.count }
        ready.forEach { $0.continuation.resume() }

        if !released {
            await withCheckedContinuation { blocked.append($0) }
        }

        activeCount -= 1
        return CanvasHTTPResult(
            data: Data("[]".utf8),
            response: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]
            )!
        )
    }

    func waitUntilStarted(_ count: Int) async {
        guard startedCount < count else { return }
        await withCheckedContinuation { startObservers.append((count, $0)) }
    }

    func releaseAll() {
        released = true
        let continuations = blocked
        blocked.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private actor GateOperationBlocker {
    private var started = false
    private var released = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var startObservers: [CheckedContinuation<Void, Never>] = []

    func run() async {
        started = true
        let observers = startObservers
        startObservers.removeAll()
        observers.forEach { $0.resume() }
        if !released { await withCheckedContinuation { blocked.append($0) } }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startObservers.append($0) }
    }

    func releaseAll() {
        released = true
        let continuations = blocked
        blocked.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private actor OperationFlag {
    private(set) var didRun = false
    func markRun() { didRun = true }
}

private func waitUntilQueued(_ gate: CanvasConcurrencyGate, count: Int) async -> Bool {
    for _ in 0..<10_000 {
        if await gate.queuedRequestCount() == count { return true }
        await Task.yield()
    }
    return false
}

private actor DuplicateFixtureCanvasService: CanvasService {
    let courseValues: [CanvasCoursePayload]
    let taskValues: [CanvasTaskPayload]
    let announcementValues: [CanvasAnnouncementPayload]

    init(courses: [CanvasCoursePayload], tasks: [CanvasTaskPayload], announcements: [CanvasAnnouncementPayload]) {
        courseValues = courses + courses
        taskValues = tasks + tasks
        announcementValues = announcements + announcements
    }

    func courses(pageToken: String?) async throws -> FetchPage<CanvasCoursePayload> {
        FetchPage(values: courseValues, nextPageToken: nil, isCompleteSnapshot: true)
    }
    func learningTasks(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasTaskPayload> {
        FetchPage(values: taskValues, nextPageToken: nil, isCompleteSnapshot: true)
    }
    func announcements(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasAnnouncementPayload> {
        FetchPage(values: announcementValues, nextPageToken: nil, isCompleteSnapshot: true)
    }
}

private func fixture(_ name: String) -> Data {
    try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Canvas")!)
}

private func fixtureDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func isoDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
