import Darwin
import Foundation

enum CanvasLocalTool {
    static let keychainService = "com.campusdashboard.desktop.canvas"

    static func configure() -> Int32 {
        print("Canvas HTTPS base URL (URL only; never paste a token here): ", terminator: "")
        guard let value = readLine() else {
            writeError("Configuration failed: Canvas URL input unavailable")
            return 2
        }
        let configuration: CanvasConfiguration
        do {
            configuration = try validatedConfiguration(value)
        } catch {
            writeError("Configuration failed: \(safeCategory(error))")
            return 2
        }

        guard let token = readHiddenAuthorization() else {
            writeError("Configuration failed: authorization input requires an interactive terminal")
            return 2
        }
        do {
            try UserDefaultsCanvasConfigurationStore().saveBaseURL(configuration.baseURL)
            let secretStore = KeychainSecretStore(service: keychainService)
            // Local ad-hoc development builds receive a new code requirement when
            // rebuilt. Recreate the explicitly reauthorized item so its Keychain
            // ACL belongs to the currently signed application instead of retaining
            // the previous build's ACL through SecItemUpdate.
            try secretStore.remove(account: CanvasConfiguration.tokenAccount)
            try secretStore.set(token, account: CanvasConfiguration.tokenAccount)
            print("Canvas configuration saved securely (authorization is in Keychain).")
            return 0
        } catch {
            writeError("Configuration failed: \(safeCategory(error))")
            return 2
        }
    }

    static func validatedConfiguration(_ value: String) throws -> CanvasConfiguration {
        guard let url = URL(string: value) else { throw CanvasConfigurationError.invalidBaseURL }
        return try CanvasConfiguration(baseURL: url)
    }

    static func smokeTest() async -> Int32 {
        do {
            let configuration = try UserDefaultsCanvasConfigurationStore().load()
            let connector = CanvasAPIConnector(
                configuration: configuration,
                secretStore: KeychainSecretStore(service: keychainService)
            )
            let snapshot = try await CanvasSnapshotLoader(service: connector).load()
            print(
                "PASS read-only Canvas smoke test: \(snapshot.courses.count) courses, " +
                "\(snapshot.tasks.count) tasks, \(snapshot.announcements.count) announcements."
            )
            return 0
        } catch {
            writeError("Canvas smoke test failed: \(safeCategory(error))")
            return 3
        }
    }

    private static func safeCategory(_ error: Error) -> String {
        if let error = error as? CanvasConnectorError { return error.category.rawValue }
        if let error = error as? CanvasConfigurationError { return String(describing: error) }
        if let error = error as? SecretStoreError { return String(describing: error) }
        return "local configuration unavailable"
    }

    private static func readHiddenAuthorization() -> Data? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        defer {
            buffer.withUnsafeMutableBytes { bytes in
                if let address = bytes.baseAddress { bzero(address, bytes.count) }
            }
        }
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            readpassphrase(
                "Institution-approved Canvas access token (input hidden): ",
                pointer.baseAddress,
                pointer.count,
                RPP_ECHO_OFF | RPP_REQUIRE_TTY
            )
        }
        guard result != nil else { return nil }
        let length = buffer.withUnsafeBufferPointer { pointer in
            strnlen(pointer.baseAddress, pointer.count)
        }
        guard length > 0 else { return nil }
        return buffer.withUnsafeBytes { Data($0.prefix(length)) }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
