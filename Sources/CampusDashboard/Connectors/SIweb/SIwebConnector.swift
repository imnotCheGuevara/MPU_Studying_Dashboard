import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
        catch SecretStoreError.notFound { throw SIwebConnectorError.structural(.sessionExpired) }
        catch { throw SIwebConnectorError.structural(.unauthorized) }
        guard let cookie = String(data: data, encoding: .utf8), !cookie.isEmpty,
              cookie.rangeOfCharacter(from: .newlines) == nil
        else { throw SIwebConnectorError.structural(.configuration) }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
    }
}

protocol SIwebSessionLifecycle: Sendable {
    func refresh(from response: HTTPURLResponse, requestedURL: URL) throws
    func invalidate() throws
}

/// Keeps server-rotated SIweb cookies in Keychain without enabling URLSession's
/// ambient cookie jar. The server remains the sole authority over session life.
final class KeychainSIwebSessionLifecycle: SIwebSessionLifecycle, @unchecked Sendable {
    private let secretStore: any SecretStore
    private let account: String
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    init(
        secretStore: any SecretStore,
        account: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.secretStore = secretStore
        self.account = account
        self.now = now
    }

    func refresh(from response: HTTPURLResponse, requestedURL: URL) throws {
        guard requestedURL.scheme?.lowercased() == "https",
              response.url == requestedURL,
              let setCookie = response.value(forHTTPHeaderField: "Set-Cookie")
        else { return }
        let responseCookies = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": setCookie], for: requestedURL
        )
        guard !responseCookies.isEmpty else { return }
        let currentTime = now()

        try lock.withLock {
            let data: Data
            do { data = try secretStore.data(account: account) }
            catch SecretStoreError.notFound {
                // The user may have revoked authorization while this request was in flight.
                return
            } catch {
                throw SIwebConnectorError.structural(.configuration)
            }
            guard let rawHeader = String(data: data, encoding: .utf8),
                  var values = Self.parseCookieHeader(rawHeader)
            else { throw SIwebConnectorError.structural(.configuration) }

            var changed = false
            for cookie in responseCookies where Self.isEligible(cookie, for: requestedURL) {
                if let expiry = cookie.expiresDate, expiry <= currentTime {
                    changed = values.removeValue(forKey: cookie.name) != nil || changed
                } else if values[cookie.name] != cookie.value {
                    values[cookie.name] = cookie.value
                    changed = true
                }
            }
            guard changed else { return }
            if values.isEmpty {
                try secretStore.remove(account: account)
            } else {
                let header = values.keys.sorted().map { "\($0)=\(values[$0]!)" }
                    .joined(separator: "; ")
                try secretStore.set(Data(header.utf8), account: account)
            }
        }
    }

    func invalidate() throws {
        try lock.withLock { try secretStore.remove(account: account) }
    }

    private static func isEligible(_ cookie: HTTPCookie, for url: URL) -> Bool {
        let domain = cookie.domain.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard domain == url.host?.lowercased(), cookie.isSecure,
              path(cookie.path, matches: url.path),
              isSafeName(cookie.name), isSafeValue(cookie.value)
        else { return false }
        return true
    }

    private static func path(_ cookiePath: String, matches requestPath: String) -> Bool {
        guard cookiePath.hasPrefix("/"), requestPath.hasPrefix(cookiePath) else { return false }
        if requestPath == cookiePath || cookiePath.hasSuffix("/") { return true }
        return requestPath.dropFirst(cookiePath.count).first == "/"
    }

    private static func parseCookieHeader(_ header: String) -> [String: String]? {
        guard !header.isEmpty, header.rangeOfCharacter(from: .newlines) == nil else { return nil }
        var values: [String: String] = [:]
        for component in header.split(separator: ";", omittingEmptySubsequences: false) {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            let name = String(pair[0]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[1]).trimmingCharacters(in: .whitespaces)
            guard isSafeName(name), isSafeValue(value) else { return nil }
            values[name] = value
        }
        return values.isEmpty ? nil : values
    }

    private static func isSafeName(_ value: String) -> Bool {
        !value.isEmpty
            && value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && !value.contains("=")
            && !value.contains(";")
    }

    private static func isSafeValue(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .newlines) == nil && !value.contains(";")
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
    private let sessionLifecycle: (any SIwebSessionLifecycle)?
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
        sessionLifecycle: (any SIwebSessionLifecycle)? = nil,
        transport: (any SIwebHTTPTransport)? = nil,
        sleeper: any SIwebRetrySleeper = SystemSIwebRetrySleeper(),
        jitter: any SIwebRetryJitter = SystemSIwebRetryJitter(),
        maximumAttempts: Int = 3,
        maximumBackoff: TimeInterval = 8,
        maximumBodyBytes: Int = 4 * 1_024 * 1_024
    ) {
        self.configuration = configuration
        self.authorizer = authorizer
        self.sessionLifecycle = sessionLifecycle
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

        do {
            let result = try await request(url)
            let parsed = try parser.parse(result.data)
            try sessionLifecycle?.refresh(from: result.response, requestedURL: url)
            let next: String?
            if let nextURL = parsed.nextPageURL {
                do { next = try configuration.validatedTarget(nextURL).absoluteString }
                catch { throw SIwebConnectorError.structural(.unsafeRoute) }
            } else {
                next = nil
            }
            return FetchPage(values: parsed.meetings, nextPageToken: next, isCompleteSnapshot: next == nil)
        } catch let error as SIwebConnectorError {
            if [.unauthorized, .sessionExpired, .loginRedirect].contains(error.category) {
                try? sessionLifecycle?.invalidate()
            }
            throw error
        }
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
