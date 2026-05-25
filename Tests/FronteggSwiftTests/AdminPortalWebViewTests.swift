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

    // MARK: - refreshCookieName(clientId:applicationId:)

    func test_refreshCookieName_usesClientId_whenApplicationIdNil() {
        let name = AdminPortalWebView.refreshCookieName(
            clientId: "b1c2d3e4-1234-5678-9abc-deadbeef0000",
            applicationId: nil
        )
        XCTAssertEqual(name, "fe_refresh_b1c2d3e4123456789abcdeadbeef0000")
        XCTAssertFalse(name.contains("-"))
        XCTAssertTrue(name.hasPrefix("fe_refresh_"))
    }

    func test_refreshCookieName_usesClientId_whenApplicationIdEmpty() {
        let name = AdminPortalWebView.refreshCookieName(
            clientId: "client-123-abc",
            applicationId: ""
        )
        XCTAssertEqual(name, "fe_refresh_client123abc")
    }

    func test_refreshCookieName_usesApplicationId_whenPresent() {
        // Mirrors frontegg-nextjs CookieManager.refreshTokenKey: when appId
        // is set (multi-app workspace), the cookie is scoped to the appId
        // instead of the clientId so the portal recognizes the per-app session.
        let name = AdminPortalWebView.refreshCookieName(
            clientId: "client-id-here",
            applicationId: "app-id-multi-tenant"
        )
        XCTAssertEqual(name, "fe_refresh_appidmultitenant")
    }

    // MARK: - makeRefreshCookie(refreshToken:baseUrl:clientId:applicationId:)

    func test_makeRefreshCookie_returnsNil_whenRefreshTokenIsNil() {
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: nil,
            baseUrl: "https://app.frontegg.com",
            clientId: "client",
            applicationId: nil
        )
        XCTAssertNil(cookie, "User not logged in → no cookie to bridge; portal falls back to its own login.")
    }

    func test_makeRefreshCookie_returnsNil_whenRefreshTokenIsEmpty() {
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: "",
            baseUrl: "https://app.frontegg.com",
            clientId: "client",
            applicationId: nil
        )
        XCTAssertNil(cookie)
    }

    func test_makeRefreshCookie_returnsNil_whenBaseUrlIsMalformed() {
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: "rt-jwt-value",
            baseUrl: "not a url",
            clientId: "client",
            applicationId: nil
        )
        XCTAssertNil(cookie)
    }

    func test_makeRefreshCookie_buildsHttpsCookie_withSecureFlag() {
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: "rt-jwt-value-abc",
            baseUrl: "https://app.frontegg.com",
            clientId: "b1c2d3e4-1234",
            applicationId: nil
        )
        XCTAssertNotNil(cookie)
        XCTAssertEqual(cookie?.name, "fe_refresh_b1c2d3e41234")
        XCTAssertEqual(cookie?.value, "rt-jwt-value-abc")
        XCTAssertEqual(cookie?.domain, "app.frontegg.com")
        XCTAssertEqual(cookie?.path, "/")
        XCTAssertTrue(cookie?.isSecure ?? false, "HTTPS baseUrl must produce a Secure cookie.")
    }

    func test_makeRefreshCookie_buildsHttpCookie_withoutSecureFlag() {
        // Useful for local-dev tenants on http://localhost. The cookie still
        // needs to be set so the portal recognizes the session in dev.
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: "rt-jwt",
            baseUrl: "http://localhost:3000",
            clientId: "client-1",
            applicationId: nil
        )
        XCTAssertNotNil(cookie)
        XCTAssertEqual(cookie?.domain, "localhost")
        XCTAssertFalse(cookie?.isSecure ?? true)
    }

    func test_makeRefreshCookie_scopesToApplicationId_whenPresent() {
        let cookie = AdminPortalWebView.makeRefreshCookie(
            refreshToken: "rt-jwt",
            baseUrl: "https://app.frontegg.com",
            clientId: "client-id",
            applicationId: "app-id-abc-123"
        )
        XCTAssertEqual(cookie?.name, "fe_refresh_appidabc123")
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
