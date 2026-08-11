
import XCTest
@testable import FronteggSwift

final class UnlockAccountFlowTests: XCTestCase {
    private let testBaseUrl = "https://auth.example.com"
    private let testClientId = "test-unlock-client"
    private let bundleId = "com.example.app"

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

    private func callback(_ query: String = "") -> URL {
        URL(string: "com.example.app://auth.example.com/ios/oauth/callback\(query)")!
    }


    func test_detectsUnlockCompletion_afterIntermediateRedirectWithoutCode() {
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        XCTAssertTrue(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: previous)
        )
    }

    func test_detectsUnlockCompletion_forFailedNavigationToCallbackScheme() {
        let failingURL = URL(string: "com.frontegg.demo://127.0.0.1/ios/oauth/callback")!
        let previous = URL(string: "http://127.0.0.1:49555/oauth/account/unlock?token=e2e-unlock-token")!
        XCTAssertTrue(
            CustomWebView.isUnlockFlowCompletion(url: failingURL, previousUrl: previous)
        )
    }

    func test_detectsUnlockCompletion_whenComingStraightFromUnlockPage() {
        let previous = URL(string: "https://auth.example.com/oauth/account/unlock?token=abc")!
        XCTAssertTrue(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: previous)
        )
    }

    func test_detectsUnlockCompletion_forAppLinkHttpsCallback() {
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        let url = URL(string: "https://auth.example.com/ios/oauth/callback")!
        XCTAssertTrue(
            CustomWebView.isUnlockFlowCompletion(url: url, previousUrl: previous)
        )
    }


    func test_notUnlock_whenCallbackCarriesCode() {
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback("?code=abc123"), previousUrl: previous)
        )
    }

    func test_notUnlock_whenCallbackCarriesOAuthError() {
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback("?error=access_denied"), previousUrl: previous)
        )
    }

    func test_notUnlock_whenCallbackCarriesOnlyErrorDescription() {
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(
                url: callback("?error_description=something%20broke"),
                previousUrl: previous
            )
        )
    }

    func test_notUnlock_whenIntermediateRedirectCarriedCode() {
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)?code=abc")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: previous)
        )
    }

    func test_notUnlock_whenThereIsNoPreviousUrl() {
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: nil)
        )
    }

    func test_notUnlock_afterSocialLoginSuccess() {
        let previous = URL(string: "https://auth.example.com/oauth/account/social/success")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: previous)
        )
    }

    func test_notUnlock_afterOrdinaryLoginPage() {
        let previous = URL(string: "https://auth.example.com/oauth/account/login")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: previous)
        )
    }
}
