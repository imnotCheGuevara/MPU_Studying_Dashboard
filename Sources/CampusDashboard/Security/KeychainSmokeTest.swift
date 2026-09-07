import Foundation
import Darwin

enum KeychainSmokeTest {
    static func run(resultPath: String) -> Never {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "missing-bundle-identifier"
        let account = "packaged-smoke-\(UUID().uuidString)"
        let store = KeychainSecretStore(service: bundleIdentifier)
        let value = Data(UUID().uuidString.utf8)
        let result: String

        do {
            try store.set(value, account: account)
            guard try store.data(account: account) == value else { throw SecretStoreError.invalidData }
            try store.remove(account: account)
            do {
                _ = try store.data(account: account)
                throw SecretStoreError.invalidData
            } catch SecretStoreError.notFound {
                // Expected after deletion.
            }
            result = "PASS \(bundleIdentifier)\n"
        } catch {
            // The report contains only a category/status, never the generated value.
            result = "FAIL \(bundleIdentifier) \(error)\n"
        }

        do {
            let resultURL: URL
            if resultPath.hasPrefix("/") {
                resultURL = URL(fileURLWithPath: resultPath)
            } else {
                let support = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true
                ).appendingPathComponent(bundleIdentifier, isDirectory: true)
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                resultURL = support.appendingPathComponent(resultPath)
            }
            try Data(result.utf8).write(to: resultURL, options: .atomic)
        } catch {}
        Darwin.exit(result.hasPrefix("PASS") ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
