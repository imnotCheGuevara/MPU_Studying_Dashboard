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
    @SwiftCrossUI.Published var language = WindowsLanguage.english

    private let configurationStore: UserDefaultsCanvasConfigurationStore
    private let secretStore: any SecretStore
    private let snapshotStore: WindowsSnapshotStore
    private let languageStore: WindowsLanguageStore

    var copy: WindowsCopy { WindowsCopy(language: language) }

    init(
        configurationStore: UserDefaultsCanvasConfigurationStore = UserDefaultsCanvasConfigurationStore(),
        secretStore: any SecretStore = WindowsCredentialSecretStore(
            service: "com.campusdashboard.desktop.canvas"
        ),
        snapshotStore: WindowsSnapshotStore = WindowsSnapshotStore(),
        languageStore: WindowsLanguageStore = WindowsLanguageStore()
    ) {
        self.configurationStore = configurationStore
        self.secretStore = secretStore
        self.snapshotStore = snapshotStore
        self.languageStore = languageStore
        language = languageStore.load()
        statusMessage = copy.previewStatus

        do {
            if let savedSnapshot = try snapshotStore.load() {
                snapshot = savedSnapshot
                isShowingPreview = false
                statusMessage = copy.offlineStatus
            }
        } catch {
            statusMessage = copy.unreadableSnapshotStatus
        }

        if let configuration = try? configurationStore.load() {
            canvasBaseURL = configuration.baseURL.absoluteString
        }
        hasSavedCanvasToken = (try? secretStore.data(account: CanvasConfiguration.tokenAccount)) != nil
    }

    func selectLanguage(_ newLanguage: WindowsLanguage) {
        language = newLanguage
        languageStore.save(newLanguage)
        statusMessage = isShowingPreview ? copy.previewStatus : copy.offlineStatus
    }

    func synchronizeCanvas() async {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = copy.syncingStatus
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
                statusMessage = copy.syncedStatus(
                    courses: source.courses.count,
                    tasks: source.tasks.count,
                    announcements: source.announcements.count
                )
            } catch {
                statusMessage = copy.snapshotSaveFailedStatus
            }
        } catch {
            statusMessage = copy.syncFailedStatus(safeDescription(error))
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
            ? copy.removalPartialStatus
            : copy.removedStatus
    }

    private func safeDescription(_ error: Error) -> String {
        if language == .english {
            if let error = error as? CanvasConnectorError { return error.diagnostic }
            if let error = error as? CanvasConfigurationError { return error.description }
            if let error = error as? SecretStoreError { return error.description }
            if let error = error as? WindowsSnapshotStoreError { return error.description }
            return "Unexpected error. Check the URL, token, and network connection."
        }

        if let error = error as? CanvasConfigurationError {
            switch error {
            case .invalidBaseURL: return "Canvas 地址必须是 HTTPS，且不能包含凭据、查询参数或片段。"
            case .missingBaseURL: return "尚未配置 Canvas 地址。"
            case .emptyToken: return "Canvas 授权令牌为空。"
            }
        }
        if error is SecretStoreError { return "无法访问 Windows 凭据管理器。" }
        if error is WindowsSnapshotStoreError { return "无法访问本地离线数据。" }
        if error is CanvasConnectorError { return "请检查地址、令牌和网络连接。" }
        return "发生意外错误，请检查地址、令牌和网络连接。"
    }
}
#endif
