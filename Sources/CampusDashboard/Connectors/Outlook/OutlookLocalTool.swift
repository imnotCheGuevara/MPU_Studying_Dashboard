import Foundation

enum OutlookLocalTool {
    static func metadataSmokeTest(resultPath: String) async -> Int32 {
        let service = OutlookAuthorizationService(
            configurations: UserDefaultsOutlookConfigurationStore(),
            tokens: KeychainOutlookTokenCache(secrets: KeychainSecretStore(service: KeychainOutlookTokenCache.service))
        )
        let result: String; let code: Int32
        do {
            let token = try await service.validAccessToken()
            let aggregate = try await OutlookGraphMetadataProbe().run(accessToken: token)
            result = "PASS metadata_items=\(aggregate.messageCount) delegated_scope=Mail.ReadBasic"; code = 0
        } catch let error as OutlookAuthorizationError {
            result = "BLOCKED category=\(safeCategory(error))"; code = 2
        } catch let error as OutlookGraphError {
            result = "BLOCKED category=\(error.category.rawValue)"; code = 2
        } catch { result = "BLOCKED category=unavailable"; code = 2 }
        do { try Data((result + "\n").utf8).write(to: URL(fileURLWithPath: resultPath), options: .atomic); return code }
        catch { return 3 }
    }
    private static func safeCategory(_ error: OutlookAuthorizationError) -> String {
        switch error {
        case .configurationMissing, .invalidConfiguration: "configuration_missing"
        case .adminApprovalRequired: "admin_approval_required"
        case .policyBlocked: "policy_blocked"
        case .offline: "offline"
        case .keychainUnavailable: "keychain_unavailable"
        case .interactionRequired, .tokenExpired: "reauthorization_required"
        default: "authorization_failed"
        }
    }
}
