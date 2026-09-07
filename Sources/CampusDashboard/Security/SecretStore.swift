import Foundation
import Security

enum SecretStoreError: Error, Equatable, CustomStringConvertible {
    case denied
    case unavailable
    case notFound
    case invalidData
    case operatingSystemStatus(OSStatus)

    var description: String {
        switch self {
        case .denied: "Keychain access was denied"
        case .unavailable: "Keychain is unavailable for this application identity"
        case .notFound: "Secret was not found"
        case .invalidData: "Keychain returned invalid secret data"
        case .operatingSystemStatus(let status): "Keychain operation failed (status \(status))"
        }
    }
}

protocol SecretStore: Sendable {
    func set(_ secret: Data, account: String) throws
    func data(account: String) throws -> Data
    func remove(account: String) throws
}

struct KeychainClient: @unchecked Sendable {
    var add: ([String: Any]) -> OSStatus
    var update: ([String: Any], [String: Any]) -> OSStatus
    var copyMatching: ([String: Any], UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    var delete: ([String: Any]) -> OSStatus

    static let live = KeychainClient(
        add: { SecItemAdd($0 as CFDictionary, nil) },
        update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        copyMatching: { SecItemCopyMatching($0 as CFDictionary, $1) },
        delete: { SecItemDelete($0 as CFDictionary) }
    )
}

final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String
    private let client: KeychainClient

    init(service: String, client: KeychainClient = .live) {
        self.service = service
        self.client = client
    }

    func set(_ secret: Data, account: String) throws {
        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = secret
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = client.add(attributes)
        if status == errSecDuplicateItem {
            let updateStatus = client.update(
                baseQuery(account: account),
                [kSecValueData as String: secret]
            )
            guard updateStatus == errSecSuccess else { throw map(updateStatus) }
        } else if status != errSecSuccess {
            throw map(status)
        }
    }

    func data(account: String) throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = client.copyMatching(query, &result)
        guard status == errSecSuccess else { throw map(status) }
        guard let data = result as? Data else { throw SecretStoreError.invalidData }
        return data
    }

    func remove(account: String) throws {
        let status = client.delete(baseQuery(account: account))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw map(status) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func map(_ status: OSStatus) -> SecretStoreError {
        switch status {
        case errSecItemNotFound:
            .notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            .denied
        case errSecNotAvailable, errSecMissingEntitlement:
            .unavailable
        default:
            .operatingSystemStatus(status)
        }
    }
}

final class FakeSecretStore: SecretStore, @unchecked Sendable {
    enum Mode: Sendable {
        case available
        case denied
        case unavailable
    }

    var mode: Mode
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    init(mode: Mode = .available) { self.mode = mode }

    func set(_ secret: Data, account: String) throws {
        try checkAvailability()
        lock.withLock { values[account] = secret }
    }

    func data(account: String) throws -> Data {
        try checkAvailability()
        guard let value = lock.withLock({ values[account] }) else { throw SecretStoreError.notFound }
        return value
    }

    func remove(account: String) throws {
        try checkAvailability()
        _ = lock.withLock { values.removeValue(forKey: account) }
    }

    private func checkAvailability() throws {
        switch mode {
        case .available: break
        case .denied: throw SecretStoreError.denied
        case .unavailable: throw SecretStoreError.unavailable
        }
    }
}
