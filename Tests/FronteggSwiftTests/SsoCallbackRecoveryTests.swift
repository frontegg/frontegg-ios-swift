
import XCTest
@testable import FronteggSwift

final class SsoCallbackRecoveryTests: XCTestCase {
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
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback")!
        XCTAssertTrue(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_whenSamlCallbackCarriesCode() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback?code=abc123")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forOrdinaryLoginPage() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/login")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forPreloginPage() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/prelogin?client_id=x&state=y")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forForeignHost() {
        let url = URL(string: "https://evil.example.com/fe-auth/oauth/account/saml/callback")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsTrue_forBaseUrlWithoutPathPrefix() {
        let plainBase = "https://auth.example.com"
        let url = URL(string: "https://auth.example.com/oauth/account/saml/callback")!
        XCTAssertTrue(isSsoCallbackWithoutCode(url, baseUrl: plainBase))
    }

    func test_returnsFalse_whenCodeAppearsAlongsideOtherParams() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback?state=xyz&code=abc123")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_whenCallbackReportsAnError() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback?error=access_denied")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }


    func test_returnsFalse_forSocialLoginSuccessRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/social/success?code=abc")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forOidcCallbackRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/oidc/callback")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forAppLinkRedirectRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/redirect/ios/com.skypath.app")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_returnsFalse_forSignUpRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/sign-up")!
        XCTAssertFalse(isSsoCallbackWithoutCode(url, baseUrl: testBaseUrl))
    }

    func test_samlCallbackStillClassifiesAsLoginRoute() {
        let url = URL(string: "https://staging-api.skypath.io/fe-auth/oauth/account/saml/callback")!
        XCTAssertEqual(getOverrideUrlType(url: url), .loginRoutes)
    }


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
