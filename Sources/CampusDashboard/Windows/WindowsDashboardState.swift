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
    private let snapshotStore: WindowsSnapshotStore

    init(
        configurationStore: UserDefaultsCanvasConfigurationStore = UserDefaultsCanvasConfigurationStore(),
        secretStore: any SecretStore = WindowsCredentialSecretStore(
            service: "com.campusdashboard.desktop.canvas"
        ),
        snapshotStore: WindowsSnapshotStore = WindowsSnapshotStore()
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.snapshotStore = snapshotStore

        do {
            if let savedSnapshot = try snapshotStore.load() {
                snapshot = savedSnapshot
                isShowingPreview = false
                statusMessage = "Saved Canvas data is available offline. Sync to refresh it."
            }
        } catch {
            statusMessage = "Saved Canvas data could not be loaded. Preview data is active."
        }

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
            let synchronizedSnapshot = WindowsCanvasSnapshotMapper().map(
                source,
                accountID: configuration.baseURL.host ?? configuration.baseURL.absoluteString,
                syncedAt: now
            )
            snapshot = synchronizedSnapshot
            isShowingPreview = false
            do {
                try snapshotStore.save(synchronizedSnapshot, now: now)
                statusMessage = "Canvas synced and saved for offline use: \(source.courses.count) courses, \(source.tasks.count) tasks, \(source.announcements.count) announcements."
            } catch {
                statusMessage = "Canvas synced, but its offline copy could not be saved."
            }
        } catch {
            statusMessage = "Canvas sync failed: \(safeDescription(error))"
        }
    }

    func forgetCanvas() {
        var removalFailed = false
        do {
            try secretStore.remove(account: CanvasConfiguration.tokenAccount)
        } catch {
            removalFailed = true
        }
        do {
            try snapshotStore.remove()
        } catch {
            removalFailed = true
        }

        configurationStore.removeBaseURL()
        canvasBaseURL = ""
        canvasToken = ""
        hasSavedCanvasToken = false
        snapshot = SyntheticFixtures.populated
        isShowingPreview = true
        statusMessage = removalFailed
            ? "Some saved Canvas data could not be removed. Close the app and try again."
            : "Canvas credentials and offline data removed. Preview data is active."
    }

    private func safeDescription(_ error: Error) -> String {
        if let error = error as? CanvasConnectorError { return error.diagnostic }
        if let error = error as? CanvasConfigurationError { return error.description }
        if let error = error as? SecretStoreError { return error.description }
        if let error = error as? WindowsSnapshotStoreError { return error.description }
        return "Unexpected error. Check the URL, token, and network connection."
    }
}
#endif
