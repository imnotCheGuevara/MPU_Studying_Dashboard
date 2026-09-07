import CryptoKit
import Foundation

enum OutlookAuthorizationStatus: String, CaseIterable, Equatable, Sendable {
    case disconnected, authorizing, connected, expired, adminApprovalRequired, policyBlocked
}

enum OutlookAuthorizationError: Error, Equatable, Sendable, CustomStringConvertible {
    case configurationMissing, invalidConfiguration, invalidRedirect, stateMismatch
    case authorizationCancelled, authorizationCodeAlreadyUsed, adminApprovalRequired, policyBlocked
    case tenantMismatch, issuerMismatch, nonceMismatch, audienceMismatch, tokenExpired
    case excessiveScope, malformedResponse, offline, interactionRequired, keychainUnavailable
    var description: String { "Outlook authorization failed safely." }
}

struct OutlookTenantConfiguration: Codable, Equatable, Sendable {
    static let redirectURI = URL(string: "msauth.com.campusdashboard.desktop://auth")!
    let clientID: String
    let tenantID: String

    init(clientID: String, tenantID: String) throws {
        let client = clientID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tenant = tenantID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: client) != nil, UUID(uuidString: tenant) != nil else {
            throw OutlookAuthorizationError.invalidConfiguration
        }
        self.clientID = client; self.tenantID = tenant
    }
    var issuer: String { "https://login.microsoftonline.com/\(tenantID)/v2.0" }
    var authorizationEndpoint: URL { URL(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/authorize")! }
    var tokenEndpoint: URL { URL(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/token")! }
    var logoutEndpoint: URL { URL(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/logout")! }
}

enum OutlookScopePolicy {
    static let mailReadBasic = "https://graph.microsoft.com/Mail.ReadBasic"
    static let requested = ["openid", "offline_access", mailReadBasic]
    private static let allowed = Set(["openid", "offline_access", "mail.readbasic"])
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "https://graph.microsoft.com/", with: "")
    }
    static func validate(_ values: [String]) throws -> Set<String> {
        let normalized = Set(values.filter { !$0.isEmpty }.map(normalized))
        guard normalized.contains("mail.readbasic"), normalized.isSubset(of: allowed) else {
            throw OutlookAuthorizationError.excessiveScope
        }
        return normalized
    }
}

struct OutlookPKCETransaction: Equatable, Sendable {
    let state: String, nonce: String, verifier: String, challenge: String
    init(randomBytes: (Int) throws -> Data = { try SecureRandom.bytes($0) }) throws {
        state = Self.base64URL(try randomBytes(32)); nonce = Self.base64URL(try randomBytes(32))
        verifier = Self.base64URL(try randomBytes(64))
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        guard state.count >= 43, nonce.count >= 43, (43...128).contains(verifier.count) else {
            throw OutlookAuthorizationError.malformedResponse
        }
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum SecureRandom {
    static func bytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw OutlookAuthorizationError.keychainUnavailable }
        return data
    }
}

struct OutlookTokenRecord: Codable, Equatable, Sendable {
    let accessToken: String, refreshToken: String
    let scopes: Set<String>
    let expiresAt: Date
    let tenantID: String, issuer: String, clientID: String
}

private struct OutlookIDTokenClaims: Decodable {
    let iss: String, aud: String, tid: String, nonce: String
    let exp: Int, nbf: Int?
}

enum OutlookIDTokenValidator {
    static func validate(_ token: String, configuration: OutlookTenantConfiguration,
                         nonce: String, now: Date) throws {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let payload = decodeBase64URL(String(parts[1])),
              let claims = try? JSONDecoder().decode(OutlookIDTokenClaims.self, from: payload)
        else { throw OutlookAuthorizationError.malformedResponse }
        guard claims.iss == configuration.issuer else { throw OutlookAuthorizationError.issuerMismatch }
        guard claims.tid.lowercased() == configuration.tenantID else { throw OutlookAuthorizationError.tenantMismatch }
        guard claims.aud.lowercased() == configuration.clientID else { throw OutlookAuthorizationError.audienceMismatch }
        guard claims.nonce == nonce else { throw OutlookAuthorizationError.nonceMismatch }
        let timestamp = Int(now.timeIntervalSince1970)
        guard claims.exp > timestamp, (claims.nbf ?? timestamp) <= timestamp + 60 else {
            throw OutlookAuthorizationError.tokenExpired
        }
    }
    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
