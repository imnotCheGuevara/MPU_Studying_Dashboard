import Foundation
import Network
import Testing
@testable import CampusDashboard

@Suite("SIweb authorized read-only crawler")
struct SIwebConnectorTests {
    private let baseURL = URL(string: "https://siweb.invalid")!

    @Test("Normal page parses courses, multiple meetings, links, timezone edges, and cancellation")
    func normalPage() throws {
        let result = try parser().parse(siwebFixture("normal"))
        #expect(result.meetings.count == 3)
        let first = result.meetings.first { $0.sourceObjectID == "meeting-101-a" }!
        #expect(first.courseSourceObjectID == "course-101")
        #expect(first.courseName == "Synthetic Systems & Society")
        #expect(first.courseCode == "SYN101")
        #expect(first.location == "Room A")
        #expect(first.timeZoneIdentifier == "UTC-07:00")
        #expect(first.endsAt.timeIntervalSince(first.startsAt) == 3_000)
        #expect(first.sourceURL == URL(string: "https://siweb.invalid/siweb/course/101"))
        #expect(first.sourceContentHash.count == 64)
        #expect(result.meetings.first { $0.sourceObjectID == "meeting-101-b" }?.isCancelled == true)
        #expect(result.meetings.allSatisfy { $0.parserVersion == SIwebHTMLParser.version })
    }

    @Test("MPU Class Time table expands periods and dot-marked weekdays")
    func mpuClassTime() throws {
        let result = try parser().parse(siwebFixture("mpu-class-time"))
        #expect(result.meetings.count == 7)
        #expect(Set(result.meetings.map(\.courseSourceObjectID)) == ["SYN1001-001", "SYN2002-002"])
        #expect(result.meetings.filter { $0.courseSourceObjectID == "SYN1001-001" }.count == 5)
        #expect(result.meetings.filter { $0.location == "Lab 2" }.count == 2)
        #expect(result.meetings.allSatisfy { $0.parserVersion == SIwebHTMLParser.mpuVersion })
        #expect(result.meetings.allSatisfy { $0.timeZoneIdentifier == "Asia/Macau" })
        #expect(result.meetings.allSatisfy { !$0.isCancelled })
        #expect(result.meetings.allSatisfy { $0.sourceContentHash.count == 64 })
        #expect(result.meetings.allSatisfy { $0.sourceURL == URL(string: "https://siweb.invalid/time_stud.asp") })

        let second = try parser().parse(siwebFixture("mpu-class-time"))
        #expect(result == second)
    }

    @Test("MPU structural changes and incomplete rows fail closed")
    func mpuStructuralChange() throws {
        let header = """
        <tr><td>Sem</td><td>Class Code</td><td>Learning Module</td><td>Instructor</td><td>Venue</td><td>Period</td><td>Time</td><td>Sun</td><td>Mon</td><td>Tue</td><td>Wed</td><td>Thu</td><td>Fri</td><td>Sat</td></tr>
        """
        let noDay = """
        <html><body><table>\(header)<tr><td>1</td><td>SYN</td><td>Course</td><td>Teacher</td><td>Room</td><td>2026/08/24-2026/09/07</td><td>09:00-10:00</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr></table></body></html>
        """
        try expectSIwebError(.structuralChange) { _ = try parser().parse(Data(noDay.utf8)) }

        let malformedPeriod = noDay.replacingOccurrences(
            of: "2026/08/24-2026/09/07", with: "24-08-2026 through 07-09-2026"
        ).replacingOccurrences(of: "<td></td><td></td><td></td><td></td><td></td><td></td><td></td>", with: "<td></td><td><img src='images/dot.gif'></td><td></td><td></td><td></td><td></td><td></td>")
        try expectSIwebError(.structuralChange) { _ = try parser().parse(Data(malformedPeriod.utf8)) }

        let reordered = noDay.replacingOccurrences(of: "<td>Venue</td><td>Period</td>", with: "<td>Period</td><td>Venue</td>")
        try expectSIwebError(.structuralChange) { _ = try parser().parse(Data(reordered.utf8)) }
    }

