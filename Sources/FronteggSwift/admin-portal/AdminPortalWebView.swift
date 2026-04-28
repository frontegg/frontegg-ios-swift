//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  POC: native admin portal via embedded WKWebView.
//
//  Strategy (per current scope): do NOT inject or modify the mobile SDK's
//  session into the WebView. Just open `${baseUrl}/oauth/portal` in a
//  WKWebView that shares the SDK's persistent cookie store
//  (`WKWebsiteDataStore.default()` + `WebViewShared.processPool`). Any web-
//  style cookies (`fe_refresh_*`, `fe_device_*`) the user already has from
//  prior in-app web flows are reused as-is. If they're missing or stale,
//  the portal renders its own login form — the user logs in once and the
//  resulting cookies persist for next time.
//
//  Bridging the iOS-app refresh token into the portal's cookie session is
//  a follow-up; it requires server-side help we don't have here.
//

import Foundation
import WebKit
import SwiftUI

@available(iOS 14.0, *)
struct AdminPortalWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    private let fronteggAuth: FronteggAuth
    private let logger = getLogger("AdminPortalWebView")

    init() {
        self.fronteggAuth = FronteggAuth.shared
    }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        // Share the SDK's process pool and persistent data store so any
        // cookies the SDK's login webview wrote are visible here.
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
            await loadPortal(webView: webView)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    private func loadPortal(webView: WKWebView) async {
        guard let portalUrl = URL(string: "\(fronteggAuth.baseUrl)/oauth/portal") else {
            logger.error("AdminPortal: invalid baseUrl=\(fronteggAuth.baseUrl)")
            return
        }

        // Snapshot existing cookies for visibility only — we do not modify them.
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let existing = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        if let host = URL(string: fronteggAuth.baseUrl)?.host {
            let scoped = existing.filter { c in
                let domain = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                return host == domain || host.hasSuffix("." + domain)
            }
            logger.info("AdminPortal: WKHTTPCookieStore total=\(existing.count) scopedToHost=\(scoped.count)")
            for c in scoped {
                logger.info("AdminPortal:   \(c.name) domain=\(c.domain) path=\(c.path) secure=\(c.isSecure)")
            }
        }

        logger.info("AdminPortal: loading \(portalUrl.absoluteString)")
        webView.load(URLRequest(url: portalUrl))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = getLogger("AdminPortalWebView")

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                logger.trace("AdminPortal: navigation → \(url.absoluteString)")
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let response = navigationResponse.response as? HTTPURLResponse {
                logger.trace("AdminPortal: response \(response.statusCode) \(response.url?.absoluteString ?? "?")")
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("AdminPortal: didFail \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("AdminPortal: didFailProvisionalNavigation \(error.localizedDescription)")
        }
    }
}
