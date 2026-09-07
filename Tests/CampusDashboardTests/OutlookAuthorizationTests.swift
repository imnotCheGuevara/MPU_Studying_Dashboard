import Foundation
import Testing
@testable import CampusDashboard

@Suite("Outlook delegated authorization boundary")
struct OutlookAuthorizationTests {
    let client = "11111111-1111-4111-8111-111111111111"
    let tenant = "22222222-2222-4222-8222-222222222222"
    let instant = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func configurationAndMinimumScopes() throws {
        let c = try OutlookTenantConfiguration(clientID: client, tenantID: tenant)
        #expect(c.authorizationEndpoint.host == "login.microsoftonline.com")
        #expect(c.issuer.contains(tenant)); #expect(OutlookTenantConfiguration.redirectURI.absoluteString == "msauth.com.campusdashboard.desktop://auth")
        #expect(throws: OutlookAuthorizationError.self) { _ = try OutlookTenantConfiguration(clientID: "common", tenantID: "organizations") }
        #expect(try OutlookScopePolicy.validate(OutlookScopePolicy.requested) == ["openid", "offline_access", "mail.readbasic"])
    }

    @Test(arguments: ["Mail.Read", "Mail.ReadWrite", "Mail.Send", "Mail.ReadBasic.All", "Mail.ReadBasic.Shared"])
    func forbiddenScope(_ scope: String) {
        #expect(throws: OutlookAuthorizationError.self) { _ = try OutlookScopePolicy.validate(["Mail.ReadBasic", scope]) }
    }

    @Test func pkceStateAndBrowserRequest() async throws {
        let setup = try make(); let url = try await setup.service.beginAuthorization(); let q = query(url)
        #expect(q["code_challenge_method"] == "S256"); #expect(q["state"]?.count == 43)
        #expect(q["nonce"]?.count == 43); #expect(q["code_challenge"]?.count == 43)
        #expect(q["redirect_uri"] == OutlookTenantConfiguration.redirectURI.absoluteString)
        #expect(Set(q["scope"]!.split(separator: " ").map(String.init)) == Set(OutlookScopePolicy.requested))
    }

