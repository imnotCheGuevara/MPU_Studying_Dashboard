import Foundation

enum SIwebErrorCategory: String, Sendable {
    case configuration
    case unsafeRoute
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverUnavailable
    case timedOut
    case offline
    case transport
    case sessionExpired
    case loginRedirect
    case partialResponse
    case structuralChange
    case malformedResponse
}

struct SIwebConnectorError: Error, Equatable, Sendable, CustomStringConvertible {
    let category: SIwebErrorCategory
    let retryable: Bool
    let retryAfter: TimeInterval?
    let diagnostic: String

    var description: String { diagnostic }

    static func structural(
        _ category: SIwebErrorCategory, contractDiagnostic: String? = nil
    ) -> SIwebConnectorError {
        SIwebConnectorError(
            category: category, retryable: false, retryAfter: nil,
            diagnostic: "SIweb read failed: \(category.rawValue)" +
                (contractDiagnostic.map { " [\($0)]" } ?? "")
        )
    }

    func withContractDiagnostic(_ value: String) -> SIwebConnectorError {
        guard !diagnostic.contains("[") else { return self }
        return SIwebConnectorError(
            category: category, retryable: retryable, retryAfter: retryAfter,
            diagnostic: diagnostic + " [\(value)]"
        )
    }
}

struct SIwebHTTPResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol SIwebHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> SIwebHTTPResult
}

private final class SIwebRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct URLSessionSIwebTransport: SIwebHTTPTransport {
    let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(
            configuration: configuration,
            delegate: SIwebRedirectBlocker(),
            delegateQueue: nil
        )
    }

    func send(_ request: URLRequest) async throws -> SIwebHTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SIwebConnectorError.structural(.malformedResponse)
        }
        return SIwebHTTPResult(data: data, response: response)
    }
}

protocol SIwebSessionAuthorizer: Sendable {
    func authorize(_ request: inout URLRequest) throws
}

struct KeychainSIwebSessionAuthorizer: SIwebSessionAuthorizer {
    let secretStore: any SecretStore
    let account: String

    func authorize(_ request: inout URLRequest) throws {
        let data: Data
        do { data = try secretStore.data(account: account) }
        catch { throw SIwebConnectorError.structural(.configuration) }
        guard let cookie = String(data: data, encoding: .utf8), !cookie.isEmpty,
              cookie.rangeOfCharacter(from: .newlines) == nil
        else { throw SIwebConnectorError.structural(.configuration) }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
    }
}

protocol SIwebRetrySleeper: Sendable {
    func sleep(for delay: TimeInterval) async throws
}

protocol SIwebRetryJitter: Sendable {
    func multiplier() -> Double
}

struct SystemSIwebRetrySleeper: SIwebRetrySleeper {
    func sleep(for delay: TimeInterval) async throws { try await Task.sleep(for: .seconds(delay)) }
}

struct SystemSIwebRetryJitter: SIwebRetryJitter {
    func multiplier() -> Double { Double.random(in: 0.5...1.5) }
}

