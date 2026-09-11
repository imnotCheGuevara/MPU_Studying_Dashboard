#if os(Windows)
import Foundation
import SwiftCrossUI

@MainActor
final class WindowsDashboardState: SwiftCrossUI.ObservableObject {
    private static let canvasSecretService = "com.campusdashboard.desktop.canvas"

    @SwiftCrossUI.Published var snapshot = SyntheticFixtures.populated
    @SwiftCrossUI.Published var canvasBaseURL = ""
    @SwiftCrossUI.Published var canvasToken = ""
    @SwiftCrossUI.Published var statusMessage = "Preview data is active. Connect Canvas for a live read-only sync."
    @SwiftCrossUI.Published var hasSavedCanvasToken = false
    @SwiftCrossUI.Published var isSyncing = false
    @SwiftCrossUI.Published var isShowingPreview = true

    private let configurationStore: UserDefaultsCanvasConfigurationStore
    private let secretStore: any SecretStore

    init(
        configurationStore: UserDefaultsCanvasConfigurationStore = UserDefaultsCanvasConfigurationStore(),
        secretStore: any SecretStore = WindowsCredentialSecretStore(
            service: "com.campusdashboard.desktop.canvas"
        )
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        if let configuration = try? configurationStore.load() {
            canvasBaseURL = configuration.baseURL.absoluteString
        }
        hasSavedCanvasToken = (try? secretStore.data(account: CanvasConfiguration.tokenAccount)) != nil
    }

    func synchronizeCanvas() async {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = "Syncing Canvas read-only data…"
        defer { isSyncing = false }

        do {
            let urlText = canvasBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: urlText) else {
                throw CanvasConfigurationError.invalidBaseURL
            }
            let configuration = try CanvasConfiguration(baseURL: url)

            let token = canvasToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                try secretStore.set(Data(token.utf8), account: configuration.tokenAccount)
                canvasToken = ""
                hasSavedCanvasToken = true
            } else if !hasSavedCanvasToken {
                throw CanvasConfigurationError.emptyToken
            }

            try configurationStore.saveBaseURL(configuration.baseURL)
            canvasBaseURL = configuration.baseURL.absoluteString

            let connector = CanvasAPIConnector(configuration: configuration, secretStore: secretStore)
            let source = try await CanvasSnapshotLoader(service: connector).load()
            let now = Date()
            snapshot = WindowsCanvasSnapshotMapper().map(
                source,
                accountID: configuration.baseURL.host ?? configuration.baseURL.absoluteString,
                syncedAt: now
            )
            isShowingPreview = false
            statusMessage = "Canvas synced: \(source.courses.count) courses, \(source.tasks.count) tasks, \(source.announcements.count) announcements."
        } catch {
            statusMessage = "Canvas sync failed: \(safeDescription(error))"
        }
    }

    func forgetCanvas() {
        do {
            try secretStore.remove(account: CanvasConfiguration.tokenAccount)
            configurationStore.removeBaseURL()
            canvasBaseURL = ""
            canvasToken = ""
            hasSavedCanvasToken = false
            snapshot = SyntheticFixtures.populated
            isShowingPreview = true
            statusMessage = "Canvas credentials removed. Preview data is active."
        } catch {
            statusMessage = "Could not remove Canvas credentials: \(safeDescription(error))"
        }
    }

    private func safeDescription(_ error: Error) -> String {
        if let error = error as? CanvasConnectorError { return error.diagnostic }
        if let error = error as? CanvasConfigurationError { return error.description }
        if let error = error as? SecretStoreError { return error.description }
        return "Unexpected error. Check the URL, token, and network connection."
    }
}
#endif
