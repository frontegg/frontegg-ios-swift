//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  POC: native admin portal via embedded WKWebView with shared session.
//
//  Authenticates the WKWebView before loading `${baseUrl}/oauth/portal` so
//  the user never sees a re-login prompt. Strategy:
//
//    1. Call `silentAuthorize` over URLSession — the response sets the full
//       `fe_refresh_*` + `fe_device_*` cookie pair on `HTTPCookieStorage.shared`.
//    2. Mirror every cookie for the base host from `HTTPCookieStorage.shared`
//       into the WebView's `WKHTTPCookieStore`.
//    3. As a defensive fallback (e.g. `silentAuthorize` failed offline) also
//       inject the `fe_refresh_*` cookie directly from the SDK's stored
//       refresh token.
//    4. Load the portal URL.
//
//  The two-step bridge is required because URLSession and WKWebView do NOT
//  share a cookie jar — even when the user has a valid SDK session, the
//  WebView's store is empty until we copy cookies in.
//

import Foundation
import WebKit
import SwiftUI

@available(iOS 14.0, *)
struct AdminPortalWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    private let fronteggAuth: FronteggAuth
    private let onNavigationFailure: ((URL?) -> Void)?
    private let logger = getLogger("AdminPortalWebView")

    init(onNavigationFailure: ((URL?) -> Void)? = nil) {
        self.fronteggAuth = FronteggAuth.shared
        self.onNavigationFailure = onNavigationFailure
    }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        // Share the SDK's process pool and persistent data store so cookies
        // any login webview wrote are visible here too.
        conf.processPool = WebViewShared.processPool
        conf.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: conf)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator

        #if compiler(>=5.8) && os(iOS) && DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        Task { @MainActor in
            await authenticateAndLoad(webView: webView)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationFailure: onNavigationFailure)
    }

    // MARK: - Auth bridging

    @MainActor
    private func authenticateAndLoad(webView: WKWebView) async {
        guard let baseUrl = URL(string: fronteggAuth.baseUrl),
              let portalUrl = URL(string: "\(fronteggAuth.baseUrl)/oauth/portal") else {
            logger.error("AdminPortal: invalid baseUrl=\(fronteggAuth.baseUrl)")
            return
        }
        let store = webView.configuration.websiteDataStore.httpCookieStore

        // 1. Drive silentAuthorize so the server sets fresh fe_refresh_* + fe_device_*
        //    cookies on HTTPCookieStorage.shared (URLSession's cookie jar).
        if let refreshToken = fronteggAuth.refreshToken {
            do {
                logger.info("AdminPortal: calling silentAuthorize to obtain session cookies")
                _ = try await fronteggAuth.api.silentAuthorize(refreshToken: refreshToken)
                logger.info("AdminPortal: silentAuthorize returned successfully")
            } catch {
                logger.warning("AdminPortal: silentAuthorize failed (\(error.localizedDescription)) — falling back to direct injection")
            }
        } else {
            logger.warning("AdminPortal: no refresh token available — portal will likely redirect to login")
        }

        // 2. Mirror every cookie on the base host from HTTPCookieStorage.shared
        //    into the WebView's WKHTTPCookieStore.
        let sessionCookies = HTTPCookieStorage.shared.cookies(for: baseUrl) ?? []
        logger.info("AdminPortal: mirroring \(sessionCookies.count) cookies into WKHTTPCookieStore")
        for cookie in sessionCookies {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) { cont.resume() }
            }
        }

        // 3. Defensive fallback: if step 1 produced no fe_refresh_* cookie,
        //    synthesize one from the SDK's stored refresh token.
        if let refreshToken = fronteggAuth.refreshToken,
           let host = baseUrl.host,
           !sessionCookies.contains(where: { $0.name.hasPrefix("fe_refresh_") }) {
            let name = AdminPortalWebView.cookieName(for: fronteggAuth.clientId)
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: refreshToken,
                .domain: host,
                .path: "/",
                .secure: true,
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 30),
            ]
            if let cookie = HTTPCookie(properties: props) {
                logger.info("AdminPortal: synthesizing fallback \(name) cookie")
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    store.setCookie(cookie) { cont.resume() }
                }
            }
        }

        // 4. Load the portal.
        logger.info("AdminPortal: loading \(portalUrl.absoluteString)")
        webView.load(URLRequest(url: portalUrl))
    }

    /// Build the `fe_refresh_*` cookie name the same way `Api.swift` does
    /// (clientId with the first dash removed).
    private static func cookieName(for clientId: String) -> String {
        var clientIdWithoutFirstDash = clientId
        if let firstDashIndex = clientIdWithoutFirstDash.firstIndex(of: "-") {
            clientIdWithoutFirstDash.remove(at: firstDashIndex)
        }
        return "fe_refresh_\(clientIdWithoutFirstDash)"
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = getLogger("AdminPortalWebView")
        private let onNavigationFailure: ((URL?) -> Void)?
        private var didReportFailure = false

        init(onNavigationFailure: ((URL?) -> Void)?) {
            self.onNavigationFailure = onNavigationFailure
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                logger.trace("AdminPortal: navigation → \(url.absoluteString)")
                if !didReportFailure, isLoginRedirect(url: url) {
                    didReportFailure = true
                    logger.warning("AdminPortal: detected login redirect — auth bridging failed at \(url.absoluteString)")
                    onNavigationFailure?(url)
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("AdminPortal: didFail \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("AdminPortal: didFailProvisionalNavigation \(error.localizedDescription)")
        }

        private func isLoginRedirect(url: URL) -> Bool {
            let path = url.path.lowercased()
            // The portal itself lives under /oauth/portal — anything else under
            // /oauth/authorize or /oauth/account/login means we got bounced.
            if path.hasPrefix("/oauth/portal") { return false }
            return path.hasPrefix("/oauth/authorize") || path.contains("/oauth/account/login")
        }
    }
}
