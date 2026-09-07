import SwiftUI
import WebKit

struct ReleaseSetupAssistantView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.text("Welcome to Campus Dashboard")).font(.largeTitle.weight(.semibold))
            Text(model.text("Connect only the services you want. Each row explains the minimum data used and can be changed later in Settings."))
                .foregroundStyle(.secondary)
            ForEach(model.setupItems) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(item.isComplete ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.text(item.integration.rawValue)).font(.headline)
                        Text(model.text(item.detail))
                        Text(model.text(item.minimumData)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.integration.isOptional { Text(model.text("Optional")).font(.caption) }
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                Button(model.text("Open setup settings")) {
                    model.selectedSection = .settings
                    model.finishSetupAssistant()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button(model.text("Continue for now")) { model.finishSetupAssistant() }
            }
        }
        .padding(28).frame(width: 680)
        .interactiveDismissDisabled()
    }
}

struct SIwebAuthorizationView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.text("Authorize MPU SIWeb (read-only)"))
                .font(.title2.weight(.semibold))
            Text(model.text("Sign in directly on MPU's non-persistent page. Campus Dashboard does not read the login form. After MPU returns to SIWeb, only the authorized wapps2 session is stored in Keychain."))
                .font(.caption).foregroundStyle(.secondary)
            SIwebAuthorizationWebView { message in
                model.completeSIwebAuthorization(message)
            }
            .accessibilityLabel(model.text("MPU SIWeb sign-in page"))
            HStack {
                Text(model.text("Closing this window cancels authorization and does not affect Canvas, Calendar, or notifications."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.text("Cancel")) {
                    model.completeSIwebAuthorization("SIWeb authorization was cancelled. Other integrations were not changed.")
                }
            }
        }
        .padding(18).frame(minWidth: 820, minHeight: 650)
    }
}

private struct SIwebAuthorizationWebView: NSViewRepresentable {
    let completion: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: MPUSIwebEndpoints.publishedEntryURL,
                             cachePolicy: .reloadIgnoringLocalCacheData))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let completion: (String) -> Void
        private var completed = false

        init(completion: @escaping (String) -> Void) { self.completion = completion }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !completed, let url = webView.url else { return }
            let host = url.host?.lowercased()
            let authorized = (host == MPUSIwebEndpoints.studentHomeHost
                              && url.path.hasSuffix("/customPage/page/StudentHomePage"))
                || (host == MPUSIwebEndpoints.operationalHost && url.path == "/siweb_cas/siweb_sa.asp")
            guard authorized else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor in self?.store(cookies) }
            }
        }

        private func store(_ cookies: [HTTPCookie]) {
            guard !completed else { return }
            guard let header = SIwebSessionCookieSerializer.headerData(from: cookies) else {
                completion("SIWeb authorization reached MPU but no eligible secure session was available. Retry SIweb only.")
                return
            }
            do {
                let configuration = try SIwebConfiguration(
                    baseURL: MPUSIwebEndpoints.operationalBaseURL,
                    targetPageURLs: [MPUSIwebEndpoints.classTimeURL],
                    minimumRequestInterval: 1,
                    maximumConcurrentRequests: 1
                )
                try UserDefaultsSIwebConfigurationStore().save(configuration)
                let secrets = KeychainSecretStore(service: SIwebLocalTool.keychainService)
                try secrets.remove(account: SIwebConfiguration.sessionAccount)
                try secrets.set(header, account: SIwebConfiguration.sessionAccount)
                completed = true
                completion("MPU SIWeb authorization was saved securely in Keychain.")
            } catch {
                completion("SIWeb authorization could not be saved securely. Other integrations were not changed.")
            }
        }
    }
}
