//
//  SocialLoginWebViewHandoffTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

/// FR-26132. After a social-login callback is parsed, the SDK hands the
/// `/oauth/account/social/success` URL back to the embedded webview to finish the
/// exchange. `loadInWebView` used to `guard let webView = webview else { return }` —
/// a silent no-op. When the flow ran in `ASWebAuthenticationSession` and no embedded
/// webview was attached, the exchange simply never started: nothing was logged, no
/// error was raised, and the only symptom was the 1.25s embedded-OAuth recovery
/// timeout surfacing a misleading "Failed to get extract code" toast ~1.3s later.
///
/// The handoff must report whether it actually loaded, so the caller can fail fast
/// with an accurate error instead of waiting for that timeout.
final class SocialLoginWebViewHandoffTests: XCTestCase {

    private let testBaseUrl = "https://test.frontegg.com"
    private let testClientId = "test-social-handoff-client"

    private var successURL: URL {
        URL(string: "\(testBaseUrl)/oauth/account/social/success?code=abc&redirectUri=x")!
    }

    override func setUp() {
        super.setUp()
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: testBaseUrl, clientId: testClientId)),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: testBaseUrl, cliendId: testClientId)
        FronteggAuth.shared.webview = nil
    }

    override func tearDown() {
        FronteggAuth.shared.webview = nil
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    /// The regression: with no webview attached the handoff must report failure
    /// rather than returning as though the load had been issued.
    func test_loadInWebView_reportsFailure_whenNoWebViewAttached() {
        XCTAssertFalse(
            FronteggAuth.shared.loadInWebView(successURL),
            "with no embedded webview attached the handoff must report failure, not silently succeed"
        )
    }

    // The positive arm (webview attached -> reports success) is intentionally NOT
    // unit-tested here. Instantiating a real `CustomWebView` spins up a WKWebView and
    // the surrounding SDK machinery — it took ~22s locally and its asynchronous
    // TraceIdLogger output leaked into `LoggerDelegateTests`' spy delegate, failing an
    // unrelated suite on CI. That cost is not worth guarding against an implementation
    // that always returns false; the loaded path is covered by the E2E suites, which
    // drive a real webview.

    /// Drives the real callback from the 2026-08-02 device capture through the callback
    /// handler with no webview attached — the configuration that failed in the field.
    ///
    /// This distinguishes the two branches that both produced silence before this change:
    /// `.failedToExtractCode` means the callback could not be parsed, `.couldNotFindRootViewController`
    /// means it parsed fine and the handoff to the webview is what failed.
    func test_realWorldCallback_withNoWebView_failsAtHandoffNotAtParsing() {
        let recordedBaseUrl = "https://app-bv4uq4gr7esi.frontegg.com"
        let recordedBundleId = "com.frontegg.demo"
        let recordedCallback = "com.frontegg.demo://app-bv4uq4gr7esi.frontegg.com/ios/oauth/callback?state=%7B%22appId%22%3A%22%22%2C%22platform%22%3A%22ios%22%2C%22provider%22%3A%22google%22%2C%22bundleId%22%3A%22com.frontegg.demo%22%2C%22action%22%3A%22login%22%7D&iss=https%3A%2F%2Faccounts.google.com&code=4%2F0AXEQxIDPLnd_sH0KYzhz6eF7x0fVPQ3_q1_7qe3Uz7ygOBj1Cmza4LqACC8Fa4-z91OBOw&scope=email+profile&authuser=0&hd=frontegg.com&prompt=none&social-login-callback=true"

        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: recordedBaseUrl, clientId: testClientId)),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: recordedBaseUrl, cliendId: testClientId)
        FronteggApp.shared.bundleIdentifier = recordedBundleId
        FronteggAuth.shared.webview = nil

        let settled = expectation(description: "social login callback settles")
        var received: FronteggError?

        FronteggAuth.shared.handleSocialLoginOAuthCallback(
            providerString: "google",
            callbackURL: URL(string: recordedCallback)!,
            error: nil
        ) { result in
            if case .failure(let error) = result { received = error }
            settled.fulfill()
        }

        // Before this change the flow never settled here — the completion was dropped and
        // only the 1.25s recovery timeout surfaced anything.
        wait(for: [settled], timeout: 5)

        guard case .authError(let authError)? = received else {
            return XCTFail("expected an auth error, got \(String(describing: received))")
        }
        XCTAssertEqual(
            authError.failureReason, "couldNotFindRootViewController",
            "expected the handoff to be the failure point; got \(String(describing: authError.failureReason))"
        )
    }
}
