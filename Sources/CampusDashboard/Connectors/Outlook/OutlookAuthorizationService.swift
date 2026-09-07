import Foundation

protocol OutlookConfigurationStoring: Sendable {
    func load() -> OutlookTenantConfiguration?
    func save(_ configuration: OutlookTenantConfiguration) throws
    func clear()
}

final class UserDefaultsOutlookConfigurationStore: OutlookConfigurationStoring, @unchecked Sendable {
    private let defaults: UserDefaults; private let key = "outlook-tenant-configuration-v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> OutlookTenantConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OutlookTenantConfiguration.self, from: data)
    }
    func save(_ configuration: OutlookTenantConfiguration) throws {
        defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }
    func clear() { defaults.removeObject(forKey: key) }
}

final class InMemoryOutlookConfigurationStore: OutlookConfigurationStoring, @unchecked Sendable {
    private let lock = NSLock(); private var value: OutlookTenantConfiguration?
    init(_ value: OutlookTenantConfiguration? = nil) { self.value = value }
    func load() -> OutlookTenantConfiguration? { lock.withLock { value } }
    func save(_ configuration: OutlookTenantConfiguration) { lock.withLock { value = configuration } }
    func clear() { lock.withLock { value = nil } }
}

protocol OutlookTokenCaching: Sendable {
    func load() throws -> OutlookTokenRecord?
    func save(_ record: OutlookTokenRecord) throws
    func clear() throws
}

final class KeychainOutlookTokenCache: OutlookTokenCaching, @unchecked Sendable {
    static let service = "com.campusdashboard.desktop.outlook"
    static let account = "delegated-token-cache-v1"
    private let secrets: any SecretStore
    init(secrets: any SecretStore) { self.secrets = secrets }
    func load() throws -> OutlookTokenRecord? {
        do { return try JSONDecoder().decode(OutlookTokenRecord.self, from: secrets.data(account: Self.account)) }
        catch SecretStoreError.notFound { return nil }
        catch is SecretStoreError { throw OutlookAuthorizationError.keychainUnavailable }
        catch { throw OutlookAuthorizationError.malformedResponse }
    }
    func save(_ record: OutlookTokenRecord) throws {
        do { try secrets.set(try JSONEncoder().encode(record), account: Self.account) }
        catch { throw OutlookAuthorizationError.keychainUnavailable }
    }
    func clear() throws {
        do { try secrets.remove(account: Self.account) }
        catch { throw OutlookAuthorizationError.keychainUnavailable }
    }
}

struct OutlookHTTPResult: Sendable { let data: Data; let response: HTTPURLResponse }
protocol OutlookHTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> OutlookHTTPResult }

final class OutlookNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class URLSessionOutlookTransport: OutlookHTTPTransport, @unchecked Sendable {
    private let session: URLSession
    init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout; configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: OutlookNoRedirectDelegate(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> OutlookHTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OutlookAuthorizationError.malformedResponse }
        return OutlookHTTPResult(data: data, response: response)
    }
}

private struct OutlookTokenResponse: Decodable {
    let accessToken: String, refreshToken: String?, expiresIn: Int, scope: String, idToken: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
        case scope; case idToken = "id_token"
    }
}
private struct OutlookOAuthErrorResponse: Decodable {
    let error: String?; let errorCodes: [Int]?
    enum CodingKeys: String, CodingKey { case error; case errorCodes = "error_codes" }
}

