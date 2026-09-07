import AppKit
import Foundation
import WebKit

enum SIwebSessionCookieSerializer {
    private static let targetPath = MPUSIwebEndpoints.classTimeURL.path

    static func headerData(from cookies: [HTTPCookie], now: Date = Date()) -> Data? {
        let values = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == MPUSIwebEndpoints.operationalHost
                && targetPath.hasPrefix(cookie.path)
                && cookie.isSecure
                && (cookie.expiresDate == nil || cookie.expiresDate! > now)
                && !cookie.name.isEmpty
                && cookie.name.rangeOfCharacter(from: .newlines) == nil
                && cookie.value.rangeOfCharacter(from: .newlines) == nil
        }.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.path < rhs.path : lhs.name < rhs.name
        }.map { "\($0.name)=\($0.value)" }
        guard !values.isEmpty else { return nil }
        return Data(values.joined(separator: "; ").utf8)
    }
}

@MainActor
enum SIwebWebAuthenticationTool {
    static func run() -> Int32 {
        let controller = SIwebWebAuthenticationController()
        controller.start()
        NSApplication.shared.run()
        return controller.result
    }
}

@MainActor
private final class SIwebWebAuthenticationController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private static let entryURL = MPUSIwebEndpoints.publishedEntryURL
    private static let baseURL = MPUSIwebEndpoints.operationalBaseURL
    private static let timetableURL = MPUSIwebEndpoints.classTimeURL

    private(set) var result: Int32 = 2
    private var completed = false
    private var window: NSWindow?
    private var webView: WKWebView?

    func start() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self

        let explanation = NSTextField(wrappingLabelWithString:
            "Sign in directly on MPU's page. Campus Dashboard does not read the login form. " +
            "After MPU returns to SIWeb, only the authorized wapps2 session is stored in Keychain."
        )
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [explanation, webView])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        explanation.setContentHuggingPriority(.required, for: .vertical)
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Authorize MPU SIWeb (read-only)"
        window.contentView = stack
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)

        self.window = window
        self.webView = webView
        webView.load(URLRequest(url: Self.entryURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !completed, let url = webView.url else { return }
        let host = url.host?.lowercased()
        let isStudentHome = host == MPUSIwebEndpoints.studentHomeHost
            && url.path.hasSuffix("/customPage/page/StudentHomePage")
        let isSIwebHome = host == MPUSIwebEndpoints.operationalHost
            && url.path == "/siweb_cas/siweb_sa.asp"
        guard isStudentHome || isSIwebHome else { return }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in self?.finish(cookies: cookies) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard !completed else { return }
        finish(result: 2, message: "SIWeb authorization cancelled before an authorized session was established.")
    }

    private func finish(cookies: [HTTPCookie]) {
        guard let header = SIwebSessionCookieSerializer.headerData(from: cookies) else {
            finish(result: 3, message: "SIWeb authorization failed: target session unavailable")
            return
        }
        do {
            let configuration = try SIwebConfiguration(
                baseURL: Self.baseURL,
                targetPageURLs: [Self.timetableURL],
                minimumRequestInterval: 1,
                maximumConcurrentRequests: 1
            )
            try UserDefaultsSIwebConfigurationStore().save(configuration)
            let secrets = KeychainSecretStore(service: SIwebLocalTool.keychainService)
            try secrets.remove(account: SIwebConfiguration.sessionAccount)
            try secrets.set(header, account: SIwebConfiguration.sessionAccount)
            finish(result: 0, message: "MPU SIWeb authorization saved securely in Keychain.")
        } catch {
            finish(result: 3, message: "SIWeb authorization failed: secure storage unavailable")
        }
    }

    private func finish(result: Int32, message: String) {
        guard !completed else { return }
        completed = true
        self.result = result
        if result == 0 { print(message) }
        else { FileHandle.standardError.write(Data((message + "\n").utf8)) }
        window?.delegate = nil
        window?.close()
        webView = nil
        window = nil
        NSApplication.shared.stop(nil)
        NSApplication.shared.postEvent(
            NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
            )!, atStart: false
        )
    }
}
