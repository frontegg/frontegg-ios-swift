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
        // (line 62-66 of Api.swift). The cleanup pass in loadPortal uses
        // this prefix to delete stale fe_refresh_* / fe_device_* cookies
        // from the WebView store before mirroring fresh ones — if the
        // format here drifts, the cleanup will miss the stale cookie that
        // got the customer into "second-login" hell in the first place.
        //
        // Earlier versions of this code stripped ALL dashes — that produced
        // a cookie name the server didn't recognize. This test pins the
        // correct behavior.
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

    // MARK: - Logout cleanup invariant

    func test_refreshCookieName_matchesDefaultLogoutCleanupRegex() {
        // FronteggAuth+Logout.swift uses `^fe_refresh` regex by default to
        // clean up cookies on logout. The cookies this class mirrors from
        // silent-authorize responses must match that regex so a logged-out
        // session can't be resurrected in the portal via a stale cookie.
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

    // MARK: - extractFronteggSessionCookies(from:requestURL:)

    private func makeResponse(
        url: URL,
        setCookieHeaders: [String]
    ) -> HTTPURLResponse {
        // HTTPURLResponse only accepts a flat header dict. Multiple Set-Cookie
        // headers are joined by `, ` per RFC 7230, which is exactly how iOS's
        // own URLSession exposes them — so concatenate to simulate the real
        // shape `HTTPCookie.cookies(withResponseHeaderFields:for:)` will see.
        let joined = setCookieHeaders.joined(separator: ", ")
        return HTTPURLResponse(
            url: url,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": joined]
        )!
    }

    func test_extractFronteggSessionCookies_capturesRefreshAndDeviceCookies() {
        // The two cookies the auth backend emits on a successful
        // POST /frontegg/oauth/authorize/silent — observed via real curl
        // against autheu.davidantoon.me. The portal's React app expects
        // both in the WebView's cookie jar to bootstrap the session.
        let requestURL = URL(string: "https://app.frontegg.com/frontegg/oauth/authorize/silent")!
        let response = makeResponse(url: requestURL, setCookieHeaders: [
            "fe_refresh_b6adfe4cd695-4c04-b95f-3ec9fd0c6cca=rt-uuid; Domain=app.frontegg.com; Path=/; HttpOnly; Secure; SameSite=None",
            "fe_device_e322534e48004374af986674ab86c55c=dev-uuid; Domain=app.frontegg.com; Path=/; HttpOnly; Secure; SameSite=None",
        ])

        let cookies = AdminPortalWebView.extractFronteggSessionCookies(
            from: response,
            requestURL: requestURL
        )

        XCTAssertEqual(cookies.count, 2)
        let names = Set(cookies.map { $0.name })
        XCTAssertTrue(names.contains("fe_refresh_b6adfe4cd695-4c04-b95f-3ec9fd0c6cca"))
        XCTAssertTrue(names.contains("fe_device_e322534e48004374af986674ab86c55c"))
    }

    func test_extractFronteggSessionCookies_filtersOutNonFronteggCookies() {
        // Defensive: if the server response also carries unrelated cookies
        // (analytics, tracking, anything), we must NOT pollute the WebView
        // cookie jar with them.
        let requestURL = URL(string: "https://app.frontegg.com/frontegg/oauth/authorize/silent")!
        let response = makeResponse(url: requestURL, setCookieHeaders: [
            "fe_refresh_abc=rt-value; Domain=app.frontegg.com; Path=/",
            "_ga=GA1.1.xxx; Domain=.frontegg.com; Path=/",
            "tracking_id=tk-value; Path=/",
        ])

        let cookies = AdminPortalWebView.extractFronteggSessionCookies(
            from: response,
            requestURL: requestURL
        )

        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies.first?.name, "fe_refresh_abc")
    }

    func test_extractFronteggSessionCookies_returnsEmpty_whenNoMatchingHeaders() {
        let requestURL = URL(string: "https://app.frontegg.com/frontegg/oauth/authorize/silent")!
        let response = makeResponse(url: requestURL, setCookieHeaders: [
            "_ga=GA1.1.xxx; Domain=.frontegg.com; Path=/",
        ])

        let cookies = AdminPortalWebView.extractFronteggSessionCookies(
            from: response,
            requestURL: requestURL
        )

        XCTAssertTrue(cookies.isEmpty)
    }

    func test_extractFronteggSessionCookies_returnsEmpty_whenResponseIsNotHTTPURLResponse() {
        // URLResponse (not HTTPURLResponse) has no headers; helper must
        // handle this gracefully.
        let requestURL = URL(string: "https://app.frontegg.com")!
        let response = URLResponse(
            url: requestURL,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        let cookies = AdminPortalWebView.extractFronteggSessionCookies(
            from: response,
            requestURL: requestURL
        )

        XCTAssertTrue(cookies.isEmpty)
    }

    func test_extractFronteggSessionCookies_carriesSecureAndDomainAttributes() {
        // The mirrored cookies must keep their HttpOnly/Secure/SameSite/Domain
        // attributes so they behave the same way in the WebView as they would
        // if the server had set them directly via a navigation response.
        let requestURL = URL(string: "https://app.frontegg.com/frontegg/oauth/authorize/silent")!
        let response = makeResponse(url: requestURL, setCookieHeaders: [
            "fe_refresh_abc=rt-value; Domain=app.frontegg.com; Path=/; HttpOnly; Secure; SameSite=None",
        ])

        let cookies = AdminPortalWebView.extractFronteggSessionCookies(
            from: response,
            requestURL: requestURL
        )

        XCTAssertEqual(cookies.count, 1)
        let c = cookies.first!
        XCTAssertEqual(c.value, "rt-value")
        XCTAssertEqual(c.path, "/")
        XCTAssertTrue(c.isSecure)
        XCTAssertTrue(c.isHTTPOnly)
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