actor OutlookAuthorizationService {
    private struct Pending: Sendable {
        let configuration: OutlookTenantConfiguration, transaction: OutlookPKCETransaction
        var consumed: Bool
    }
    private let configurations: any OutlookConfigurationStoring
    private let tokens: any OutlookTokenCaching
    private let transport: any OutlookHTTPTransport
    private let now: @Sendable () -> Date
    private let randomBytes: @Sendable (Int) throws -> Data
    private var pending: Pending?; private var pendingClaimsChallenge: String?
    private(set) var status: OutlookAuthorizationStatus = .disconnected

    init(configurations: any OutlookConfigurationStoring, tokens: any OutlookTokenCaching,
         transport: any OutlookHTTPTransport = URLSessionOutlookTransport(),
         now: @escaping @Sendable () -> Date = { Date() },
         randomBytes: @escaping @Sendable (Int) throws -> Data = { try SecureRandom.bytes($0) }) {
        self.configurations = configurations; self.tokens = tokens; self.transport = transport
        self.now = now; self.randomBytes = randomBytes
    }

    func currentConfiguration() -> OutlookTenantConfiguration? { configurations.load() }
    func configure(clientID: String, tenantID: String) throws {
        let value = try OutlookTenantConfiguration(clientID: clientID, tenantID: tenantID)
        if let previous = configurations.load(), previous != value { try tokens.clear() }
        try configurations.save(value); pending = nil
        status = (try? tokens.load()) == nil ? .disconnected : .expired
    }
    func restoreStatus() {
        guard let configuration = configurations.load() else { status = .disconnected; return }
        do {
            guard let token = try tokens.load() else { status = .disconnected; return }
            guard token.clientID == configuration.clientID, token.tenantID == configuration.tenantID,
                  token.issuer == configuration.issuer else { status = .expired; return }
            status = token.expiresAt > now() ? .connected : .expired
        } catch { status = .expired }
    }

    func beginAuthorization(claims: String? = nil) throws -> URL {
        guard let configuration = configurations.load() else { throw OutlookAuthorizationError.configurationMissing }
        let transaction = try OutlookPKCETransaction(randomBytes: randomBytes)
        let effectiveClaims = claims ?? pendingClaimsChallenge; pendingClaimsChallenge = nil
        pending = Pending(configuration: configuration, transaction: transaction, consumed: false)
        status = .authorizing
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: configuration.clientID), URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: OutlookTenantConfiguration.redirectURI.absoluteString),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: OutlookScopePolicy.requested.joined(separator: " ")),
            URLQueryItem(name: "state", value: transaction.state), URLQueryItem(name: "nonce", value: transaction.nonce),
            URLQueryItem(name: "code_challenge", value: transaction.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "prompt", value: "select_account")
        ]
        if let effectiveClaims, !effectiveClaims.isEmpty { items.append(URLQueryItem(name: "claims", value: effectiveClaims)) }
        components.queryItems = items; return components.url!
    }
    func cancelAuthorization() { pending = nil; status = .disconnected }

    func handleCallback(_ callback: URL) async throws {
        guard var current = pending else { throw OutlookAuthorizationError.invalidRedirect }
        guard !current.consumed else { throw OutlookAuthorizationError.authorizationCodeAlreadyUsed }
        guard callback.scheme == OutlookTenantConfiguration.redirectURI.scheme,
              callback.host == OutlookTenantConfiguration.redirectURI.host,
              callback.path == OutlookTenantConfiguration.redirectURI.path, callback.fragment == nil,
              callback.user == nil, callback.password == nil, callback.port == nil,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        else { throw OutlookAuthorizationError.invalidRedirect }
        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard parameters[item.name] == nil else { throw OutlookAuthorizationError.invalidRedirect }
            parameters[item.name] = item.value ?? ""
        }
        guard parameters["state"] == current.transaction.state else {
            pending = nil; status = .disconnected; throw OutlookAuthorizationError.stateMismatch
        }
        if let error = parameters["error"] {
            pending = nil
            let mapped = mapOAuthError(error: error, codes: sanitizedErrorCodes(from: parameters["error_description"] ?? ""))
            status = status(for: mapped); throw mapped
        }
        guard let code = parameters["code"], !code.isEmpty else {
            pending = nil; status = .disconnected; throw OutlookAuthorizationError.malformedResponse
        }
        current.consumed = true; pending = current
        do {
            let record = try await redeem(code: code, pending: current); try tokens.save(record)
            pending = nil; status = .connected
        } catch {
            pending = nil; let mapped = mapTransportError(error); status = status(for: mapped); throw mapped
        }
    }

    func validAccessToken() async throws -> String {
        guard let configuration = configurations.load(), var record = try tokens.load() else {
            status = .disconnected; throw OutlookAuthorizationError.configurationMissing
        }
        guard record.clientID == configuration.clientID, record.tenantID == configuration.tenantID,
              record.issuer == configuration.issuer else { status = .expired; throw OutlookAuthorizationError.tenantMismatch }
        if record.expiresAt <= now().addingTimeInterval(60) {
            do { record = try await refresh(record, configuration: configuration); try tokens.save(record) }
            catch { let mapped = mapTransportError(error); status = status(for: mapped); throw mapped }
        }
        status = .connected; return record.accessToken
    }
    func disconnect() throws -> URL? {
        try tokens.clear(); pending = nil; status = .disconnected
        guard let configuration = configurations.load() else { return nil }
        return configuration.logoutEndpoint
    }
    func markRevokedOrClaimsChallenge(claims: String?) {
        status = .expired; pending = nil; pendingClaimsChallenge = claims; _ = try? tokens.clear()
    }

    private func redeem(code: String, pending: Pending) async throws -> OutlookTokenRecord {
        let response = try await tokenRequest(endpoint: pending.configuration.tokenEndpoint, fields: [
            "client_id": pending.configuration.clientID, "scope": OutlookScopePolicy.requested.joined(separator: " "),
            "code": code, "redirect_uri": OutlookTenantConfiguration.redirectURI.absoluteString,
            "grant_type": "authorization_code", "code_verifier": pending.transaction.verifier
        ])
        guard let idToken = response.idToken, let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw OutlookAuthorizationError.malformedResponse
        }
        try OutlookIDTokenValidator.validate(idToken, configuration: pending.configuration,
                                             nonce: pending.transaction.nonce, now: now())
        return OutlookTokenRecord(accessToken: response.accessToken, refreshToken: refreshToken,
            scopes: try OutlookScopePolicy.validate(response.scope.split(separator: " ").map(String.init)),
            expiresAt: now().addingTimeInterval(TimeInterval(max(1, response.expiresIn))),
            tenantID: pending.configuration.tenantID, issuer: pending.configuration.issuer,
            clientID: pending.configuration.clientID)
    }
    private func refresh(_ record: OutlookTokenRecord, configuration: OutlookTenantConfiguration) async throws -> OutlookTokenRecord {
        let response = try await tokenRequest(endpoint: configuration.tokenEndpoint, fields: [
            "client_id": configuration.clientID, "scope": OutlookScopePolicy.requested.joined(separator: " "),
            "refresh_token": record.refreshToken, "grant_type": "refresh_token"
        ])
        return OutlookTokenRecord(accessToken: response.accessToken, refreshToken: response.refreshToken ?? record.refreshToken,
            scopes: try OutlookScopePolicy.validate(response.scope.split(separator: " ").map(String.init)),
            expiresAt: now().addingTimeInterval(TimeInterval(max(1, response.expiresIn))),
            tenantID: configuration.tenantID, issuer: configuration.issuer, clientID: configuration.clientID)
    }
    private func tokenRequest(endpoint: URL, fields: [String: String]) async throws -> OutlookTokenResponse {
        guard endpoint.scheme == "https", endpoint.host == "login.microsoftonline.com", endpoint.user == nil,
              endpoint.password == nil, endpoint.port == nil else { throw OutlookAuthorizationError.invalidConfiguration }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = fields.sorted { $0.key < $1.key }.map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&").data(using: .utf8)
        let result: OutlookHTTPResult
        do { result = try await transport.send(request) }
        catch let error as URLError where error.code == .notConnectedToInternet { throw OutlookAuthorizationError.offline }
        catch is CancellationError { throw CancellationError() }
        catch { throw OutlookAuthorizationError.malformedResponse }
        guard result.response.url == endpoint else { throw OutlookAuthorizationError.invalidRedirect }
        guard result.response.statusCode == 200 else {
            let response = try? JSONDecoder().decode(OutlookOAuthErrorResponse.self, from: result.data)
            throw mapOAuthError(error: response?.error ?? "", codes: response?.errorCodes ?? [])
        }
        guard let decoded = try? JSONDecoder().decode(OutlookTokenResponse.self, from: result.data),
              !decoded.accessToken.isEmpty, decoded.expiresIn > 0 else { throw OutlookAuthorizationError.malformedResponse }
        return decoded
    }
    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
    private func mapOAuthError(error: String, codes: [Int]) -> OutlookAuthorizationError {
        if codes.contains(90094) { return .adminApprovalRequired }
        if codes.contains(50105) || codes.contains(53003) { return .policyBlocked }
        if codes.contains(65001) { return .interactionRequired }; if codes.contains(65004) { return .authorizationCancelled }
        switch error.lowercased() {
        case "access_denied": return .authorizationCancelled
        case "interaction_required", "login_required", "consent_required", "invalid_grant": return .interactionRequired
        case "unauthorized_client": return .policyBlocked
        default: return .malformedResponse
        }
    }
    private func sanitizedErrorCodes(from description: String) -> [Int] {
        guard description.utf8.count <= 8_192 else { return [] }
        return description.matches(of: /AADSTS([0-9]{5,6})/).compactMap { Int($0.1) }
    }
    private func mapTransportError(_ error: any Error) -> OutlookAuthorizationError {
        if let value = error as? OutlookAuthorizationError { return value }
        if error is CancellationError { return .authorizationCancelled }
        return .malformedResponse
    }
    private func status(for error: OutlookAuthorizationError) -> OutlookAuthorizationStatus {
        switch error {
        case .adminApprovalRequired: .adminApprovalRequired
        case .policyBlocked: .policyBlocked
        case .interactionRequired, .tokenExpired: .expired
        default: .disconnected
        }
    }
}
