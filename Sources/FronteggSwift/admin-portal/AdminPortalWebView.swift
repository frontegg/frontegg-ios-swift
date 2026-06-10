//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  Native admin portal via embedded WKWebView. The portal opens without a
//  second login by handing the SDK's OAuth tokens to the hosted admin-box app
//  through a JS bridge (AdminPortalBridge), rather than relying on the WebView
//  cookie jar.
//
//  Why the bridge instead of cookies: the Frontegg refresh cookie is single-use
//  and rotates on every read, and in hosted-login mode it lives in the system
//  browser where the app can't reach it at all. So seeding the WebView cookie
//  jar is either stale (embedded) or impossible (hosted). Instead the portal
//  detects the SDK via window.FronteggNativeBridgeFunctions and calls
//  getTokens(), and native (the single source of truth) returns the current
//  access/refresh token. See AdminPortalBridge for the full contract.
//

import Foundation
import WebKit
import SwiftUI

@available(iOS 14.0, *)
struct AdminPortalWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    private let fronteggAuth: FronteggAuth
    private let onClose: (() -> Void)?
    private let logger = getLogger("AdminPortalWebView")

    init(onClose: (() -> Void)? = nil) {
        self.fronteggAuth = FronteggAuth.shared
        self.onClose = onClose
    }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        // Share the SDK's process pool and persistent data store so cookies
        // are visible across the SDK's webviews and this one.
        conf.processPool = WebViewShared.processPool
        conf.websiteDataStore = .default()

        // Request the desktop layout so the portal renders the persistent
        // sidebar + content side-by-side instead of collapsing into a mobile
        // drawer.
        let prefs = WKWebpagePreferences()
        prefs.preferredContentMode = .desktop
        conf.defaultWebpagePreferences = prefs

        // Force the viewport meta to a desktop width before the page's CSS
        // and JS evaluate. Material-UI's responsive hooks read
        // window.innerWidth, so this is what actually flips the breakpoint
        // from mobile to desktop. Runs at documentStart on the main frame
        // only.
        let viewportOverride = """
        (function() {
            var setViewport = function() {
                var existing = document.querySelector('meta[name="viewport"]');
                if (existing) { existing.parentNode.removeChild(existing); }
                var meta = document.createElement('meta');
                meta.setAttribute('name', 'viewport');
                meta.setAttribute('content', 'width=1024, user-scalable=yes, minimum-scale=0.3, maximum-scale=3');
                (document.head || document.documentElement).appendChild(meta);
            };
            setViewport();
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', setViewport);
            }
        })();
        """
        let viewportScript = WKUserScript(source: viewportOverride, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        conf.userContentController.addUserScript(viewportScript)

        // JS <-> native bridge: lets the hosted admin-box app pull the SDK's
        // OAuth tokens (and request authorize / close) instead of depending on
        // the WebView cookie jar. Registered under the same handler name as the
        // login-box bridge so FronteggNativeModule detects it, and the
        // capability map is injected at documentStart so isAvailable() passes.
        let bridge = AdminPortalBridge(onClose: onClose)
        conf.userContentController.add(bridge, name: AdminPortalBridge.handlerName)
        let bridgeFunctions = WKUserScript(
            source: "window.FronteggNativeBridgeFunctions = \(AdminPortalBridge.capabilitiesJSON);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        conf.userContentController.addUserScript(bridgeFunctions)
        context.coordinator.bridge = bridge

        let webView = WKWebView(frame: .zero, configuration: conf)
        bridge.webView = webView
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Desktop user-agent — backstop for any UA-sniffing branches in the
        // portal's responsive logic.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.isOpaque = true
        webView.backgroundColor = .secondarySystemBackground
        webView.scrollView.backgroundColor = .secondarySystemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.scrollView.bouncesZoom = true

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
        Coordinator(onClose: onClose)
    }

    /// SwiftUI teardown hook — fires when the representable is removed (sheet
    /// dismissed by swipe, programmatic dismiss, parent navigation, etc.).
    /// This is the reliable place to reclaim the token, since the portal's
    /// `window.close()` (→ webViewDidClose) only covers the in-page X button.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // DIAGNOSTIC: no reclaim — pure no-op build.
    }

    /// Builds the admin portal URL. Pinning the application context via
    /// `?appId=<applicationId>` is required for multi-app workspaces — without
    /// it the portal renders "Application not found". Single-app workspaces
    /// pass `nil`/empty and get the bare URL.
    internal static func portalURL(baseUrl: String, applicationId: String?) -> URL? {
        var components = URLComponents(string: "\(baseUrl)/oauth/portal")
        if let applicationId = applicationId, !applicationId.isEmpty {
            components?.queryItems = [URLQueryItem(name: "appId", value: applicationId)]
        }
        return components?.url
    }

    @MainActor
    private func loadPortal(webView: WKWebView) async {
        guard let portalUrl = AdminPortalWebView.portalURL(
            baseUrl: fronteggAuth.baseUrl,
            applicationId: fronteggAuth.applicationId
        ) else {
            logger.error("AdminPortal: invalid baseUrl=\(fronteggAuth.baseUrl)")
            return
        }

        // The portal authenticates via the native token bridge
        // (AdminPortalBridge.getTokens), not the WebView cookie jar, so we just
        // load the URL — no cookie seeding or rotation handling needed.
        logger.info("AdminPortal: loading \(portalUrl.absoluteString)")
        webView.load(URLRequest(url: portalUrl))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let logger = getLogger("AdminPortalWebView")
        private let onClose: (() -> Void)?
        /// Retains the JS<->native bridge for the lifetime of the WebView.
        var bridge: AdminPortalBridge?

        init(onClose: (() -> Void)?) {
            self.onClose = onClose
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if let url = navigationAction.request.url {
                logger.trace("AdminPortal: navigation → \(url.absoluteString)")
            }
            preferences.preferredContentMode = .desktop
            decisionHandler(.allow, preferences)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let reapply = """
            (function() {
                var existing = document.querySelector('meta[name="viewport"]');
                var desired = 'width=1024, user-scalable=yes, minimum-scale=0.3, maximum-scale=3';
                if (existing && existing.getAttribute('content') === desired) { return; }
                if (existing) { existing.parentNode.removeChild(existing); }
                var meta = document.createElement('meta');
                meta.setAttribute('name', 'viewport');
                meta.setAttribute('content', desired);
                (document.head || document.documentElement).appendChild(meta);
            })();
            """
            webView.evaluateJavaScript(reapply, completionHandler: nil)
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

        // The portal's X button calls window.close() — reclaim the token, then
        // dismiss.
        func webViewDidClose(_ webView: WKWebView) {
            logger.info("AdminPortal: webViewDidClose — dismissing")
            onClose?()
        }
    }
}
