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

    /// Builds the cookie name the Frontegg auth backend reads at `/oauth/portal`.
    ///
    /// Critical: this MUST match the format the SDK's HTTP client uses for the
    /// same cookie elsewhere — see `Api.swift` (`self.cookieName`), which sends
    /// `Cookie: fe_refresh_<id>=<refreshToken>` to the auth server in
    /// `refreshToken`, `logout`, and `silentAuthorize`. The server accepts that
    /// exact format with the raw JWT as the value, so writing the same name +
    /// value into WKHTTPCookieStore lets the portal recognize the session
    /// without any backend changes.
    ///
    /// Format: `fe_refresh_<clientId-with-FIRST-dash-removed>`. Note: only the
    /// first dash is removed, not all of them. The Frontegg Next.js SDK uses
    /// the same convention in `modifySetCookie` (which forwards real server-set
    /// cookies). Using `applicationId` here is wrong — the SDK's HTTP client
    /// always keys this cookie by `clientId`, including in multi-app workspaces.
    internal static func refreshCookieName(clientId: String) -> String {
        var stripped = clientId
        if let firstDash = stripped.firstIndex(of: "-") {
            stripped.remove(at: firstDash)
        }
        return "fe_refresh_\(stripped)"
    }

    /// Constructs the `HTTPCookie` that lets the embedded portal recognize the
    /// SDK's existing authenticated session.
    ///
    /// Returns nil when there is no refresh token to bridge (user not logged in)
    /// or when the base URL is malformed. In both cases the portal falls back
    /// to its own login form — the existing behavior before this bridge.
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
        if isSecure {
            properties[.secure] = "TRUE"
        }
        // Deliberately not setting `.sameSitePolicy`: the portal request is
        // same-origin to this cookie's host, so SameSite policy is irrelevant.
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

        // Bridge: write the SDK's refresh token into WKHTTPCookieStore as
        // `fe_refresh_<clientId>=<rawJWT>` BEFORE the WebView fetches
        // /oauth/portal. The Frontegg auth backend already accepts this exact
        // cookie format with the raw JWT value — see `Api.swift` cookieName
        // and the Cookie header it sends on every refresh / logout call. So
        // this is a pure client-side fix; no backend changes needed.
        //
        // Without this bridge, users who logged in via ASWebAuthenticationSession
        // (whose cookies live in Safari's isolated jar — never visible to
        // WKWebView) are forced to log in a second time to access the portal.
        if let bridgeCookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: fronteggAuth.refreshToken,
            baseUrl: fronteggAuth.baseUrl,
            clientId: fronteggAuth.clientId
        ) {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.setCookie(bridgeCookie) { cont.resume() }
            }
            logger.info("AdminPortal: bridged refresh cookie \(bridgeCookie.name) domain=\(bridgeCookie.domain)")
        } else {
            logger.info("AdminPortal: no refresh token to bridge — portal will use its own login if no existing web cookies are present")
        }

        // Snapshot existing cookies for visibility only — we do not modify them.
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
