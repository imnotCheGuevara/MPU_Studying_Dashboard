import Foundation
import Security
import Testing
@testable import CampusDashboard

@Suite("Secret store")
struct SecretStoreTests {
    @Test("Fake store supports opaque-data lifecycle")
    func lifecycle() throws {
        let store = FakeSecretStore()
        let value = Data([1, 2, 3, 4])
        try store.set(value, account: "synthetic-account")
        #expect(try store.data(account: "synthetic-account") == value)
        try store.remove(account: "synthetic-account")
        #expect(throws: SecretStoreError.notFound) {
            try store.data(account: "synthetic-account")
        }
    }

    @Test("Denied Keychain state is visible and safe")
    func denied() {
        let store = FakeSecretStore(mode: .denied)
        #expect(throws: SecretStoreError.denied) {
            try store.set(Data([7]), account: "synthetic-account")
        }
        #expect(throws: SecretStoreError.denied) {
            try store.data(account: "synthetic-account")
        }
    }

    @Test("Unavailable Keychain state is visible and safe")
    func unavailable() {
        let store = FakeSecretStore(mode: .unavailable)
        #expect(throws: SecretStoreError.unavailable) {
            try store.set(Data([8]), account: "synthetic-account")
        }
        #expect(throws: SecretStoreError.unavailable) {
            try store.remove(account: "synthetic-account")
        }
    }

    @Test("Keychain adapter maps denied and unavailable OS statuses")
    func keychainStatusMapping() {
        let deniedStore = KeychainSecretStore(
            service: "com.campusdashboard.tests",
            client: client(addStatus: errSecInteractionNotAllowed)
        )
        let unavailableStore = KeychainSecretStore(
            service: "com.campusdashboard.tests",
            client: client(addStatus: errSecMissingEntitlement)
        )
        #expect(throws: SecretStoreError.denied) {
            try deniedStore.set(Data([1]), account: "synthetic-account")
        }
        #expect(throws: SecretStoreError.unavailable) {
            try unavailableStore.set(Data([1]), account: "synthetic-account")
        }
    }

    private func client(addStatus: OSStatus) -> KeychainClient {
        KeychainClient(
            add: { _ in addStatus },
            update: { _, _ in errSecSuccess },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecItemNotFound }
        )
    }
}
