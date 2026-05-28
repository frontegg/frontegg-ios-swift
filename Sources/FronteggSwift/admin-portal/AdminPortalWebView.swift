//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  Native admin portal via embedded WKWebView.
//
//  ⚠️ DIAGNOSTIC BUILD — the cookie-bridge strategy is intentionally minimal here.
//  Earlier attempts (synthetic-cookie bridge, silent-authorize-first) both failed
//  for hosted-login users because the SDK's stored refresh token (issued by
//  /oauth/token code exchange) and the cookie-auth `fe_refresh_*` value the
//  portal expects are different identifier families on the auth backend. Until
//  we have evidence of what cookies actually live in WKHTTPCookieStore at
//  portal-open time across the various login flows, this class just:
//
//    1. snapshots the existing fe_refresh_* / fe_device_* cookies for the host
//       (logging name + first 8 chars of value + domain/path/secure flags),
//    2. logs the SDK's stored refresh-token prefix and the cookie name it would
//       map to (so we can correlate against the snapshot), and
//    3. loads /oauth/portal as-is.
//
//  No cookie writes, no deletes, no silent-authorize. Whatever the login
//  WebView left behind stays.
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
        // Share the SDK's process pool and persistent data store so any
        // cookies the SDK's login webview wrote are visible here.
        conf.processPool = WebViewShared.processPool
        conf.websiteDataStore = .default()

        // Request the desktop layout so the portal renders the persistent
        // sidebar + content side-by-side (matches what the PM sees in
        // Chrome) instead of collapsing into a mobile drawer.
        let prefs = WKWebpagePreferences()
        prefs.preferredContentMode = .desktop
        conf.defaultWebpagePreferences = prefs

        // Force the viewport meta to a desktop width before the page's CSS
        // and JS evaluate. Material-UI's responsive hooks read
        // window.innerWidth, so this is what actually flips the breakpoint
        // from mobile to desktop. Runs at documentStart on the main frame
        // only — overriding inside iframes (e.g. embedded social-login
        // widgets) was causing mid-page re-layouts that disrupted the
        // zoom-and-pan state.
        //
        // initial-scale lets WebKit auto-fit on first paint; minimum/maximum
        // clamp pinch zoom to a sane range so panning a zoomed page stays
        // smooth instead of going extreme.
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
        // Opaque + solid background so nothing from the host view can bleed
        // through any seam between the webview and the sheet edges. Use the
        // *secondary* system background (light grey in light mode, near-black
        // in dark mode) because that's what Frontegg's admin-portal body
        // chrome uses — without the match, horizontal over-scroll bouncing
        // flashes a colour that doesn't belong to the page.
        webView.isOpaque = true
        webView.backgroundColor = .secondarySystemBackground
        webView.scrollView.backgroundColor = .secondarySystemBackground
        // Disable the auto safe-area inset that WKWebView applies, so the
        // page content extends edge-to-edge (no grey strip above the home
        // indicator).
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Explicit defaults for pinch-zoom-and-pan — when the viewport is
        // wider than the screen and the user zooms in, the scroll view
        // needs both bouncing and bouncesZoom for the rubber-band gesture
        // to surface (some iOS versions disable bounces on certain
        // contentInsetAdjustmentBehavior combos).
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

    /// The cookie name format the Frontegg auth backend reads at
    /// `/frontegg/oauth/authorize/silent`. Strips ONLY the first dash of
    /// clientId — must match `Api.swift`'s `cookieName` exactly.
    ///
    /// Exposed (internal) for diagnostic logging in [loadPortal] (so we can
    /// log the EXPECTED cookie name alongside what actually lives in
    /// WKHTTPCookieStore) and for tests pinning the format.
    internal static func refreshCookieName(clientId: String) -> String {
        var stripped = clientId
        if let firstDash = stripped.firstIndex(of: "-") {
            stripped.remove(at: firstDash)
        }
        return "fe_refresh_\(stripped)"
    }

    /// Safe redacted prefix of a (potentially sensitive) token value, for log
    /// correlation only. Returns the first 8 chars + `...` + length. NEVER
    /// returns the full value.
    private static func valuePrefix(_ s: String) -> String {
        if s.isEmpty { return "<empty>" }
        if s.count <= 8 { return "<short len=\(s.count)>" }
        let prefix = s.prefix(8)
        return "\(prefix)... len=\(s.count)"
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

        // DIAGNOSTIC PASS — log what's already in the cookie store at
        // portal-open time, plus what cookie name+value the SDK would
        // synthesize if we wanted to bridge. We deliberately do NOT
        // write/delete anything; this is just observation.
        //
        // For each fe_refresh_* / fe_device_* cookie scoped to this host
        // we log name, domain (host-only vs domain cookie), path, secure,
        // and a redacted first-8-chars-of-value. Comparing those prefixes
        // against the SDK's stored refresh-token prefix tells us whether
        // the WebView's cookies match the SDK's session.
        let expectedCookieName = AdminPortalWebView.refreshCookieName(clientId: fronteggAuth.clientId)
        let sdkTokenPrefix = AdminPortalWebView.valuePrefix(fronteggAuth.refreshToken ?? "")
        logger.info("AdminPortal: SDK expects cookie name=\(expectedCookieName), SDK.refreshToken=\(sdkTokenPrefix)")

        let existing = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        if let host = URL(string: fronteggAuth.baseUrl)?.host {
            let scoped = existing.filter { c in
                let domain = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                return host == domain || host.hasSuffix("." + domain)
            }
            let feScoped = scoped.filter { $0.name.hasPrefix("fe_refresh_") || $0.name.hasPrefix("fe_device_") }
            logger.info("AdminPortal: WKHTTPCookieStore total=\(existing.count) scopedToHost=\(scoped.count) feScopedToHost=\(feScoped.count)")
            for c in feScoped {
                let prefix = AdminPortalWebView.valuePrefix(c.value)
                let exp = c.expiresDate.map { "\($0)" } ?? "session"
                logger.info("AdminPortal:   \(c.name) value=\(prefix) domain=\(c.domain) path=\(c.path) secure=\(c.isSecure) httpOnly=\(c.isHTTPOnly) expires=\(exp)")
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

        /// iOS 13+ per-navigation preferences callback. Setting
        /// `preferredContentMode = .desktop` here (in addition to the
        /// `defaultWebpagePreferences` we set on the configuration) is what
        /// makes desktop layout stick across in-page back/forward and
        /// BFCache restorations — without this, a few in-page navigations
        /// can flip the layout back to mobile.
        ///
        /// When this method is implemented, the simpler 3-arg variant is
        /// not called, so navigation-trace logging happens here too.
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

        /// Re-apply the desktop viewport on every finished navigation as a
        /// safety net — BFCache or fast same-document navigations can skip
        /// the documentStart user script, leaving the page on whatever
        /// viewport the document originally declared.
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

        // The portal's X button calls window.close() — bridge that to SwiftUI dismiss.
        func webViewDidClose(_ webView: WKWebView) {
            logger.info("AdminPortal: webViewDidClose — dismissing")
            onClose?()
        }
    }
}
