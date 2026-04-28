//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  POC: native admin portal via embedded WKWebView with shared session.
//
//  Loads the hosted admin portal at `${baseUrl}/oauth/portal` inside a WKWebView
//  that shares its cookie store and process pool with the SDK's login webview.
//  The user's existing refresh-token cookie is also injected defensively before
//  load, so the portal authenticates without a re-login regardless of whether
//  the original sign-in happened via embedded mode or `ASWebAuthenticationSession`.
//

import Foundation
import WebKit
import SwiftUI

@available(iOS 14.0, *)
struct AdminPortalWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    private let fronteggAuth: FronteggAuth
    private let onNavigationFailure: ((URL?) -> Void)?

    init(onNavigationFailure: ((URL?) -> Void)? = nil) {
        self.fronteggAuth = FronteggAuth.shared
        self.onNavigationFailure = onNavigationFailure
    }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        // Share the SDK's process pool and persistent data store so that any
        // session cookies the login webview wrote are visible here.
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

        let portalUrlString = "\(fronteggAuth.baseUrl)/oauth/portal"
        guard let portalUrl = URL(string: portalUrlString) else {
            return webView
        }

        injectRefreshCookieIfAvailable(into: webView) {
            webView.load(URLRequest(url: portalUrl))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationFailure: onNavigationFailure)
    }

    // MARK: - Cookie injection

    /// Build the `fe_refresh_*` cookie name the same way `Api.swift` does
    /// (clientId with the first dash removed).
    private static func cookieName(for clientId: String) -> String {
        var clientIdWithoutFirstDash = clientId
        if let firstDashIndex = clientIdWithoutFirstDash.firstIndex(of: "-") {
            clientIdWithoutFirstDash.remove(at: firstDashIndex)
        }
        return "fe_refresh_\(clientIdWithoutFirstDash)"
    }

    private func injectRefreshCookieIfAvailable(into webView: WKWebView,
                                                completion: @escaping () -> Void) {
        guard
            let refreshToken = fronteggAuth.refreshToken,
            let host = URL(string: fronteggAuth.baseUrl)?.host
        else {
            completion()
            return
        }

        let cookieName = AdminPortalWebView.cookieName(for: fronteggAuth.clientId)
        let cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .name: cookieName,
            .value: refreshToken,
            .domain: host,
            .path: "/",
            .secure: true,
            .expires: Date().addingTimeInterval(60 * 60 * 24 * 30),
        ]

        guard let cookie = HTTPCookie(properties: cookieProperties) else {
            completion()
            return
        }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.setCookie(cookie) {
            completion()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigationFailure: ((URL?) -> Void)?

        init(onNavigationFailure: ((URL?) -> Void)?) {
            self.onNavigationFailure = onNavigationFailure
        }

        /// If the portal redirects the user to a login route, auth bridging failed —
        /// surface that to the host view so it can show an error or dismiss.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               isLoginRedirect(url: url) {
                onNavigationFailure?(url)
            }
            decisionHandler(.allow)
        }

        private func isLoginRedirect(url: URL) -> Bool {
            let path = url.path.lowercased()
            return path.contains("/oauth/account/login") || path.contains("/oauth/authorize")
        }
    }
}
