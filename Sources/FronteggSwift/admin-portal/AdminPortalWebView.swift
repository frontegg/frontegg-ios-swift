//
//  AdminPortalWebView.swift
//  FronteggSwift
//
//  POC: native admin portal via embedded WKWebView with shared session.
//
//  Bridges the SDK's session into the WebView before loading
//  `${baseUrl}/oauth/portal` so the user never sees a re-login prompt.
//
//  iOS SDK auth state lives in URLSession's cookie jar + Keychain. WKWebView
//  has its own cookie jar (`WKHTTPCookieStore`) that does NOT share with
//  URLSession. Bridging strategy:
//
//    1. Parse `Set-Cookie` directly from the response of `silentAuthorize`
//       and inject every returned cookie into `WKHTTPCookieStore`.
//    2. Mirror anything that landed in `HTTPCookieStorage.shared` into the
//       WebView store.
//    3. As a defensive fallback, synthesize a `fe_refresh_*` cookie from the
//       SDK's stored refresh token.
//    4. Load the portal AND set a Cookie header on the initial URLRequest
//       so the very first request is authenticated even if step 1–3 missed.
//
//  Verbose logging at every step — flip the failure into something
//  diagnosable rather than a silent redirect to /oauth/account/login.
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
        let cookieNameValue = AdminPortalWebView.cookieName(for: fronteggAuth.clientId)

        logger.info("AdminPortal: clientId=\(fronteggAuth.clientId) baseUrl=\(fronteggAuth.baseUrl) refreshTokenPresent=\(fronteggAuth.refreshToken != nil) accessTokenPresent=\(fronteggAuth.accessToken != nil)")

        // --- 1. Drive silentAuthorize and harvest its Set-Cookie response ---
        if let refreshToken = fronteggAuth.refreshToken {
            do {
                logger.info("AdminPortal: calling silentAuthorize")
                let (_, response) = try await fronteggAuth.api.silentAuthorize(refreshToken: refreshToken)
                if let httpResponse = response as? HTTPURLResponse {
                    logger.info("AdminPortal: silentAuthorize status=\(httpResponse.statusCode)")
                    let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") ?? ""
                    logger.info("AdminPortal: silentAuthorize Set-Cookie length=\(setCookie.count)")
                    if !setCookie.isEmpty,
                       let headers = httpResponse.allHeaderFields as? [String: String] {
                        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headers, for: baseUrl)
                        logger.info("AdminPortal: parsed \(parsed.count) cookies from silentAuthorize Set-Cookie")
                        for cookie in parsed {
                            logger.info("AdminPortal:   set \(cookie.name) domain=\(cookie.domain) path=\(cookie.path) secure=\(cookie.isSecure)")
                            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                                store.setCookie(cookie) { cont.resume() }
                            }
                        }
                    }
                }
            } catch {
                logger.warning("AdminPortal: silentAuthorize threw: \(error.localizedDescription)")
            }
        }

        // --- 2. Mirror HTTPCookieStorage.shared (full dump) ---
        let urlSessionCookies = HTTPCookieStorage.shared.cookies ?? []
        let scopedCookies = HTTPCookieStorage.shared.cookies(for: baseUrl) ?? []
        logger.info("AdminPortal: HTTPCookieStorage.shared total=\(urlSessionCookies.count) forBaseUrl=\(scopedCookies.count)")
        for cookie in urlSessionCookies {
            if cookie.domain.contains(baseUrl.host ?? "___never___") || (baseUrl.host?.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) ?? false) {
                logger.info("AdminPortal:   mirror \(cookie.name) domain=\(cookie.domain) path=\(cookie.path)")
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    store.setCookie(cookie) { cont.resume() }
                }
            }
        }

        // --- 3. Defensive direct synthesis of fe_refresh_* if not yet present ---
        let existingCookies = await currentCookies(in: store)
        let alreadyHasRefresh = existingCookies.contains { $0.name == cookieNameValue }
        if !alreadyHasRefresh,
           let refreshToken = fronteggAuth.refreshToken,
           let host = baseUrl.host {
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: cookieNameValue,
                .value: refreshToken,
                .domain: host,
                .path: "/",
                .secure: true,
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 30),
            ]
            if let cookie = HTTPCookie(properties: props) {
                logger.info("AdminPortal: synthesizing fallback \(cookieNameValue)")
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    store.setCookie(cookie) { cont.resume() }
                }
            }
        }

        // Snapshot the WKHTTPCookieStore right before load.
        let preLoadCookies = await currentCookies(in: store)
        let scopedToBase = preLoadCookies.filter { c in
            guard let host = baseUrl.host else { return false }
            let domain = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        logger.info("AdminPortal: WKHTTPCookieStore pre-load total=\(preLoadCookies.count) scopedToBase=\(scopedToBase.count)")
        for c in scopedToBase {
            logger.info("AdminPortal:   wkstore \(c.name) domain=\(c.domain) path=\(c.path) secure=\(c.isSecure)")
        }

        // --- 4. Load portal + send Cookie header on the initial request as belt-and-suspenders ---
        var request = URLRequest(url: portalUrl)
        if let refreshToken = fronteggAuth.refreshToken {
            request.setValue("\(cookieNameValue)=\(refreshToken)", forHTTPHeaderField: "Cookie")
            logger.info("AdminPortal: setting initial Cookie header (\(cookieNameValue)=…)")
        }
        logger.info("AdminPortal: loading \(portalUrl.absoluteString)")
        webView.load(request)
    }

    private func currentCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
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
                    logger.warning("AdminPortal: login redirect — auth bridging failed at \(url.absoluteString)")
                    onNavigationFailure?(url)
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let response = navigationResponse.response as? HTTPURLResponse {
                let setCookie = response.value(forHTTPHeaderField: "Set-Cookie") ?? ""
                logger.trace("AdminPortal: response \(response.statusCode) \(response.url?.absoluteString ?? "?") setCookieLen=\(setCookie.count)")
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
            if path.hasPrefix("/oauth/portal") { return false }
            return path.hasPrefix("/oauth/authorize") || path.contains("/oauth/account/login")
        }
    }
}
