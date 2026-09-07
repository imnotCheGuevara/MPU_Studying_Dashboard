import Foundation

struct CanvasConfiguration: Equatable, Sendable {
    static let tokenAccount = "canvas.access-token"

    let baseURL: URL
    let tokenAccount: String

    init(baseURL: URL, tokenAccount: String = tokenAccount) throws {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { throw CanvasConfigurationError.invalidBaseURL }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let normalized = components.url else { throw CanvasConfigurationError.invalidBaseURL }
        self.baseURL = normalized
        self.tokenAccount = tokenAccount
    }
}

enum CanvasConfigurationError: Error, Equatable, CustomStringConvertible {
    case invalidBaseURL
    case missingBaseURL
    case emptyToken

    var description: String {
        switch self {
        case .invalidBaseURL: "Canvas URL must be an HTTPS origin without credentials, query, or fragment"
        case .missingBaseURL: "Canvas URL has not been configured"
        case .emptyToken: "Canvas authorization was empty"
        }
    }
}

protocol CanvasConfigurationStore: Sendable {
    func load() throws -> CanvasConfiguration
    func saveBaseURL(_ baseURL: URL) throws
}

final class UserDefaultsCanvasConfigurationStore: CanvasConfigurationStore, @unchecked Sendable {
    private static let baseURLKey = "CanvasBaseURL"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> CanvasConfiguration {
        guard let value = defaults.string(forKey: Self.baseURLKey), let url = URL(string: value) else {
            throw CanvasConfigurationError.missingBaseURL
        }
        return try CanvasConfiguration(baseURL: url)
    }

    func saveBaseURL(_ baseURL: URL) throws {
        let configuration = try CanvasConfiguration(baseURL: baseURL)
        defaults.set(configuration.baseURL.absoluteString, forKey: Self.baseURLKey)
    }
}