    @Test func successOneTimeAndKeychain() async throws {
        let s = try make(); let auth = try await s.service.beginAuthorization(); let q = query(auth)
        let endpoint = try #require((await s.service.currentConfiguration())?.tokenEndpoint)
        await s.transport.enqueue(.success(http(endpoint, 200, token(nonce: q["nonce"]!))))
        let callback = callback(state: q["state"]!); try await s.service.handleCallback(callback)
        #expect(await s.service.status == .connected); #expect(try s.cache.load()?.accessToken == "access-value")
        let body = String(decoding: try #require((await s.transport.requests.first)?.httpBody), as: UTF8.self)
        #expect(body.contains("code_verifier=")); #expect(!body.lowercased().contains("secret"))
        await #expect(throws: OutlookAuthorizationError.self) { try await s.service.handleCallback(callback) }
        #expect(await s.transport.requests.count == 1)
    }

    @Test func redirectAndStateFailures() async throws {
        for url in [URL(string: "bad://auth?state=x&code=y")!, URL(string: "msauth.com.campusdashboard.desktop://wrong?state=x&code=y")!, URL(string: "msauth.com.campusdashboard.desktop://auth?state=x&state=x&code=y")!] {
            let s = try make(); _ = try await s.service.beginAuthorization()
            await #expect(throws: OutlookAuthorizationError.self) { try await s.service.handleCallback(url) }
            #expect(await s.transport.requests.isEmpty)
        }
        let s = try make(); _ = try await s.service.beginAuthorization()
        await #expect(throws: OutlookAuthorizationError.self) { try await s.service.handleCallback(callback(state: "wrong")) }
    }

    @Test func issuerTenantAudienceNonceExpiryAndScope() async throws {
        let changes: [(String?, String?, String?, String?, Int?, String?)] = [
            ("https://issuer.invalid/v2.0", nil, nil, nil, nil, nil), (nil, "33333333-3333-4333-8333-333333333333", nil, nil, nil, nil),
            (nil, nil, "44444444-4444-4444-8444-444444444444", nil, nil, nil), (nil, nil, nil, "wrong", nil, nil),
            (nil, nil, nil, nil, Int(instant.timeIntervalSince1970 - 1), nil), (nil, nil, nil, nil, nil, "openid offline_access Mail.ReadBasic Mail.Send")
        ]
        for change in changes {
            let s = try make(); let auth = try await s.service.beginAuthorization(); let q = query(auth)
            let issuer = change.0 ?? "https://login.microsoftonline.com/\(tenant)/v2.0"
            let id = idToken(issuer: issuer, tenant: change.1 ?? tenant, audience: change.2 ?? client,
                             nonce: change.3 ?? q["nonce"]!, expiry: change.4 ?? Int(instant.timeIntervalSince1970 + 600))
            let endpoint = try #require((await s.service.currentConfiguration())?.tokenEndpoint)
            await s.transport.enqueue(.success(http(endpoint, 200, token(nonce: q["nonce"]!, scope: change.5 ?? "openid offline_access Mail.ReadBasic", id: id))))
            await #expect(throws: OutlookAuthorizationError.self) { try await s.service.handleCallback(callback(state: q["state"]!)) }
            #expect(try s.cache.load() == nil)
        }
    }

    @Test func refreshExpiryAndRevocation() async throws {
        let s = try make(); let config = try #require(await s.service.currentConfiguration())
        try s.cache.save(record(config, expiry: instant, access: "old", refresh: "old-refresh"))
        await s.transport.enqueue(.success(http(config.tokenEndpoint, 200, token(nonce: "unused", id: nil, access: "new", refresh: "new-refresh"))))
        #expect(try await s.service.validAccessToken() == "new"); #expect(try s.cache.load()?.refreshToken == "new-refresh")
        try s.cache.save(record(config, expiry: instant, access: "expired", refresh: "revoked"))
        await s.transport.enqueue(.success(http(config.tokenEndpoint, 400, errorData("invalid_grant", []))))
        await #expect(throws: OutlookAuthorizationError.self) { _ = try await s.service.validAccessToken() }
        #expect(await s.service.status == .expired)
    }

    @Test func cancellationOfflineAdminPolicyAndKeychain() async throws {
        let cancel = try make(); _ = try await cancel.service.beginAuthorization(); await cancel.service.cancelAuthorization()
        #expect(await cancel.service.status == .disconnected)
        let offline = try make(); let auth = try await offline.service.beginAuthorization(); await offline.transport.enqueue(.failure(URLError(.notConnectedToInternet)))
        await #expect(throws: OutlookAuthorizationError.self) { try await offline.service.handleCallback(callback(state: query(auth)["state"]!)) }
        for (codes, expected) in [([90094], OutlookAuthorizationStatus.adminApprovalRequired), ([53003], OutlookAuthorizationStatus.policyBlocked)] {
            let s = try make(); let url = try await s.service.beginAuthorization(); let endpoint = try #require((await s.service.currentConfiguration())?.tokenEndpoint)
            await s.transport.enqueue(.success(http(endpoint, 400, errorData("access_denied", codes))))
            await #expect(throws: OutlookAuthorizationError.self) { try await s.service.handleCallback(callback(state: query(url)["state"]!)) }
            #expect(await s.service.status == expected)
        }
        let denied = KeychainOutlookTokenCache(secrets: FakeSecretStore(mode: .denied))
        #expect(throws: OutlookAuthorizationError.self) { _ = try denied.load() }
    }

    @Test func claimsChallengePassthrough() async throws {
        let s = try make(); await s.service.markRevokedOrClaimsChallenge(claims: "synthetic-claim")
        #expect(query(try await s.service.beginAuthorization())["claims"] == "synthetic-claim")
        await s.service.cancelAuthorization(); #expect(query(try await s.service.beginAuthorization())["claims"] == nil)
    }

    @Test func metadataOnlyGraphReadAndClaims() async throws {
        let t = ScriptedOutlookTransport(); await t.enqueue(.success(http(OutlookGraphMetadataProbe.endpoint, 200, Data("{\"value\":[{\"receivedDateTime\":\"2033-05-18T03:33:20Z\"}]}".utf8))))
        #expect(try await OutlookGraphMetadataProbe(transport: t).run(accessToken: "ephemeral").messageCount == 1)
        let request = try #require(await t.requests.first); #expect(request.httpMethod == "GET"); #expect(request.httpBody == nil)
        #expect(request.url?.absoluteString.contains("select=receivedDateTime") == true); #expect(request.url?.absoluteString.contains("top=1") == true)
        let challenge = ScriptedOutlookTransport(); await challenge.enqueue(.success(OutlookHTTPResult(data: Data(), response: HTTPURLResponse(url: OutlookGraphMetadataProbe.endpoint, statusCode: 401, httpVersion: nil, headerFields: ["WWW-Authenticate": "Bearer claims=\"synthetic-claim\""])!)))
        await #expect(throws: OutlookGraphError.self) { _ = try await OutlookGraphMetadataProbe(transport: challenge).run(accessToken: "ephemeral") }
    }

    @Test(arguments: OutlookAuthorizationStatus.allCases)
    @MainActor func bilingualSettingsStates(_ status: OutlookAuthorizationStatus) {
        let model = DashboardModel(scenario: .populated, snapshot: SyntheticFixtures.populated, outlookPreviewStatus: status)
        #expect(model.outlookStatus == status); #expect(Localizer.text(model.outlookMessage, language: .simplifiedChinese) != model.outlookMessage)
        #expect(Localizer.text(status.rawValue, language: .simplifiedChinese) != status.rawValue)
    }

    @Test @MainActor func sourceIsolation() async {
        let original = SyntheticFixtures.populated; let model = DashboardModel(snapshot: original, outlookAuthorization: nil)
        await model.refreshOutlookAuthorization(); #expect(model.snapshot.courses == original.courses); #expect(model.snapshot.tasks == original.tasks)
        #expect(model.outlookMessage.contains("Canvas and SIweb remain available"))
    }

    private func make() throws -> (service: OutlookAuthorizationService, transport: ScriptedOutlookTransport, cache: KeychainOutlookTokenCache) {
        let config = try OutlookTenantConfiguration(clientID: client, tenantID: tenant); let transport = ScriptedOutlookTransport()
        let cache = KeychainOutlookTokenCache(secrets: FakeSecretStore())
        return (OutlookAuthorizationService(configurations: InMemoryOutlookConfigurationStore(config), tokens: cache,
                 transport: transport, now: { instant }, randomBytes: { Data((0..<$0).map { UInt8(($0 % 251) + 1) }) }), transport, cache)
    }
    private func query(_ url: URL) -> [String: String] { Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") }) }
    private func callback(state: String) -> URL { var c = URLComponents(url: OutlookTenantConfiguration.redirectURI, resolvingAgainstBaseURL: false)!; c.queryItems = [.init(name: "state", value: state), .init(name: "code", value: "one-time")]; return c.url! }
    private func token(nonce: String, scope: String = "openid offline_access Mail.ReadBasic", id: String? = "default", access: String = "access-value", refresh: String = "refresh-value") -> Data {
        var o: [String: Any] = ["access_token": access, "refresh_token": refresh, "expires_in": 3600, "scope": scope]
        if let id { o["id_token"] = id == "default" ? idToken(issuer: "https://login.microsoftonline.com/\(tenant)/v2.0", tenant: tenant, audience: client, nonce: nonce, expiry: Int(instant.timeIntervalSince1970 + 600)) : id }
        return try! JSONSerialization.data(withJSONObject: o)
    }
    private func idToken(issuer: String, tenant: String, audience: String, nonce: String, expiry: Int) -> String {
        let h = OutlookPKCETransaction.base64URL(Data("{}".utf8)); let o: [String: Any] = ["iss": issuer, "tid": tenant, "aud": audience, "nonce": nonce, "exp": expiry, "nbf": Int(instant.timeIntervalSince1970 - 10)]
        return "\(h).\(OutlookPKCETransaction.base64URL(try! JSONSerialization.data(withJSONObject: o))).sig"
    }
    private func http(_ url: URL, _ code: Int, _ data: Data) -> OutlookHTTPResult { OutlookHTTPResult(data: data, response: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!) }
    private func errorData(_ error: String, _ codes: [Int]) -> Data { try! JSONSerialization.data(withJSONObject: ["error": error, "error_codes": codes]) }
    private func record(_ c: OutlookTenantConfiguration, expiry: Date, access: String, refresh: String) -> OutlookTokenRecord { OutlookTokenRecord(accessToken: access, refreshToken: refresh, scopes: ["mail.readbasic"], expiresAt: expiry, tenantID: tenant, issuer: c.issuer, clientID: client) }
}

private actor ScriptedOutlookTransport: OutlookHTTPTransport {
    private var results: [Result<OutlookHTTPResult, any Error>] = []; private(set) var requests: [URLRequest] = []
    func enqueue(_ result: Result<OutlookHTTPResult, any Error>) { results.append(result) }
    func send(_ request: URLRequest) async throws -> OutlookHTTPResult { requests.append(request); guard !results.isEmpty else { throw URLError(.badServerResponse) }; return try results.removeFirst().get() }
}
