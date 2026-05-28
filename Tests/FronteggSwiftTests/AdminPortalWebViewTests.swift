//
//  AdminPortalWebViewTests.swift
//  FronteggSwiftTests
//

import XCTest
import WebKit
@testable import FronteggSwift

@available(iOS 14.0, *)
final class AdminPortalWebViewTests: XCTestCase {

    // MARK: - portalURL(baseUrl:applicationId:)

    func test_portalURL_appendsAppIdQueryParam_whenApplicationIdPresent() {
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app-x4gr8g28fxr5.frontegg.com",
            applicationId: "910a4f81-788a-4184-8ad0-acf355afc66f"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://app-x4gr8g28fxr5.frontegg.com/oauth/portal?appId=910a4f81-788a-4184-8ad0-acf355afc66f"
        )
    }

    func test_portalURL_omitsAppIdQueryParam_whenApplicationIdNil() {
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app-x4gr8g28fxr5.frontegg.com",
            applicationId: nil
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://app-x4gr8g28fxr5.frontegg.com/oauth/portal"
        )
    }

    func test_portalURL_omitsAppIdQueryParam_whenApplicationIdEmpty() {
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app-x4gr8g28fxr5.frontegg.com",
            applicationId: ""
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://app-x4gr8g28fxr5.frontegg.com/oauth/portal"
        )
    }

    func test_portalURL_preservesBaseUrlPath_whenBaseUrlHasSubpath() {
        // Vanity-domain configurations sometimes route Frontegg under a path
        // prefix; the portal URL must inherit that prefix.
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://acme.com/auth",
            applicationId: nil
        )

        XCTAssertEqual(url?.absoluteString, "https://acme.com/auth/oauth/portal")
    }

    func test_portalURL_percentEncodesApplicationId_whenContainsReservedChars() {
        // Defensive — applicationIds are GUIDs in practice, but URLComponents
        // should still produce a valid URL if a configuration is exotic.
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app.frontegg.com",
            applicationId: "id with spaces"
        )

        XCTAssertNotNil(url)
        XCTAssertEqual(
            url?.query,
            "appId=id%20with%20spaces"
        )
    }

    // MARK: - refreshCookieName(clientId:)

    func test_refreshCookieName_stripsOnlyFirstDash_notAllDashes() {
        // CRITICAL: this format must match Api.swift's `self.cookieName`
        // (line 62-66 of Api.swift). The SDK's HTTP client sends
        // `Cookie: fe_refresh_<that-id>=<refreshToken>` to the auth server
        // on every refresh / logout call and the server accepts it. So
        // writing the same name + value into WKHTTPCookieStore is what
        // makes the portal recognize the session without backend changes.
        //
        // Earlier versions of this code removed ALL dashes — that produced
        // a cookie name the server didn't recognize, and the portal
        // bounced to login. This test pins the right behavior.
        let name = AdminPortalWebView.refreshCookieName(
            clientId: "b1c2d3e4-1234-5678-9abc-deadbeef0000"
        )
        XCTAssertEqual(name, "fe_refresh_b1c2d3e41234-5678-9abc-deadbeef0000",
                       "Must strip ONLY the first dash to match Api.swift cookieName format.")
        XCTAssertTrue(name.hasPrefix("fe_refresh_"))
        XCTAssertTrue(name.contains("-"), "Subsequent dashes must remain in the cookie name.")
    }

    func test_refreshCookieName_handlesClientIdWithNoDashes() {
        let name = AdminPortalWebView.refreshCookieName(clientId: "nodashesclient")
        XCTAssertEqual(name, "fe_refresh_nodashesclient")
    }

    // MARK: - makeRefreshCookie(refreshToken:baseUrl:clientId:)

    func test_makeRefreshCookie_returnsNil_whenRefreshTokenIsNil() {
        XCTAssertNil(AdminPortalWebView.makeRefreshCookie(
            refreshToken: nil,
            baseUrl: "https://app.frontegg.com",
            clientId: "abc-def"
        ))
    }

    func test_makeRefreshCookie_returnsNil_whenRefreshTokenIsEmpty() {
        XCTAssertNil(AdminPortalWebView.makeRefreshCookie(
            refreshToken: "",
            baseUrl: "https://app.frontegg.com",
            clientId: "abc-def"
        ))
    }

    func test_makeRefreshCookie_returnsNil_whenBaseUrlIsMalformed() {
        XCTAssertNil(AdminPortalWebView.makeRefreshCookie(
            refreshToken: "rt-jwt",
            baseUrl: "not a url",
            clientId: "abc-def"
        ))
    }

    func test_makeRefreshCookie_buildsHttpsCookie_withSecureFlag() {
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: "rt-jwt-value-abc",
            baseUrl: "https://app.frontegg.com",
            clientId: "b1c2d3e4-1234"
        )
        XCTAssertNotNil(cookie)
        XCTAssertEqual(cookie?.name, "fe_refresh_b1c2d3e41234",
                       "First dash stripped — matches Api.swift cookieName format.")
        XCTAssertEqual(cookie?.value, "rt-jwt-value-abc",
                       "Cookie value is the raw refresh token JWT, same as Api.swift sends.")
        XCTAssertEqual(cookie?.domain, "app.frontegg.com")
        XCTAssertEqual(cookie?.path, "/")
        XCTAssertTrue(cookie?.isSecure ?? false)
    }

    func test_makeRefreshCookie_buildsHttpCookie_withoutSecureFlag() {
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: "rt-jwt",
            baseUrl: "http://localhost:3000",
            clientId: "client-1"
        )
        XCTAssertNotNil(cookie)
        XCTAssertEqual(cookie?.domain, "localhost")
        XCTAssertFalse(cookie?.isSecure ?? true)
    }

    // MARK: - Logout cleanup invariant

    func test_refreshCookieName_matchesDefaultLogoutCleanupRegex() {
        // FronteggAuth+Logout.swift uses `^fe_refresh` regex by default to
        // clean up cookies on logout. The bridged cookie this class writes
        // must match that regex so a logged-out session can't be resurrected
        // in the portal via a stale cookie.
        let names = [
            AdminPortalWebView.refreshCookieName(clientId: "c-1"),
            AdminPortalWebView.refreshCookieName(clientId: "b1c2d3e4-1234-5678-9abc-deadbeef0000"),
            AdminPortalWebView.refreshCookieName(clientId: "nodashes"),
        ]
        let logoutMatcher = try! NSRegularExpression(pattern: "^fe_refresh")
        for name in names {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            XCTAssertNotNil(
                logoutMatcher.firstMatch(in: name, range: range),
                "Bridged cookie name '\(name)' must match the default logout-cleanup regex '^fe_refresh'."
            )
        }
    }

    // MARK: - Coordinator.webViewDidClose

    @MainActor
    func test_coordinator_invokesOnClose_whenWebViewDidCloseFires() {
        let expectation = expectation(description: "onClose invoked")
        let coordinator = AdminPortalWebView.Coordinator(onClose: {
            expectation.fulfill()
        })

        coordinator.webViewDidClose(WKWebView())

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func test_coordinator_doesNotCrash_whenOnCloseIsNilAndWebViewDidCloseFires() {
        let coordinator = AdminPortalWebView.Coordinator(onClose: nil)

        // Should be a no-op; if the optional-call wasn't safe this would crash.
        coordinator.webViewDidClose(WKWebView())
    }

    // MARK: - Coordinator navigation policy

    @MainActor
    func test_coordinator_allowsAllNavigation_andRequestsDesktopContentMode() {
        let coordinator = AdminPortalWebView.Coordinator(onClose: nil)
        let request = URLRequest(url: URL(string: "https://app.frontegg.com/oauth/portal")!)
        let action = StubNavigationAction(request: request)
        let preferences = WKWebpagePreferences()

        var receivedPolicy: WKNavigationActionPolicy?
        var receivedPreferences: WKWebpagePreferences?
        coordinator.webView(WKWebView(), decidePolicyFor: action, preferences: preferences) { policy, prefs in
            receivedPolicy = policy
            receivedPreferences = prefs
        }

        XCTAssertEqual(receivedPolicy, .allow)
        XCTAssertEqual(receivedPreferences?.preferredContentMode, .desktop,
                       "Per-navigation preferences must request desktop content mode so the portal layout doesn't flip to mobile after in-page navigations.")
    }

}

// MARK: - Stubs

/// `WKNavigationAction` cannot be instantiated directly in tests; subclass to
/// inject a synthetic request.
private final class StubNavigationAction: WKNavigationAction {
    private let stubRequest: URLRequest

    init(request: URLRequest) {
        self.stubRequest = request
        super.init()
    }

    override var request: URLRequest { stubRequest }
}
