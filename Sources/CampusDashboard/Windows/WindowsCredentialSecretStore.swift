#if os(Windows)
import Foundation
import WinSDK

/// Stores Canvas access tokens in the current Windows user's Credential Manager.
/// Credentials stay on this machine and are never written to app settings or logs.
final class WindowsCredentialSecretStore: SecretStore, @unchecked Sendable {
    private static let maximumBlobSize = 2_560

    private let service: String

    init(service: String) {
        self.service = service
    }

    func set(_ secret: Data, account: String) throws {
        guard secret.count <= Self.maximumBlobSize else {
            throw SecretStoreError.invalidData
        }

        let written = try withTargetName(account: account) { targetName in
            secret.withUnsafeBytes { bytes -> Bool in
                if let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress {
                    return write(
                        targetName: targetName,
                        bytes: UnsafeMutablePointer(mutating: baseAddress),
                        count: secret.count
                    )
                }

                var placeholder: UInt8 = 0
                return withUnsafeMutablePointer(to: &placeholder) {
                    write(targetName: targetName, bytes: $0, count: 0)
                }
            }
        }
        guard written else { throw mapLastError() }
    }

    func data(account: String) throws -> Data {
        var credential: PCREDENTIALW?
        let read = try withTargetName(account: account) { targetName in
            CredReadW(targetName, DWORD(CRED_TYPE_GENERIC), 0, &credential)
        }
        guard read else { throw mapLastError() }
        guard let credential else { throw SecretStoreError.invalidData }
        defer { CredFree(credential) }

        let count = Int(credential.pointee.CredentialBlobSize)
        guard count > 0 else { return Data() }
        guard let blob = credential.pointee.CredentialBlob else {
            throw SecretStoreError.invalidData
        }
        return Data(bytes: blob, count: count)
    }

    func remove(account: String) throws {
        let deleted = try withTargetName(account: account) { targetName in
            CredDeleteW(targetName, DWORD(CRED_TYPE_GENERIC), 0)
        }
        if !deleted, GetLastError() != ERROR_NOT_FOUND {
            throw mapLastError()
        }
    }

    private func write(
        targetName: UnsafeMutablePointer<WCHAR>,
        bytes: UnsafeMutablePointer<UInt8>,
        count: Int
    ) -> Bool {
        var credential = CREDENTIALW()
        credential.Type = DWORD(CRED_TYPE_GENERIC)
        credential.TargetName = targetName
        credential.CredentialBlob = bytes
        credential.CredentialBlobSize = DWORD(count)
        credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
        return CredWriteW(&credential, 0)
    }

    private func withTargetName<Result>(
        account: String,
        _ body: (UnsafeMutablePointer<WCHAR>) throws -> Result
    ) rethrows -> Result {
        let targetName = "CampusDashboard:\(escaped(service)):\(escaped(account))"
        return try targetName.withCString(encodedAs: UTF16.self) { pointer in
            try body(UnsafeMutablePointer(mutating: pointer))
        }
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: ":", with: "%3A")
    }

    private func mapLastError() -> SecretStoreError {
        let code = GetLastError()
        switch code {
        case DWORD(ERROR_NOT_FOUND):
            return .notFound
        case DWORD(ERROR_ACCESS_DENIED), DWORD(ERROR_CANCELLED):
            return .denied
        case DWORD(ERROR_NO_SUCH_LOGON_SESSION):
            return .unavailable
        default:
            return .operatingSystemStatus(Int32(bitPattern: code))
        }
    }
}
#endif
