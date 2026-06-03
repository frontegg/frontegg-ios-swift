//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  Native admin portal via embedded WKWebView, using a "baton handoff" of the
//  refresh-token rotation chain so the portal opens without a second login —
//  for ALL login methods and both embedded/hosted modes.
//
//  Background (proven against the auth backend): the Frontegg refresh token is
//  single-use and rotates on every read with no grace window. The SDK's
//  background refresh loop and this portal WebView both need that one
//  credential, so they cannot consume it concurrently without invalidating
//  each other. See FronteggAuth+AdminPortalSession for the full rationale.
//
//  Flow:
//    open  → fronteggAuth.beginAdminPortalSession() pauses the SDK loop and
//            returns the current refresh token. We clear any stale fe_refresh_*
//            cookie from the WebView store and write the current token, then
//            load /oauth/portal. The portal's own silent-authorize on mount
//            recognizes the session (no second login) and from then on the
//            portal is the sole consumer that rotates the token.
//    close → we read the latest fe_refresh_* cookie value back from the WebView
//            store (the portal's most recent rotation) and hand it to
//            fronteggAuth.endAdminPortalSession(...), which makes the SDK adopt
//            it and resumes the loop.
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

        let webView = WKWebView(frame: .zero, configuration: conf)
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

    /// The cookie name the Frontegg auth backend reads for the refresh-token
    /// session. Strips ONLY the first dash of clientId — must match
    /// `Api.swift`'s `cookieName` exactly (the format the SDK's own HTTP client
    /// sends on every refresh / logout call). Earlier bridge attempts that
    /// stripped all dashes or used applicationId produced a name the server
    /// didn't recognize.
    internal static func refreshCookieName(clientId: String) -> String {
        var stripped = clientId
        if let firstDash = stripped.firstIndex(of: "-") {
            stripped.remove(at: firstDash)
        }
        return "fe_refresh_\(stripped)"
    }

    /// Build the `HTTPCookie` that seeds the portal WebView with the SDK's
    /// current refresh token. Returns nil if there's no token or the baseUrl
    /// is malformed (caller then loads the portal without seeding — it renders
    /// its own login).
    internal static func makeRefreshCookie(
        refreshToken: String?,
        baseUrl: String,
        clientId: String
    ) -> HTTPCookie? {
        guard let refreshToken = refreshToken, !refreshToken.isEmpty else { return nil }
        guard let url = URL(string: baseUrl), let host = url.host else { return nil }
        let isSecure = url.scheme?.lowercased() == "https"
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: refreshCookieName(clientId: clientId),
            .value: refreshToken,
            .domain: host,
            .path: "/",
        ]
        if isSecure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
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

        let store = webView.configuration.websiteDataStore.httpCookieStore

        // DIAGNOSTIC PASS (no-op): do NOT clear/seed/refresh. Just log what's in
        // WKHTTPCookieStore at portal-open and what the SDK has stored, so we can
        // see — on a real device — whether the login's cookie-family fe_refresh
        // is present + fresh, or stale (rotated away by the SDK's URLSession-based
        // refresh, which can't write WKHTTPCookieStore). Then load the portal
        // exactly as the original pass-through did.
        let expectedName = AdminPortalWebView.refreshCookieName(clientId: fronteggAuth.clientId)
        let sdkTok = fronteggAuth.refreshToken ?? ""
        let sdkPrefix = sdkTok.isEmpty ? "<none>" : (sdkTok.count > 8 ? "\(sdkTok.prefix(8))... len=\(sdkTok.count)" : "<short>")
        logger.info("AdminPortal[DIAG]: expectedCookieName=\(expectedName) SDK.refreshToken=\(sdkPrefix)")

        let existing = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        if let host = URL(string: fronteggAuth.baseUrl)?.host {
            let fe = existing.filter { ($0.name.hasPrefix("fe_refresh_") || $0.name.hasPrefix("fe_device_")) }
                .filter { c in
                    let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                    return host == d || host.hasSuffix("." + d)
                }
            logger.info("AdminPortal[DIAG]: WKHTTPCookieStore fe_* scoped to \(host): \(fe.count)")
            for c in fe {
                let vp = c.value.count > 8 ? "\(c.value.prefix(8))... len=\(c.value.count)" : "<short>"
                let matchesSDK = (c.name == expectedName && c.value == sdkTok) ? " MATCHES-SDK" : ""
                logger.info("AdminPortal[DIAG]:   \(c.name) value=\(vp) domain=\(c.domain) secure=\(c.isSecure)\(matchesSDK)")
            }
        }

        logger.info("AdminPortal: loading \(portalUrl.absoluteString)")
        webView.load(URLRequest(url: portalUrl))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let logger = getLogger("AdminPortalWebView")
        private let onClose: (() -> Void)?

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
