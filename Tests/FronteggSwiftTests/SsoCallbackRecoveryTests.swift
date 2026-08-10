//
//  SsoCallbackRecoveryTests.swift
//  FronteggSwiftTests
//
//  FR-26387: after a successful SAML round trip the identity service lands the embedded
//  WebView on /oauth/account/saml/callback with no authorization code, so the app's
//  redirect_uri is never reached. These cover the predicate that detects that dead end.
//

import XCTest
@testable import FronteggSwift

final class SsoCallbackRecoveryTests: XCTestCase {
    /// Mirrors the customer tenant in FR-26387: a custom domain whose base URL carries a
    /// `/fe-auth` path prefix, which every routed path has to be resolved against.
    private let testBaseUrl = "https://staging-api.skypath.io/fe-auth"
    private let testClientId = "9d35fb01-a7bd-4912-9ad3-301871400cca"

    override func setUp() {
        super.setUp()
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: testBaseUrl, clientId: testClientId)),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: testBaseUrl, cliendId: testClientId)
    }

    override func tearDown() {
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    func test_returnsTrue_forSamlCallbackWithoutCode() {
        // The exact URL the WebView lands on in the FR-26387 capture.
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback")!
        XCTAssertTrue(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_whenSamlCallbackCarriesCode() {
        // If the hosted login box ever does hand back a code, the normal OAuth exchange
        // owns the flow and the cookie recovery must stay out of the way.
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback?code=abc123")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forOrdinaryLoginPage() {
        // A stale fe_refresh cookie must never auto-complete a login from the login page.
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/login")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forPreloginPage() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/prelogin?client_id=x&state=y")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forForeignHost() {
        // Same path on someone else's host is not our identity service.
        let url = URL(string: "https://evil.example.com/fe-auth/oauth/account/saml/callback")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsTrue_forBaseUrlWithoutPathPrefix() {
        // Tenants without a path-prefixed custom domain must behave identically.
        let plainBase = "https://auth.example.com"
        let url = URL(string: "https://auth.example.com/oauth/account/saml/callback")!
        XCTAssertTrue(isSsoCallbackWithoutCode(url, baseUrl: plainBase))
    }

    func test_returnsFalse_whenCodeAppearsAlongsideOtherParams() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback?state=xyz&code=abc123")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_whenCallbackReportsAnError() {
        // An explicit failure must surface to the user, not be papered over by signing them
        // in from a cookie a previous attempt happened to leave behind.
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback?error=access_denied")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    // MARK: - Regressions: routes owned by other flows must not trigger the recovery

    func test_returnsFalse_forSocialLoginSuccessRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/social/success?code=abc")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forOidcCallbackRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/oidc/callback")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forAppLinkRedirectRoute() {
        // Magic-link / App-Link callbacks land on /oauth/account/redirect/ios/{bundleId} and
        // are owned by the hosted-callback path, including the unlock-account case that
        // deliberately arrives without a code.
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/redirect/ios/com.skypath.app")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forSignUpRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/sign-up")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_samlCallbackStillClassifiesAsLoginRoute() {
        // The recovery is additive: routing for the assertion callback is unchanged, so the
        // loader still hides and the login box still renders if recovery cannot proceed.
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback")!
        XCTAssertEqual(getOverrideUrlType(url: url), .loginRoutes)
    }

    // MARK: - Cookie handling

    func test_recoveryTokens_nilWhenNoRefreshCookie() {
        XCTAssertNil(CustomWebView.ssoRecoveryTokens(refreshCookie: nil, deviceCookie: nil))
    }

    func test_recoveryTokens_nilWhenRefreshCookieMalformed() {
        XCTAssertNil(CustomWebView.ssoRecoveryTokens(refreshCookie: "fe_refresh_abc", deviceCookie: nil))
    }

    func test_recoveryTokens_extractsRefreshAndDeviceTokens() {
        let tokens = CustomWebView.ssoRecoveryTokens(
            refreshCookie: "fe_refresh_9d35fb01a7bd-4912-9ad3-301871400cca=06cd3861-34b1-4bcb-b8ae-a3718b37a176",
            deviceCookie: "fe_device_9d35fb01=device-value"
        )
        XCTAssertEqual(tokens?.refreshToken, "06cd3861-34b1-4bcb-b8ae-a3718b37a176")
        XCTAssertEqual(tokens?.deviceToken, "device-value")
    }

    func test_recoveryTokens_preservesEqualsSignsInsideValue() {
        // Base64url token values can carry '=' padding; only the first '=' is the separator.
        let tokens = CustomWebView.ssoRecoveryTokens(
            refreshCookie: "fe_refresh_abc=dG9rZW4=",
            deviceCookie: nil
        )
        XCTAssertEqual(tokens?.refreshToken, "dG9rZW4=")
        XCTAssertNil(tokens?.deviceToken)
    }

    func test_recoveryTokens_ignoresMalformedDeviceCookieButKeepsRefresh() {
        let tokens = CustomWebView.ssoRecoveryTokens(
            refreshCookie: "fe_refresh_abc=refresh-value",
            deviceCookie: "garbage"
        )
        XCTAssertEqual(tokens?.refreshToken, "refresh-value")
        XCTAssertNil(tokens?.deviceToken)
    }
}
