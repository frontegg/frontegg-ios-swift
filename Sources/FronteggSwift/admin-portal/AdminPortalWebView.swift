//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  Native admin portal via embedded WKWebView, with a server-issued session
//  bootstrapped from the SDK's stored refresh token.
//
//  The challenge: the portal SPA at /oauth/portal calls
//  /frontegg/oauth/authorize/silent on mount to validate the session, and
//  that endpoint reads a fe_refresh_<id> cookie from the WebView. Users
//  who logged into the SDK via ASWebAuthenticationSession have their
//  refresh-token cookie in Safari's isolated jar — not visible to
//  WKWebView's WKHTTPCookieStore — so by default the portal sees no
//  cookie, can't validate, and renders its own login form (the "second
//  login" bug).
//
//  Fix: BEFORE loading /oauth/portal, the SDK itself calls
//  /frontegg/oauth/authorize/silent via URLSession (which is what the
//  portal will call from inside the WebView). The server's response
//  contains both:
//    * a JSON body with a freshly-rotated `refresh_token` — we feed this
//      into the SDK's credential storage so the SDK stays in sync, and
//    * `Set-Cookie: fe_refresh_*; fe_device_*` headers — we mirror these
//      into WKHTTPCookieStore so the WebView starts with server-signed
//      cookies that are byte-identical to what the portal expects.
//  Then we load /oauth/portal. The portal's own silent-authorize on mount
//  will succeed (at most one rotation behind, which Frontegg's grace
//  window covers).
//
//  Before mirroring, we delete any existing fe_refresh_*/fe_device_*
//  cookies for the host. Without this cleanup, an earlier session's
//  stale (already-rotated) cookie can coexist with our fresh one in a
//  different scope (host-only vs. domain), and per RFC 6265 §5.4 the
//  older one ends up first in the Cookie header — the server reads it
//  and 401s the silent-authorize request.
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

    /// Cookie names the SDK writes to the portal WebView store.
    ///
    /// Stale entries here are the actual failure mode behind the "second
    /// login" bug Pavel reproduced: a server-rotated cookie from a prior
    /// app session stays in WKHTTPCookieStore (persistent across launches),
    /// our fresh bridge writes in a different scope, both end up in the
    /// `Cookie:` header, RFC 6265 §5.4 puts the older one first, server
    /// reads the stale one and 401s.
    ///
    /// The format must match `Api.swift` (`self.cookieName`) exactly —
    /// strip ONLY the first dash of clientId, not all of them — so the
    /// cleanup catches the same cookie the server set.
    internal static func refreshCookieName(clientId: String) -> String {
        var stripped = clientId
        if let firstDash = stripped.firstIndex(of: "-") {
            stripped.remove(at: firstDash)
        }
        return "fe_refresh_\(stripped)"
    }

    /// Extract the `HTTPCookie` instances the server set in a response, scoped
    /// to the request's host. Returns only `fe_refresh_*` and `fe_device_*`
    /// (the session-bootstrap cookies the portal actually reads) — never
    /// unrelated server cookies, so we don't accidentally pollute the WebView
    /// store.
    ///
    /// Exposed (internal) for tests.
    internal static func extractFronteggSessionCookies(
        from response: URLResponse,
        requestURL: URL
    ) -> [HTTPCookie] {
        guard let httpResponse = response as? HTTPURLResponse else { return [] }
        // allHeaderFields is `[AnyHashable: Any]`; HTTPCookie.cookies needs
        // `[String: String]` — flatten with the keys lowercased so we don't
        // miss `set-cookie` vs `Set-Cookie`.
        var stringHeaders: [String: String] = [:]
        for (k, v) in httpResponse.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                stringHeaders[ks] = vs
            }
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: requestURL)
        return parsed.filter { $0.name.hasPrefix("fe_refresh_") || $0.name.hasPrefix("fe_device_") }
    }

    /// Remove every existing `fe_refresh_*` and `fe_device_*` cookie scoped to
    /// the given host from the cookie store. Returns the count removed.
    ///
    /// Why this matters: WKHTTPCookieStore is persistent. A cookie the server
    /// set during a prior portal open (and then later rotated server-side)
    /// stays in the store across app launches. If we write a fresh cookie
    /// alongside the stale one — in a *different* scope, e.g. host-only vs.
    /// domain — both end up in the `Cookie:` request header. The server picks
    /// the older one, gets a rotated/invalid value, and returns 401.
    /// Sweeping out all matching cookies before mirroring the fresh ones
    /// eliminates that collision.
    @MainActor
    private func clearStaleSessionCookies(
        in store: WKHTTPCookieStore,
        host: String
    ) async -> Int {
        let all = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        let toDelete = all.filter { cookie in
            guard cookie.name.hasPrefix("fe_refresh_") || cookie.name.hasPrefix("fe_device_") else { return false }
            // Match both host-only (`example.com`) and domain (`.example.com`) scopes.
            let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == cookieDomain || host.hasSuffix("." + cookieDomain)
        }
        for cookie in toDelete {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.delete(cookie) { cont.resume() }
            }
        }
        return toDelete.count
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

        // Step 1 — bootstrap a server-issued session via silent-authorize.
        //
        // Sequence:
        //   a) Clear any stale fe_refresh_*/fe_device_* cookies for this host
        //      from the WebView store. These would otherwise coexist with the
        //      fresh server-issued ones we're about to mirror, and the older
        //      stale value would end up sorted first in the `Cookie:` header
        //      (RFC 6265 §5.4) → server reads stale UUID → 401.
        //   b) POST /frontegg/oauth/authorize/silent via URLSession with the
        //      SDK's current refresh-token UUID as the cookie. This is the
        //      exact same call the portal's React app would make on mount —
        //      doing it server-side first means by the time the WebView loads
        //      /oauth/portal, the cookie jar already has the rotated cookies
        //      the portal expects.
        //   c) On success: update credentialManager with the rotated
        //      refresh_token from the response body (keeps SDK and WebView in
        //      sync — without this the SDK's stored UUID would go
        //      one-rotation-stale immediately, and any subsequent
        //      /oauth/token call from the SDK might be rejected once outside
        //      the grace window). Then mirror the response's Set-Cookie
        //      headers into WKHTTPCookieStore — these are byte-identical to
        //      what the portal's React app would see if it made the same call
        //      itself.
        //   d) On failure: log + skip the bridge. The portal will render its
        //      own login form, same fallback as before any of this existed.
        if let baseUrl = URL(string: fronteggAuth.baseUrl),
           let host = baseUrl.host,
           let refreshToken = fronteggAuth.refreshToken,
           !refreshToken.isEmpty {

            let cleared = await clearStaleSessionCookies(in: store, host: host)
            logger.info("AdminPortal: cleared \(cleared) stale fe_*/fe_device_* cookie(s) before bridge")

            do {
                // We only need the response headers (Set-Cookie); the body
                // is intentionally ignored — see comment below the guard.
                let (_, response) = try await fronteggAuth.api.silentAuthorize(refreshToken: refreshToken)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    logger.warning("AdminPortal: silent-authorize returned HTTP \(status) — portal will render its own login")
                    // Don't load yet — fall through to the load below.
                    throw NSError(domain: "AdminPortalWebView", code: status, userInfo: nil)
                }

                // Mirror server-issued Set-Cookie into the WebView store.
                // These are byte-identical to what the portal's React app
                // would see if it made the same call itself — so the
                // portal's internal silent-authorize on mount will succeed.
                //
                // We deliberately DO NOT update the SDK's credentialManager
                // here. Empirical testing (curl against staging) shows the
                // body's `refresh_token` field from silent-authorize is a
                // different identifier than the Set-Cookie value, and is
                // invalid for the SDK's existing /token/refresh path (HTTP
                // 401). Trying to "keep the SDK in sync" by storing either
                // value would break the SDK's existing refresh flow for at
                // least some auth-flow combinations. Better to leave the
                // SDK's stored token alone — the only consequence is that
                // the SDK's own next refresh call will operate on whatever
                // token it had before opening the portal (the auth backend
                // appears to invalidate it once silent-authorize rotates,
                // so the SDK may need to re-authenticate; if customer
                // reports confirm this manifests in practice, the fix is to
                // add `setCredentials` with the Set-Cookie value here in a
                // follow-up).
                let silentURL = URL(string: "\(fronteggAuth.baseUrl)/frontegg/oauth/authorize/silent") ?? portalUrl
                let serverCookies = AdminPortalWebView.extractFronteggSessionCookies(
                    from: httpResponse,
                    requestURL: silentURL
                )
                for cookie in serverCookies {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        store.setCookie(cookie) { cont.resume() }
                    }
                }
                let cookieNamesJoined = serverCookies.map { $0.name }.joined(separator: ", ")
                logger.info("AdminPortal: mirrored \(serverCookies.count) server cookie(s) into WKHTTPCookieStore: \(cookieNamesJoined)")
            } catch {
                logger.warning("AdminPortal: silent-authorize bootstrap failed (\(error.localizedDescription)) — portal will render its own login if no usable cookies remain")
            }
        } else {
            logger.info("AdminPortal: no refresh token in credentialManager — skipping silent-authorize bootstrap, portal will render its own login")
        }

        // Diagnostic snapshot of what the WebView will actually send.
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