    @Test("MPU exact header with no rows is an explicit complete empty snapshot")
    func mpuEmpty() throws {
        let html = """
        <html><body><table><tr><td>Sem</td><td>Class Code</td><td>Learning Module</td><td>Instructor</td><td>Venue</td><td>Period</td><td>Time</td><td>Sun</td><td>Mon</td><td>Tue</td><td>Wed</td><td>Thu</td><td>Fri</td><td>Sat</td></tr><tr><td colspan="14">No synthetic rows</td></tr></table></body></html>
        """
        #expect(try parser().parse(Data(html.utf8)).meetings.isEmpty)
    }

    @Test("Empty schedule is accepted only with explicit semantic markers")
    func emptyPage() throws {
        #expect(try parser().parse(siwebFixture("empty")).meetings.isEmpty)
    }

    @Test("Missing optional values produce a deterministic derived stable ID")
    func optionalFieldsAndStableID() throws {
        let first = try parser().parse(siwebFixture("normal")).meetings.first {
            $0.courseSourceObjectID == "course-202"
        }!
        let second = try parser().parse(siwebFixture("normal")).meetings.first {
            $0.courseSourceObjectID == "course-202"
        }!
        #expect(first.sourceObjectID.hasPrefix("derived-v1-"))
        #expect(first.sourceObjectID == second.sourceObjectID)
        #expect(first.courseCode == nil)
        #expect(first.location == nil)
        #expect(first.sourceURL == nil)
    }

    @Test("Login content is session expiry, not a structural import")
    func expiredSession() throws {
        try expectSIwebError(.sessionExpired) { _ = try parser().parse(siwebFixture("login")) }
    }

    @Test("Partial HTML never emits guessed meetings")
    func partialResponse() throws {
        try expectSIwebError(.partialResponse) { _ = try parser().parse(siwebFixture("partial")) }
        let truncatedArticle = """
        <main data-siweb-contract="schedule-v1">
        <article data-siweb-course-id="c" data-siweb-course-name="Course">
          <div data-siweb-start="2026-09-01T09:00:00+08:00" data-siweb-end="2026-09-01T10:00:00+08:00"></div>
        <meta data-siweb-complete="true"></main>
        """
        try expectSIwebError(.partialResponse) { _ = try parser().parse(Data(truncatedArticle.utf8)) }
    }

    @Test("Changed DOM stops import with a structural-change category")
    func changedDOM() throws {
        try expectSIwebError(.structuralChange) { _ = try parser().parse(siwebFixture("changed-dom")) }
        let missingMeetingMarkers = page(course: """
        <article data-siweb-course-id="course-1" data-siweb-course-name="Course">
          <div class="new-visual-meeting-row">Changed meeting DOM</div>
        </article>
        """)
        try expectSIwebError(.structuralChange) {
            _ = try parser().parse(Data(missingMeetingMarkers.utf8))
        }
    }

    @Test("Unknown status and timezone-free dates violate the structural contract")
    func invalidContractFields() throws {
        let html = page(course: """
        <article data-siweb-course-id="c" data-siweb-course-name="Course">
          <div data-siweb-start="2026-09-01T09:00:00" data-siweb-end="2026-09-01T10:00:00" data-siweb-status="moved"></div>
        </article>
        """)
        try expectSIwebError(.structuralChange) { _ = try parser().parse(Data(html.utf8)) }
    }

    @Test("Repeated parsing and snapshot collection are idempotent")
    func idempotent() async throws {
        let values = try parser().parse(siwebFixture("normal")).meetings
        let service = DuplicateSIwebService(values: values + values)
        let loader = SIwebSnapshotLoader(service: service)
        let first = try await loader.load()
        let second = try await loader.load()
        #expect(first == second)
        #expect(first.meetings.count == 3)
    }

