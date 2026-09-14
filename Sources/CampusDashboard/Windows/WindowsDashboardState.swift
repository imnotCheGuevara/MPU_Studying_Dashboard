#if os(Windows)
import Foundation
import SwiftCrossUI

@MainActor
final class WindowsDashboardState: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published var snapshot = SyntheticFixtures.populated
    @SwiftCrossUI.Published var canvasBaseURL = ""
    @SwiftCrossUI.Published var canvasToken = ""
    @SwiftCrossUI.Published var siwebSession = ""
    @SwiftCrossUI.Published var statusMessage = "Preview data is active. Connect Canvas for a live read-only sync."
    @SwiftCrossUI.Published var hasSavedCanvasToken = false
    @SwiftCrossUI.Published var hasSavedSIwebSession = false
    @SwiftCrossUI.Published var isSyncing = false
    @SwiftCrossUI.Published var isShowingPreview = true
    @SwiftCrossUI.Published var language = WindowsLanguage.english

    private let configurationStore: UserDefaultsCanvasConfigurationStore
    private let canvasSecretStore: any SecretStore
    private let siwebSecretStore: any SecretStore
    private let snapshotStore: WindowsSnapshotStore
    private let languageStore: WindowsLanguageStore

    var copy: WindowsCopy { WindowsCopy(language: language) }

    init(
        configurationStore: UserDefaultsCanvasConfigurationStore = UserDefaultsCanvasConfigurationStore(),
        secretStore: any SecretStore = WindowsCredentialSecretStore(
            service: "com.campusdashboard.desktop.canvas"
        ),
        siwebSecretStore: any SecretStore = WindowsCredentialSecretStore(
            service: "com.campusdashboard.desktop.siweb"
        ),
        snapshotStore: WindowsSnapshotStore = WindowsSnapshotStore(),
        languageStore: WindowsLanguageStore = WindowsLanguageStore()
    ) {
        self.configurationStore = configurationStore
        canvasSecretStore = secretStore
        self.siwebSecretStore = siwebSecretStore
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
        hasSavedCanvasToken = (try? canvasSecretStore.data(account: CanvasConfiguration.tokenAccount)) != nil
        hasSavedSIwebSession = (try? siwebSecretStore.data(account: SIwebConfiguration.sessionAccount)) != nil
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
                try canvasSecretStore.set(Data(token.utf8), account: configuration.tokenAccount)
                canvasToken = ""
                hasSavedCanvasToken = true
            } else if !hasSavedCanvasToken {
                throw CanvasConfigurationError.emptyToken
            }

            try configurationStore.saveBaseURL(configuration.baseURL)
            canvasBaseURL = configuration.baseURL.absoluteString

            let connector = CanvasAPIConnector(configuration: configuration, secretStore: canvasSecretStore)
            let source = try await CanvasSnapshotLoader(service: connector).load()
            let now = Date()
            let canvasSnapshot = WindowsCanvasSnapshotMapper().map(
                source,
                accountID: configuration.baseURL.host ?? configuration.baseURL.absoluteString,
                syncedAt: now
            )
            let synchronizedSnapshot = WindowsSIwebSnapshotMerger().preservingSIweb(
                from: isShowingPreview ? .empty : snapshot,
                in: canvasSnapshot
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

    func synchronizeSIweb() async {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = copy.siwebSyncingStatus
        defer { isSyncing = false }

        do {
            let candidate = siwebSession.trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                let normalized = try WindowsSIwebSessionInput().normalize(candidate)
                try siwebSecretStore.set(
                    Data(normalized.utf8), account: SIwebConfiguration.sessionAccount
                )
                siwebSession = ""
                hasSavedSIwebSession = true
            } else if !hasSavedSIwebSession {
                throw WindowsSIwebSessionInputError.empty
            }

            let configuration = try SIwebConfiguration(
                baseURL: MPUSIwebEndpoints.operationalBaseURL,
                targetPageURLs: [MPUSIwebEndpoints.classTimeURL]
            )
            let connector = SIwebConnector(
                configuration: configuration,
                authorizer: KeychainSIwebSessionAuthorizer(
                    secretStore: siwebSecretStore,
                    account: configuration.sessionAccount
                )
            )
            let source = try await SIwebSnapshotLoader(service: connector).load()
            let now = Date()
            let synchronizedSnapshot = WindowsSIwebSnapshotMerger().merge(
                source,
                into: isShowingPreview ? .empty : snapshot,
                syncedAt: now
            )
            snapshot = synchronizedSnapshot
            isShowingPreview = false
            do {
                try snapshotStore.save(synchronizedSnapshot, now: now)
                statusMessage = copy.siwebSyncedStatus(meetings: source.meetings.count)
            } catch {
                statusMessage = copy.siwebSnapshotSaveFailedStatus
            }
        } catch {
            statusMessage = copy.siwebSyncFailedStatus(safeDescription(error))
        }
    }

    func forgetCanvas() {
        var removalFailed = false
        do {
            try canvasSecretStore.remove(account: CanvasConfiguration.tokenAccount)
        } catch {
            removalFailed = true
        }

        configurationStore.removeBaseURL()
        canvasBaseURL = ""
        canvasToken = ""
        hasSavedCanvasToken = false
        if hasSavedSIwebSession {
            snapshot = WindowsSIwebSnapshotMerger().removingCanvas(from: snapshot)
            isShowingPreview = false
            do { try snapshotStore.save(snapshot) } catch { removalFailed = true }
        } else {
            do { try snapshotStore.remove() } catch { removalFailed = true }
            snapshot = SyntheticFixtures.populated
            isShowingPreview = true
        }
        statusMessage = removalFailed
            ? copy.removalPartialStatus
            : (hasSavedSIwebSession ? copy.canvasRemovedSIwebRetainedStatus : copy.removedStatus)
    }

    func forgetSIweb() {
        var removalFailed = false
        do {
            try siwebSecretStore.remove(account: SIwebConfiguration.sessionAccount)
        } catch {
            removalFailed = true
        }
        siwebSession = ""
        hasSavedSIwebSession = false

        if hasSavedCanvasToken {
            snapshot = WindowsSIwebSnapshotMerger().removingSIweb(from: snapshot)
            isShowingPreview = false
            do { try snapshotStore.save(snapshot) } catch { removalFailed = true }
        } else {
            do { try snapshotStore.remove() } catch { removalFailed = true }
            snapshot = SyntheticFixtures.populated
            isShowingPreview = true
        }
        statusMessage = removalFailed
            ? copy.siwebRemovalPartialStatus
            : (hasSavedCanvasToken ? copy.siwebRemovedCanvasRetainedStatus : copy.siwebRemovedStatus)
    }

    private func safeDescription(_ error: Error) -> String {
        if language == .english {
            if let error = error as? CanvasConnectorError { return error.diagnostic }
            if let error = error as? CanvasConfigurationError { return error.description }
            if let error = error as? SecretStoreError { return error.description }
            if let error = error as? WindowsSnapshotStoreError { return error.description }
            if let error = error as? WindowsSIwebSessionInputError { return error.description }
            if let error = error as? SIwebConnectorError { return error.diagnostic }
            if let error = error as? SIwebConfigurationError { return error.description }
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
        if error is WindowsSIwebSessionInputError { return "请仅粘贴浏览器请求中的 Cookie 值（name=value），不要粘贴密码或整段请求。" }
        if let error = error as? SIwebConnectorError {
            switch error.category {
            case .sessionExpired, .loginRedirect, .unauthorized:
                return "SIweb 会话已失效，请在浏览器重新登录并替换会话值。"
            default:
                return "SIweb 只读同步失败，请检查会话值、网络及网页结构。"
            }
        }
        if error is SIwebConfigurationError { return "SIweb 固定只读地址配置无效。" }
        if error is CanvasConnectorError { return "请检查地址、令牌和网络连接。" }
        return "发生意外错误，请检查地址、令牌和网络连接。"
    }
}
#endif
