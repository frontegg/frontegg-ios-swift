//
//  UnlockAccountFlowTests.swift
//  FronteggSwiftTests
//
//  FR-26330: the unlock-account deep link opens the app, then drops the user to a fresh
//  login screen. The final callback of that flow is a custom-scheme URL with no code, which
//  the custom-scheme branch of decidePolicyFor treats as a cancelled OAuth login before the
//  unlock detection in the .HostedLoginCallback case can ever run.
//

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

    // MARK: - The FR-26330 flow

    func test_detectsUnlockCompletion_afterIntermediateRedirectWithoutCode() {
        // The server sends the unlock link through /oauth/account/redirect/ios/{bundleId}
        // with no code, and only then to the custom-scheme callback, also with no code.
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        XCTAssertTrue(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: previous)
        )
    }

    /// The shape the flow actually takes: WebKit refuses a server redirect to an
    /// unregistered scheme, so the callback never reaches decidePolicyFor and instead
    /// arrives as a WebKitErrorDomain 102 failure whose failing URL is the callback and
    /// whose preceding URL is still the unlock page. Confirmed on a simulator run.
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
        // With useAssetLinks the final callback is an https App-Link rather than a custom
        // scheme; the same intermediate hop precedes it.
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        let url = URL(string: "https://auth.example.com/ios/oauth/callback")!
        XCTAssertTrue(
            CustomWebView.isUnlockFlowCompletion(url: url, previousUrl: previous)
        )
    }

    // MARK: - Must not swallow real OAuth outcomes

    func test_notUnlock_whenCallbackCarriesCode() {
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback("?code=abc123"), previousUrl: previous)
        )
    }

    func test_notUnlock_whenCallbackCarriesOAuthError() {
        // A real OAuth failure must still reach the failure handler.
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
        // Magic link: the intermediate hop carries the code, so this is a real OAuth callback.
        let previous = URL(string: "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)?code=abc")!
        XCTAssertFalse(
            CustomWebView.isUnlockFlowCompletion(url: callback(), previousUrl: previous)
        )
    }

    func test_notUnlock_whenThereIsNoPreviousUrl() {
        // Without the preceding hop there is no evidence of an unlock flow, and guessing
        // would swallow a genuinely cancelled login.
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