    @Test("Conflicting duplicate stable IDs stop snapshot collection")
    func conflictingDuplicate() async throws {
        let original = try parser().parse(siwebFixture("normal")).meetings[0]
        let conflict = SIwebMeetingPayload(
            sourceObjectID: original.sourceObjectID,
            courseSourceObjectID: original.courseSourceObjectID,
            courseName: original.courseName,
            courseCode: original.courseCode,
            startsAt: original.startsAt,
            endsAt: original.endsAt,
            timeZoneIdentifier: original.timeZoneIdentifier,
            location: "Conflicting room",
            isCancelled: original.isCancelled,
            sourceURL: original.sourceURL,
            parserVersion: original.parserVersion,
            sourceContentHash: original.sourceContentHash
        )
        let loader = SIwebSnapshotLoader(service: DuplicateSIwebService(values: [original, conflict]))
        await expectSIwebErrorAsync(.structuralChange) { _ = try await loader.load() }
    }

    @Test("Network requests are authorized GETs to explicitly allowed routes only")
    func readOnlyAllowedRoutes() async throws {
        let transport = StubSIwebTransport(outcomes: [
            .response(status: 200, data: siwebFixture("empty"), headers: ["Content-Type": "text/html"])
        ])
        let connector = try makeConnector(transport: transport)
        _ = try await connector.meetings(pageToken: nil)
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].httpBody == nil)
        #expect(requests[0].url == URL(string: "https://siweb.invalid/siweb/schedule"))
        #expect(requests[0].value(forHTTPHeaderField: "Cookie") == "synthetic-session=opaque")

        await expectSIwebErrorAsync(.unsafeRoute) {
            _ = try await connector.meetings(pageToken: "https://attacker.invalid/siweb/schedule")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Redirects, partial HTTP, and HTML login pages stop without importing")
    func sessionAndPartialNetworkFailures() async throws {
        let transport = StubSIwebTransport(outcomes: [
            .response(status: 302, data: Data(), headers: ["Location": "/sso/login"]),
            .response(status: 206, data: siwebFixture("partial"), headers: ["Content-Type": "text/html"]),
            .response(status: 200, data: siwebFixture("login"), headers: ["Content-Type": "text/html"])
        ])
        let connector = try makeConnector(transport: transport)
        await expectSIwebErrorAsync(.loginRedirect) { _ = try await connector.meetings(pageToken: nil) }
        await expectSIwebErrorAsync(.partialResponse) { _ = try await connector.meetings(pageToken: nil) }
        await expectSIwebErrorAsync(.sessionExpired) { _ = try await connector.meetings(pageToken: nil) }
    }

    @Test("Production URLSession returns the original redirect without forwarding Cookie")
    func productionTransportBlocksRedirects() async throws {
        let server = try SIwebRedirectProbeServer()
        defer { server.stop() }

        var request = URLRequest(url: server.startURL)
        request.setValue("synthetic-session=opaque", forHTTPHeaderField: "Cookie")
        let result = try await URLSessionSIwebTransport(timeout: 5).send(request)

        #expect(result.response.statusCode == 302)
        #expect(result.response.url == server.startURL)
        try await Task.sleep(for: .milliseconds(100))
        let probe = server.snapshot()
        #expect(probe.paths == ["/start"])
        #expect(probe.redirectTargetCookies.isEmpty)
    }

    @Test("429 and temporary failures retry with bounded redacted diagnostics")
    func retriesAndRedaction() async throws {
        let transport = StubSIwebTransport(outcomes: [
            .response(status: 429, data: Data("private-body-marker".utf8), headers: ["Retry-After": "2"]),
            .response(status: 503, data: Data("private-body-marker".utf8), headers: [:]),
            .response(status: 200, data: siwebFixture("empty"), headers: ["Content-Type": "text/html"])
        ])
        let sleeper = SIwebRecordingSleeper()
        let connector = try makeConnector(transport: transport, sleeper: sleeper, maximumAttempts: 3)
        _ = try await connector.meetings(pageToken: nil)
        #expect(await sleeper.delays == [2, 2])
        #expect(await transport.requests.count == 3)

        let failed = StubSIwebTransport(outcomes: [
            .response(status: 403, data: Data("private-body-marker".utf8), headers: [:])
        ])
        let failedConnector = try makeConnector(transport: failed)
        do {
            _ = try await failedConnector.meetings(pageToken: nil)
            Issue.record("Expected forbidden")
        } catch let error as SIwebConnectorError {
            #expect(error.category == .forbidden)
            #expect(!error.diagnostic.contains("private-body-marker"))
            #expect(!error.diagnostic.contains("siweb.invalid"))
            #expect(!error.diagnostic.contains("synthetic-session"))
        }
    }

    @Test("Timeouts retry only within the configured attempt bound")
    func timeoutRetry() async throws {
        let transport = StubSIwebTransport(outcomes: [.urlError(.timedOut), .urlError(.timedOut)])
        let sleeper = SIwebRecordingSleeper()
        let connector = try makeConnector(transport: transport, sleeper: sleeper, maximumAttempts: 2)
        await expectSIwebErrorAsync(.timedOut) { _ = try await connector.meetings(pageToken: nil) }
        #expect(await sleeper.delays == [1])
        #expect(await transport.requests.count == 2)
    }

    @Test("Configured concurrency and minimum request interval bound network starts")
    func limits() async throws {
        let blocking = ControlledSIwebTransport()
        let connector = try makeConnector(
            transport: blocking, minimumInterval: 0, maximumConcurrentRequests: 2
        )
        let tasks = (0..<6).map { _ in Task { try await connector.meetings(pageToken: nil) } }
        await blocking.waitUntilStarted(2)
        #expect(await blocking.startedCount == 2)
        #expect(await blocking.maximumObservedConcurrency == 2)
        await blocking.releaseAll()
        for task in tasks { _ = try await task.value }
        #expect(await blocking.startedCount == 6)
        #expect(await blocking.maximumObservedConcurrency == 2)

        let timing = TimingSIwebTransport()
        let paced = try makeConnector(
            transport: timing, minimumInterval: 0.05, maximumConcurrentRequests: 2,
            targets: ["/siweb/schedule", "/siweb/schedule?page=2"]
        )
        async let one = paced.meetings(pageToken: nil)
        async let two = paced.meetings(pageToken: "https://siweb.invalid/siweb/schedule?page=2")
        _ = try await (one, two)
        let starts = await timing.starts.sorted()
        #expect(starts.count == 2)
        #expect(starts[1] - starts[0] >= 0.04)
    }

    @Test("Configuration rejects credentials, cross-origin targets, and unsafe limits")
    func configuration() throws {
        #expect(throws: SIwebConfigurationError.self) {
            _ = try SIwebConfiguration(
                baseURL: URL(string: "http://siweb.invalid")!,
                targetPageURLs: [URL(string: "http://siweb.invalid/schedule")!]
            )
        }
        #expect(throws: SIwebConfigurationError.self) {
            _ = try SIwebConfiguration(
                baseURL: baseURL,
                targetPageURLs: [URL(string: "https://other.invalid/schedule")!]
            )
        }
        #expect(throws: SIwebConfigurationError.self) {
            _ = try SIwebConfiguration(
                baseURL: baseURL,
                targetPageURLs: [URL(string: "https://siweb.invalid/schedule")!],
                maximumConcurrentRequests: 10
            )
        }
        #expect(throws: SIwebConfigurationError.self) {
            _ = try SIwebConfiguration(
                baseURL: baseURL,
                targetPageURLs: [URL(string: "https://siweb.invalid/schedule?session=secret")!]
            )
        }
    }

    @Test("Keychain session authorizer keeps opaque session material out of configuration")
    func keychainSessionBoundary() throws {
        let secrets = FakeSecretStore()
        try secrets.set(Data("synthetic-session=opaque".utf8), account: SIwebConfiguration.sessionAccount)
        var request = URLRequest(url: URL(string: "https://siweb.invalid/siweb/schedule")!)
        try KeychainSIwebSessionAuthorizer(
            secretStore: secrets, account: SIwebConfiguration.sessionAccount
        ).authorize(&request)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "synthetic-session=opaque")

        try secrets.set(Data("invalid\nheader".utf8), account: SIwebConfiguration.sessionAccount)
        #expect(throws: SIwebConnectorError.self) {
            try KeychainSIwebSessionAuthorizer(
                secretStore: secrets, account: SIwebConfiguration.sessionAccount
            ).authorize(&request)
        }
    }

    @Test("Web login captures only secure unexpired target-domain session cookies")
    func webSessionCookieBoundary() throws {
        let future = Date(timeIntervalSince1970: 2_000_000_000)
        let past = Date(timeIntervalSince1970: 1_000_000_000)
        let now = Date(timeIntervalSince1970: 1_500_000_000)
        let accepted = try #require(HTTPCookie(properties: [
            .name: "SYNTHETIC", .value: "opaque", .domain: "wapps2.ipm.edu.mo",
            .path: "/", .secure: "TRUE", .expires: future
        ]))
        let wrongDomain = try #require(HTTPCookie(properties: [
            .name: "OTHER", .value: "opaque", .domain: "account.ipm.edu.mo",
            .path: "/", .secure: "TRUE", .expires: future
        ]))
        let publishedEntryDomain = try #require(HTTPCookie(properties: [
            .name: "PUBLISHED", .value: "opaque", .domain: "wapps2.mpu.edu.mo",
            .path: "/", .secure: "TRUE", .expires: future
        ]))
        let expired = try #require(HTTPCookie(properties: [
            .name: "EXPIRED", .value: "opaque", .domain: "wapps2.ipm.edu.mo",
            .path: "/siweb_cas", .secure: "TRUE", .expires: past
        ]))
        let insecure = try #require(HTTPCookie(properties: [
            .name: "INSECURE", .value: "opaque", .domain: "wapps2.ipm.edu.mo",
            .path: "/siweb_cas", .expires: future
        ]))
        let data = try #require(SIwebSessionCookieSerializer.headerData(
            from: [wrongDomain, publishedEntryDomain, expired, insecure, accepted], now: now
        ))
        #expect(String(data: data, encoding: .utf8) == "SYNTHETIC=opaque")
    }

    @Test("MPU published entry and operational crawler target remain distinct")
    func mpuEndpointContract() {
        #expect(MPUSIwebEndpoints.publishedEntryURL.absoluteString == "https://wapps2.mpu.edu.mo/siweb_cas/")
        #expect(MPUSIwebEndpoints.operationalBaseURL.absoluteString == "https://wapps2.ipm.edu.mo/siweb_cas")
        #expect(MPUSIwebEndpoints.classTimeURL.absoluteString == "https://wapps2.ipm.edu.mo/siweb_cas/time_stud.asp")
        #expect(MPUSIwebEndpoints.publishedEntryURL.host != MPUSIwebEndpoints.classTimeURL.host)
    }

    private func parser() -> SIwebHTMLParser { SIwebHTMLParser(baseURL: baseURL) }

    private func page(course: String) -> String {
        "<main data-siweb-contract=\"schedule-v1\">\(course)<meta data-siweb-complete=\"true\"></main>"
    }

    private func makeConnector(
        transport: any SIwebHTTPTransport,
        sleeper: any SIwebRetrySleeper = SIwebRecordingSleeper(),
        maximumAttempts: Int = 1,
        minimumInterval: TimeInterval = 0,
        maximumConcurrentRequests: Int = 1,
        targets: [String] = ["/siweb/schedule"]
    ) throws -> SIwebConnector {
        let urls = targets.map { URL(string: "https://siweb.invalid\($0)")! }
        let configuration = try SIwebConfiguration(
            baseURL: baseURL, targetPageURLs: urls, minimumRequestInterval: minimumInterval,
            maximumConcurrentRequests: maximumConcurrentRequests
        )
        return SIwebConnector(
            configuration: configuration, authorizer: SyntheticSIwebAuthorizer(),
            transport: transport, sleeper: sleeper, jitter: FixedSIwebJitter(),
            maximumAttempts: maximumAttempts
        )
    }
}

