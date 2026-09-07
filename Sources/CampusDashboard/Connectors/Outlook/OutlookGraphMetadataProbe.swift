import Foundation

struct OutlookMetadataProbeResult: Equatable, Sendable { let messageCount: Int }
private struct OutlookMetadataEnvelope: Decodable { let value: [OutlookMetadataRow] }
private struct OutlookMetadataRow: Decodable { let receivedDateTime: String? }
struct OutlookGraphError: Error, Equatable, Sendable { let category: OutlookGraphErrorCategory; let claims: String? }
enum OutlookGraphErrorCategory: String, Equatable, Sendable {
    case unauthorized, forbidden, claimsChallenge, rateLimited, offline, serviceUnavailable, malformedResponse
}

struct OutlookGraphMetadataProbe: Sendable {
    static let endpoint = URL(string: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?$select=receivedDateTime&$top=1")!
    let transport: any OutlookHTTPTransport
    init(transport: any OutlookHTTPTransport = URLSessionOutlookTransport()) { self.transport = transport }
    func run(accessToken: String) async throws -> OutlookMetadataProbeResult {
        var request = URLRequest(url: Self.endpoint); request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let result: OutlookHTTPResult
        do { result = try await transport.send(request) }
        catch let error as URLError where error.code == .notConnectedToInternet {
            throw OutlookGraphError(category: .offline, claims: nil)
        } catch { throw OutlookGraphError(category: .malformedResponse, claims: nil) }
        guard result.response.url == Self.endpoint else { throw OutlookGraphError(category: .malformedResponse, claims: nil) }
        switch result.response.statusCode {
        case 200:
            guard let envelope = try? JSONDecoder().decode(OutlookMetadataEnvelope.self, from: result.data),
                  envelope.value.count <= 1 else { throw OutlookGraphError(category: .malformedResponse, claims: nil) }
            return OutlookMetadataProbeResult(messageCount: envelope.value.count)
        case 401:
            let claims = Self.claimsChallenge(from: result.response.value(forHTTPHeaderField: "WWW-Authenticate") ?? "")
            throw OutlookGraphError(category: claims == nil ? .unauthorized : .claimsChallenge, claims: claims)
        case 403: throw OutlookGraphError(category: .forbidden, claims: nil)
        case 429: throw OutlookGraphError(category: .rateLimited, claims: nil)
        case 500...599: throw OutlookGraphError(category: .serviceUnavailable, claims: nil)
        default: throw OutlookGraphError(category: .malformedResponse, claims: nil)
        }
    }
    static func claimsChallenge(from header: String) -> String? {
        guard let range = header.range(of: "claims=\"") else { return nil }
        let remainder = header[range.upperBound...]
        guard let end = remainder.firstIndex(of: "\"") else { return nil }
        let value = String(remainder[..<end]); return value.isEmpty || value.utf8.count > 8_192 ? nil : value
    }
}
