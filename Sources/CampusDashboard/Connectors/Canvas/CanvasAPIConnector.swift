import Foundation

enum CanvasErrorCategory: String, Sendable {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverUnavailable
    case timedOut
    case offline
    case transport
    case malformedResponse
    case unsafePagination
    case configuration
}

struct CanvasConnectorError: Error, Equatable, Sendable, CustomStringConvertible {
    let category: CanvasErrorCategory
    let retryable: Bool
    let retryAfter: TimeInterval?
    let diagnostic: String

    var description: String { diagnostic }
}

struct CanvasRateLimitSnapshot: Equatable, Sendable {
    let remaining: Double?
    let requestCost: Double?
}

struct CanvasHTTPResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol CanvasHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> CanvasHTTPResult
}

struct URLSessionCanvasTransport: CanvasHTTPTransport {
    let session: URLSession

    init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> CanvasHTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CanvasConnectorError(
                category: .malformedResponse, retryable: false, retryAfter: nil,
                diagnostic: "Canvas returned a non-HTTP response"
            )
        }
        return CanvasHTTPResult(data: data, response: httpResponse)
    }
}

protocol CanvasRetrySleeper: Sendable {
    func sleep(for delay: TimeInterval) async throws
}

protocol CanvasRetryJitter: Sendable {
    func multiplier() -> Double
}

struct SystemCanvasRetryJitter: CanvasRetryJitter {
    func multiplier() -> Double { Double.random(in: 0.5...1.5) }
}

struct SystemCanvasRetrySleeper: CanvasRetrySleeper {
    func sleep(for delay: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(delay))
    }
}