private final class SIwebRedirectProbeServer: @unchecked Sendable {
    struct Snapshot {
        let paths: [String]
        let redirectTargetCookies: [String]
    }

    enum ProbeError: Error { case startupFailed }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "SIwebRedirectProbeServer")
    private let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var paths: [String] = []
    private var redirectTargetCookies: [String] = []

    var startURL: URL {
        URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/start")!
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .failed:
                self?.ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, listener.port != nil else {
            listener.cancel()
            throw ProbeError.startupFailed
        }
    }

    func stop() { listener.cancel() }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(paths: paths, redirectTargetCookies: redirectTargetCookies)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
            [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let lines = request.components(separatedBy: "\r\n")
            let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let cookie = lines.first { $0.lowercased().hasPrefix("cookie:") }
                .map { String($0.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespaces) }

            lock.lock()
            paths.append(path)
            if path == "/target", let cookie { redirectTargetCookies.append(cookie) }
            lock.unlock()

            let response: String
            if path == "/start" {
                response = "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:\(listener.port!.rawValue)/target\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            } else {
                response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

private struct SyntheticSIwebAuthorizer: SIwebSessionAuthorizer {
    func authorize(_ request: inout URLRequest) throws {
        request.setValue("synthetic-session=opaque", forHTTPHeaderField: "Cookie")
    }
}

private struct FixedSIwebJitter: SIwebRetryJitter { func multiplier() -> Double { 1 } }

private enum SIwebStubOutcome: Sendable {
    case response(status: Int, data: Data, headers: [String: String])
    case urlError(URLError.Code)
}

private actor StubSIwebTransport: SIwebHTTPTransport {
    private var outcomes: [SIwebStubOutcome]
    private(set) var requests: [URLRequest] = []

    init(outcomes: [SIwebStubOutcome]) { self.outcomes = outcomes }

    func send(_ request: URLRequest) async throws -> SIwebHTTPResult {
        requests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        switch outcomes.removeFirst() {
        case .urlError(let code): throw URLError(code)
        case .response(let status, let data, let headers):
            return SIwebHTTPResult(
                data: data,
                response: HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
                )!
            )
        }
    }
}

private actor SIwebRecordingSleeper: SIwebRetrySleeper {
    private(set) var delays: [TimeInterval] = []
    func sleep(for delay: TimeInterval) async throws { delays.append(delay) }
}

private actor DuplicateSIwebService: SIwebService {
    let values: [SIwebMeetingPayload]
    init(values: [SIwebMeetingPayload]) { self.values = values }
    func meetings(pageToken: String?) async throws -> FetchPage<SIwebMeetingPayload> {
        FetchPage(values: values, nextPageToken: nil, isCompleteSnapshot: true)
    }
}

private actor ControlledSIwebTransport: SIwebHTTPTransport {
    private(set) var startedCount = 0
    private(set) var maximumObservedConcurrency = 0
    private var active = 0
    private var released = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func send(_ request: URLRequest) async throws -> SIwebHTTPResult {
        startedCount += 1
        active += 1
        maximumObservedConcurrency = max(maximumObservedConcurrency, active)
        let ready = observers.filter { startedCount >= $0.0 }
        observers.removeAll { startedCount >= $0.0 }
        ready.forEach { $0.1.resume() }
        if !released { await withCheckedContinuation { blocked.append($0) } }
        active -= 1
        return htmlResult(request)
    }

    func waitUntilStarted(_ count: Int) async {
        guard startedCount < count else { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func releaseAll() {
        released = true
        let values = blocked
        blocked.removeAll()
        values.forEach { $0.resume() }
    }
}

private actor TimingSIwebTransport: SIwebHTTPTransport {
    private(set) var starts: [TimeInterval] = []
    func send(_ request: URLRequest) async throws -> SIwebHTTPResult {
        starts.append(ProcessInfo.processInfo.systemUptime)
        return htmlResult(request)
    }
}

private func htmlResult(_ request: URLRequest) -> SIwebHTTPResult {
    SIwebHTTPResult(
        data: siwebFixture("empty"),
        response: HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html"]
        )!
    )
}

private func siwebFixture(_ name: String) -> Data {
    try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "SIweb")!)
}

private func expectSIwebError(
    _ category: SIwebErrorCategory, operation: () throws -> Void
) throws {
    do { try operation(); Issue.record("Expected SIweb error \(category.rawValue)") }
    catch let error as SIwebConnectorError { #expect(error.category == category) }
}

private func expectSIwebErrorAsync(
    _ category: SIwebErrorCategory, operation: () async throws -> Void
) async {
    do { try await operation(); Issue.record("Expected SIweb error \(category.rawValue)") }
    catch let error as SIwebConnectorError { #expect(error.category == category) }
    catch { Issue.record("Unexpected error type: \(error)") }
}
