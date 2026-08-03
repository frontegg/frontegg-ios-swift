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

    /// Sanity check on the other arm, so the contract is not trivially satisfied
    /// by always returning false.
    @MainActor
    func test_loadInWebView_reportsSuccess_whenWebViewAttached() {
        let webView = CustomWebView()
        FronteggAuth.shared.webview = webView
        defer { FronteggAuth.shared.webview = nil }

        XCTAssertTrue(
            FronteggAuth.shared.loadInWebView(successURL),
            "with a webview attached the handoff must report that the load was issued"
        )
    }
}