actor CanvasAPIConnector: CanvasService {
    private let configuration: CanvasConfiguration
    private let secretStore: any SecretStore
    private let transport: any CanvasHTTPTransport
    private let sleeper: any CanvasRetrySleeper
    private let jitter: any CanvasRetryJitter
    private let concurrencyGate: CanvasConcurrencyGate
    private let maximumAttempts: Int
    private let maximumBackoff: TimeInterval
    private let decoder: JSONDecoder
    private var latestRateLimit: CanvasRateLimitSnapshot?

    init(
        configuration: CanvasConfiguration,
        secretStore: any SecretStore,
        transport: any CanvasHTTPTransport = URLSessionCanvasTransport(),
        sleeper: any CanvasRetrySleeper = SystemCanvasRetrySleeper(),
        jitter: any CanvasRetryJitter = SystemCanvasRetryJitter(),
        maximumAttempts: Int = 3,
        maximumBackoff: TimeInterval = 8,
        maximumConcurrentRequests: Int = 1
    ) {
        self.configuration = configuration
        self.secretStore = secretStore
        self.transport = transport
        self.sleeper = sleeper
        self.jitter = jitter
        concurrencyGate = CanvasConcurrencyGate(limit: maximumConcurrentRequests)
        self.maximumAttempts = max(1, maximumAttempts)
        self.maximumBackoff = max(0, maximumBackoff)
        decoder = JSONDecoder.canvas
    }

    func rateLimitSnapshot() -> CanvasRateLimitSnapshot? { latestRateLimit }

    func courses(pageToken: String?) async throws -> FetchPage<CanvasCoursePayload> {
        let url = try pageToken.map(validatedNextPageURL) ?? endpoint(
            path: "/api/v1/courses",
            query: [
                URLQueryItem(name: "enrollment_state", value: "active"),
                URLQueryItem(name: "enrollment_type", value: "student"),
                URLQueryItem(name: "state[]", value: "available"),
                URLQueryItem(name: "include[]", value: "term"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        let response = try await request(url)
        let values: [CanvasCourseDTO] = try decode(response.data, context: "courses")
        return FetchPage(
            values: values.map(\.payload),
            nextPageToken: try nextPageToken(response.response),
            isCompleteSnapshot: nextLink(response.response) == nil
        )
    }

    func learningTasks(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasTaskPayload> {
        let url = try pageToken.map(validatedNextPageURL) ?? endpoint(
            path: "/api/v1/courses/\(encodedPathComponent(courseID))/assignments",
            query: [
                URLQueryItem(name: "override_assignment_dates", value: "true"),
                URLQueryItem(name: "order_by", value: "due_at"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        let response = try await request(url)
        let values: [CanvasAssignmentDTO] = try decode(response.data, context: "assignments")
        return FetchPage(
            values: values.map { $0.payload(fallbackCourseID: courseID) },
            nextPageToken: try nextPageToken(response.response),
            isCompleteSnapshot: nextLink(response.response) == nil
        )
    }

    func announcements(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasAnnouncementPayload> {
        let url = try pageToken.map(validatedNextPageURL) ?? endpoint(
            path: "/api/v1/courses/\(encodedPathComponent(courseID))/discussion_topics",
            query: [
                URLQueryItem(name: "only_announcements", value: "true"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        let response = try await request(url)
        let values: [CanvasAnnouncementDTO] = try decode(response.data, context: "announcements")
        return FetchPage(
            values: values.map { $0.payload(fallbackCourseID: courseID) },
            nextPageToken: try nextPageToken(response.response),
            isCompleteSnapshot: nextLink(response.response) == nil
        )
    }

    private func request(_ url: URL) async throws -> CanvasHTTPResult {
        let token: Data
        do {
            token = try secretStore.data(account: configuration.tokenAccount)
        } catch {
            throw CanvasConnectorError(
                category: .configuration, retryable: false, retryAfter: nil,
                diagnostic: "Canvas authorization is unavailable in Keychain"
            )
        }
        guard !token.isEmpty, let tokenText = String(data: token, encoding: .utf8) else {
            throw CanvasConnectorError(
                category: .configuration, retryable: false, retryAfter: nil,
                diagnostic: "Canvas authorization in Keychain is invalid"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(tokenText)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let authorizedRequest = request
        let transport = self.transport

        var attempt = 0
        while true {
            attempt += 1
            do {
                let result = try await concurrencyGate.withPermit {
                    try await transport.send(authorizedRequest)
                }
                latestRateLimit = CanvasRateLimitSnapshot(
                    remaining: result.response.value(forHTTPHeaderField: "X-Rate-Limit-Remaining").flatMap(Double.init),
                    requestCost: result.response.value(forHTTPHeaderField: "X-Request-Cost").flatMap(Double.init)
                )
                if (200..<300).contains(result.response.statusCode) { return result }
                let error = classify(statusCode: result.response.statusCode, response: result.response)
                if error.retryable && attempt < maximumAttempts {
                    try await sleeper.sleep(for: retryDelay(attempt: attempt, error: error))
                    continue
                }
                throw error
            } catch let error as CanvasConnectorError {
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

    private func endpoint(path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)!
        components.path = configuration.baseURL.path + path
        components.queryItems = query
        return components.url!
    }

    private func validatedNextPageURL(_ token: String) throws -> URL {
        guard let url = URL(string: token),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == configuration.baseURL.host?.lowercased(),
              (url.port ?? 443) == (configuration.baseURL.port ?? 443),
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              url.path.hasPrefix(configuration.baseURL.path + "/api/v1/")
        else {
            throw CanvasConnectorError(
                category: .unsafePagination, retryable: false, retryAfter: nil,
                diagnostic: "Canvas returned an unsafe pagination link"
            )
        }
        return url
    }

    private func nextPageToken(_ response: HTTPURLResponse) throws -> String? {
        guard let link = nextLink(response) else { return nil }
        return try validatedNextPageURL(link).absoluteString
    }

    private func nextLink(_ response: HTTPURLResponse) -> String? {
        guard let header = response.value(forHTTPHeaderField: "Link") else { return nil }
        return header.split(separator: ",").lazy.compactMap { segment -> String? in
            let value = String(segment)
            guard value.range(of: #"rel\s*=\s*"next""#, options: .regularExpression) != nil,
                  let start = value.firstIndex(of: "<"), let end = value[start...].firstIndex(of: ">")
            else { return nil }
            return String(value[value.index(after: start)..<end])
        }.first
    }

    private func classify(statusCode: Int, response: HTTPURLResponse) -> CanvasConnectorError {
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        switch statusCode {
        case 401:
            return error(.unauthorized, retryable: false, statusCode: statusCode)
        case 403:
            return error(.forbidden, retryable: false, statusCode: statusCode)
        case 404:
            return error(.notFound, retryable: false, statusCode: statusCode)
        case 429:
            return error(.rateLimited, retryable: true, statusCode: statusCode, retryAfter: retryAfter)
        case 500...599:
            return error(.serverUnavailable, retryable: true, statusCode: statusCode, retryAfter: retryAfter)
        default:
            return error(.malformedResponse, retryable: false, statusCode: statusCode)
        }
    }

    private func classifyTransport(_ underlying: Error) -> CanvasConnectorError {
        let code = (underlying as? URLError)?.code
        switch code {
        case .timedOut:
            return error(.timedOut, retryable: true)
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return error(.offline, retryable: true)
        default:
            return error(.transport, retryable: true)
        }
    }

    private func retryDelay(attempt: Int, error: CanvasConnectorError) -> TimeInterval {
        if let retryAfter = error.retryAfter { return retryAfter }
        let exponential = min(pow(2, Double(attempt - 1)), maximumBackoff)
        let multiplier = min(1.5, max(0.5, jitter.multiplier()))
        return min(maximumBackoff, exponential * multiplier)
    }

    private func error(
        _ category: CanvasErrorCategory,
        retryable: Bool,
        statusCode: Int? = nil,
        retryAfter: TimeInterval? = nil
    ) -> CanvasConnectorError {
        let status = statusCode.map { " (HTTP \($0))" } ?? ""
        return CanvasConnectorError(
            category: category,
            retryable: retryable,
            retryAfter: retryAfter,
            diagnostic: "Canvas request failed: \(category.rawValue)\(status)"
        )
    }

    private func decode<Value: Decodable>(_ data: Data, context: String) throws -> Value {
        do { return try decoder.decode(Value.self, from: data) }
        catch {
            throw CanvasConnectorError(
                category: .malformedResponse, retryable: false, retryAfter: nil,
                diagnostic: "Canvas \(context) response no longer matches the expected format"
            )
        }
    }

    private func encodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)!
    }
}

private extension JSONDecoder {
    static var canvas: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            if let date = fractional.date(from: value) ?? standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid Canvas ISO 8601 date"
            )
        }
        return decoder
    }
}
