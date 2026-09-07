import Foundation

enum MPUSIwebEndpoints {
    static let publishedEntryURL = URL(string: "https://wapps2.mpu.edu.mo/siweb_cas/")!
    static let operationalBaseURL = URL(string: "https://wapps2.ipm.edu.mo/siweb_cas")!
    static let classTimeURL = URL(string: "https://wapps2.ipm.edu.mo/siweb_cas/time_stud.asp")!
    static let operationalHost = "wapps2.ipm.edu.mo"
    static let studentHomeHost = "banner-prod-xe-01.ipm.edu.mo"
}

struct SIwebConfiguration: Equatable, Sendable {
    static let sessionAccount = "siweb.authorized-session"

    let baseURL: URL
    let targetPageURLs: [URL]
    let sessionAccount: String
    let requestTimeout: TimeInterval
    let minimumRequestInterval: TimeInterval
    let maximumConcurrentRequests: Int

    init(
        baseURL: URL,
        targetPageURLs: [URL],
        sessionAccount: String = sessionAccount,
        requestTimeout: TimeInterval = 30,
        minimumRequestInterval: TimeInterval = 1,
        maximumConcurrentRequests: Int = 1
    ) throws {
        let normalizedBase = try Self.normalizedBaseURL(baseURL)
        guard !targetPageURLs.isEmpty else { throw SIwebConfigurationError.missingTargetPages }
        guard requestTimeout > 0, minimumRequestInterval >= 0,
              (1...4).contains(maximumConcurrentRequests)
        else { throw SIwebConfigurationError.invalidLimits }

        var normalizedTargets: [URL] = []
        for target in targetPageURLs {
            guard let normalized = Self.normalizedTarget(target, base: normalizedBase) else {
                throw SIwebConfigurationError.unsafeTargetPage
            }
            if !normalizedTargets.contains(normalized) { normalizedTargets.append(normalized) }
        }
        self.baseURL = normalizedBase
        self.targetPageURLs = normalizedTargets
        self.sessionAccount = sessionAccount
        self.requestTimeout = requestTimeout
        self.minimumRequestInterval = minimumRequestInterval
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    func validatedTarget(_ url: URL) throws -> URL {
        guard let normalized = Self.normalizedTarget(url, base: baseURL),
              targetPageURLs.contains(normalized)
        else { throw SIwebConfigurationError.unsafeTargetPage }
        return normalized
    }

    private static func normalizedBaseURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil
        else { throw SIwebConfigurationError.invalidBaseURL }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let result = components.url else { throw SIwebConfigurationError.invalidBaseURL }
        return result
    }

    private static func normalizedTarget(_ url: URL, base: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == base.host?.lowercased(),
              (components.port ?? 443) == (base.port ?? 443),
              components.user == nil, components.password == nil, components.fragment == nil,
              components.path == base.path || components.path.hasPrefix(base.path + "/")
        else { return nil }
        let secretNames = ["token", "session", "auth", "authorization", "key", "secret", "code"]
        guard components.queryItems?.allSatisfy({ item in
            !secretNames.contains { item.name.lowercased().contains($0) }
        }) != false else { return nil }
        components.scheme = "https"
        components.host = components.host?.lowercased()
        return components.url
    }
}

protocol SIwebConfigurationStore: Sendable {
    func load() throws -> SIwebConfiguration
    func save(_ configuration: SIwebConfiguration) throws
}

final class UserDefaultsSIwebConfigurationStore: SIwebConfigurationStore, @unchecked Sendable {
    private static let baseURLKey = "SIwebBaseURL"
    private static let targetURLsKey = "SIwebTargetPageURLs"
    private static let intervalKey = "SIwebMinimumRequestInterval"
    private static let concurrencyKey = "SIwebMaximumConcurrentRequests"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> SIwebConfiguration {
        guard let base = defaults.string(forKey: Self.baseURLKey).flatMap(URL.init(string:)),
              let values = defaults.stringArray(forKey: Self.targetURLsKey), !values.isEmpty
        else { throw SIwebConfigurationError.missingTargetPages }
        let targets = values.compactMap(URL.init(string:))
        guard targets.count == values.count else { throw SIwebConfigurationError.unsafeTargetPage }
        let interval = defaults.object(forKey: Self.intervalKey) == nil
            ? 1 : defaults.double(forKey: Self.intervalKey)
        let concurrency = defaults.object(forKey: Self.concurrencyKey) == nil
            ? 1 : defaults.integer(forKey: Self.concurrencyKey)
        return try SIwebConfiguration(
            baseURL: base, targetPageURLs: targets, minimumRequestInterval: interval,
            maximumConcurrentRequests: concurrency
        )
    }

    func save(_ configuration: SIwebConfiguration) throws {
        defaults.set(configuration.baseURL.absoluteString, forKey: Self.baseURLKey)
        defaults.set(configuration.targetPageURLs.map(\.absoluteString), forKey: Self.targetURLsKey)
        defaults.set(configuration.minimumRequestInterval, forKey: Self.intervalKey)
        defaults.set(configuration.maximumConcurrentRequests, forKey: Self.concurrencyKey)
    }
}

enum SIwebConfigurationError: Error, Equatable, CustomStringConvertible {
    case invalidBaseURL
    case missingTargetPages
    case unsafeTargetPage
    case invalidLimits

    var description: String {
        switch self {
        case .invalidBaseURL: "SIweb base URL must be a credential-free HTTPS URL"
        case .missingTargetPages: "At least one explicitly approved SIweb target page is required"
        case .unsafeTargetPage: "SIweb target must be an explicitly approved same-origin HTTPS page"
        case .invalidLimits: "SIweb timeout, interval, or concurrency limit is invalid"
        }
    }
}