actor SIwebConnector: SIwebService {
    private let configuration: SIwebConfiguration
    private let authorizer: any SIwebSessionAuthorizer
    private let transport: any SIwebHTTPTransport
    private let sleeper: any SIwebRetrySleeper
    private let jitter: any SIwebRetryJitter
    private let gate: SIwebConcurrencyGate
    private let pacer: SIwebRequestPacer
    private let parser: SIwebHTMLParser
    private let maximumAttempts: Int
    private let maximumBackoff: TimeInterval
    private let maximumBodyBytes: Int

    init(
        configuration: SIwebConfiguration,
        authorizer: any SIwebSessionAuthorizer,
        transport: (any SIwebHTTPTransport)? = nil,
        sleeper: any SIwebRetrySleeper = SystemSIwebRetrySleeper(),
        jitter: any SIwebRetryJitter = SystemSIwebRetryJitter(),
        maximumAttempts: Int = 3,
        maximumBackoff: TimeInterval = 8,
        maximumBodyBytes: Int = 4 * 1_024 * 1_024
    ) {
        self.configuration = configuration
        self.authorizer = authorizer
        self.transport = transport ?? URLSessionSIwebTransport(timeout: configuration.requestTimeout)
        self.sleeper = sleeper
        self.jitter = jitter
        gate = SIwebConcurrencyGate(limit: configuration.maximumConcurrentRequests)
        pacer = SIwebRequestPacer(minimumInterval: configuration.minimumRequestInterval)
        parser = SIwebHTMLParser(baseURL: configuration.baseURL)
        self.maximumAttempts = max(1, maximumAttempts)
        self.maximumBackoff = max(0, maximumBackoff)
        self.maximumBodyBytes = max(1, maximumBodyBytes)
    }

    func meetings(pageToken: String?) async throws -> FetchPage<SIwebMeetingPayload> {
        let url: URL
        do {
            if let pageToken, let candidate = URL(string: pageToken) {
                url = try configuration.validatedTarget(candidate)
            } else if pageToken != nil {
                throw SIwebConfigurationError.unsafeTargetPage
            } else {
                url = configuration.targetPageURLs[0]
            }
        } catch {
            throw SIwebConnectorError.structural(.unsafeRoute)
        }

        let result = try await request(url)
        let parsed = try parser.parse(result.data)
        let next: String?
        if let nextURL = parsed.nextPageURL {
            do { next = try configuration.validatedTarget(nextURL).absoluteString }
            catch { throw SIwebConnectorError.structural(.unsafeRoute) }
        } else {
            next = nil
        }
        return FetchPage(values: parsed.meetings, nextPageToken: next, isCompleteSnapshot: next == nil)
    }

    private func request(_ url: URL) async throws -> SIwebHTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        try authorizer.authorize(&request)
        let safeRequest = request
        let transport = self.transport

        var attempt = 0
        while true {
            attempt += 1
            do {
                let result = try await gate.withPermit {
                    try await self.pacer.waitForTurn()
                    return try await transport.send(safeRequest)
                }
                try validate(result, requestedURL: url)
                return result
            } catch let error as SIwebConnectorError {
                if error.retryable && attempt < maximumAttempts {
                    try await sleeper.sleep(for: retryDelay(attempt: attempt, error: error))
                    continue
                }
                throw error
            } catch {
                if error is CancellationError { throw error }
                let mapped = classifyTransport(error)
                if mapped.retryable && attempt < maximumAttempts {
                    try await sleeper.sleep(for: retryDelay(attempt: attempt, error: mapped))
                    continue
                }
                throw mapped
            }
        }
    }

    private func validate(_ result: SIwebHTTPResult, requestedURL: URL) throws {
        let response = result.response
        if (300..<400).contains(response.statusCode) {
            throw SIwebConnectorError.structural(.loginRedirect)
        }
        guard response.url == requestedURL else {
            throw SIwebConnectorError.structural(.loginRedirect)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw classify(statusCode: response.statusCode, response: response)
        }
        guard response.statusCode != 206, result.data.count <= maximumBodyBytes else {
            throw SIwebConnectorError.structural(.partialResponse)
        }
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           !contentType.contains("text/html") && !contentType.contains("application/xhtml+xml") {
            throw SIwebConnectorError.structural(.malformedResponse)
        }
    }

    private func classify(statusCode: Int, response: HTTPURLResponse) -> SIwebConnectorError {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        switch statusCode {
        case 401: return error(.sessionExpired, retryable: false)
        case 403: return error(.forbidden, retryable: false)
        case 404: return error(.notFound, retryable: false)
        case 429: return error(.rateLimited, retryable: true, retryAfter: retryAfter)
        case 500...599: return error(.serverUnavailable, retryable: true, retryAfter: retryAfter)
        default: return error(.malformedResponse, retryable: false)
        }
    }

    private func classifyTransport(_ underlying: Error) -> SIwebConnectorError {
        switch (underlying as? URLError)?.code {
        case .timedOut: return error(.timedOut, retryable: true)
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return error(.offline, retryable: true)
        default: return error(.transport, retryable: true)
        }
    }

    private func retryDelay(attempt: Int, error: SIwebConnectorError) -> TimeInterval {
        if let retryAfter = error.retryAfter { return retryAfter }
        let exponential = min(pow(2, Double(attempt - 1)), maximumBackoff)
        return min(maximumBackoff, exponential * min(1.5, max(0.5, jitter.multiplier())))
    }

    private func error(
        _ category: SIwebErrorCategory, retryable: Bool, retryAfter: TimeInterval? = nil
    ) -> SIwebConnectorError {
        SIwebConnectorError(
            category: category, retryable: retryable, retryAfter: retryAfter,
            diagnostic: "SIweb read failed: \(category.rawValue)"
        )
    }
}
