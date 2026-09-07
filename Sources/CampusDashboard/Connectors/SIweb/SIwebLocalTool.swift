import Darwin
import Foundation

enum SIwebLocalTool {
    static let keychainService = "com.campusdashboard.desktop.siweb"

    static func configure() -> Int32 {
        print("Approved SIweb HTTPS base URL (no credentials): ", terminator: "")
        guard let baseText = readLine(), let baseURL = URL(string: baseText) else {
            writeError("Configuration failed: invalidBaseURL")
            return 2
        }
        print("Approved schedule page URLs, one per line; submit a blank line when finished.")
        var targets: [URL] = []
        while true {
            print("Target page URL: ", terminator: "")
            guard let value = readLine() else {
                writeError("Configuration failed: target input unavailable")
                return 2
            }
            if value.isEmpty { break }
            guard let url = URL(string: value) else {
                writeError("Configuration failed: unsafeTargetPage")
                return 2
            }
            targets.append(url)
        }

        let configuration: SIwebConfiguration
        do { configuration = try SIwebConfiguration(baseURL: baseURL, targetPageURLs: targets) }
        catch {
            writeError("Configuration failed: \(safeCategory(error))")
            return 2
        }
        guard let session = readHiddenSession() else {
            writeError("Configuration failed: session input requires an interactive terminal")
            return 2
        }
        do {
            try UserDefaultsSIwebConfigurationStore().save(configuration)
            let secrets = KeychainSecretStore(service: keychainService)
            try secrets.remove(account: SIwebConfiguration.sessionAccount)
            try secrets.set(session, account: SIwebConfiguration.sessionAccount)
            print("SIweb target configuration saved; authorized session material is in Keychain.")
            return 0
        } catch {
            writeError("Configuration failed: \(safeCategory(error))")
            return 2
        }
    }

    static func smokeTest() async -> Int32 {
        do {
            let configuration = try UserDefaultsSIwebConfigurationStore().load()
            let connector = SIwebConnector(
                configuration: configuration,
                authorizer: KeychainSIwebSessionAuthorizer(
                    secretStore: KeychainSecretStore(service: keychainService),
                    account: configuration.sessionAccount
                )
            )
            let snapshot = try await SIwebSnapshotLoader(service: connector).load()
            let cancelled = snapshot.meetings.filter(\.isCancelled).count
            print("PASS read-only SIweb smoke test: \(snapshot.meetings.count) meetings, \(cancelled) cancelled.")
            return 0
        } catch {
            if let error = error as? SIwebConnectorError {
                writeError(error.diagnostic)
            } else {
                writeError("SIweb smoke test failed: \(safeCategory(error))")
            }
            return 3
        }
    }

    private static func readHiddenSession() -> Data? {
        var buffer = [CChar](repeating: 0, count: 16_384)
        defer {
            buffer.withUnsafeMutableBytes { bytes in
                if let address = bytes.baseAddress { bzero(address, bytes.count) }
            }
        }
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            readpassphrase(
                "Institution-approved session Cookie header (input hidden): ",
                pointer.baseAddress, pointer.count, RPP_ECHO_OFF | RPP_REQUIRE_TTY
            )
        }
        guard result != nil else { return nil }
        let length = buffer.withUnsafeBufferPointer { strnlen($0.baseAddress, $0.count) }
        guard length > 0 else { return nil }
        return buffer.withUnsafeBytes { Data($0.prefix(length)) }
    }

    private static func safeCategory(_ error: Error) -> String {
        if let error = error as? SIwebConnectorError { return error.category.rawValue }
        if let error = error as? SIwebConfigurationError { return String(describing: error) }
        if let error = error as? SecretStoreError { return String(describing: error) }
        return "local configuration unavailable"
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
