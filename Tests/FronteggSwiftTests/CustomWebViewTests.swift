//
//  CustomWebViewTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class CustomWebViewTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearOAuthState()
    }

    override func tearDown() {
        clearOAuthState()
        super.tearDown()
    }

    func test_resolveHostedCallbackCodeVerifier_magicLink_returnsNil() async {
        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: true,
            isSocialLogin: false,
            oauthState: "state-123",
            socialVerifierProvider: {
                XCTFail("Magic link flow should not request social verifier")
                return "unexpected"
            }
        )

        XCTAssertNil(resolution.codeVerifier)
        XCTAssertEqual(resolution.source, "magic_link")
        XCTAssertNil(resolution.providerError)
    }

    func test_resolveHostedCallbackCodeVerifier_socialUsesWebViewVerifierWhenAvailable() async {
        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: true,
            oauthState: "state-123",
            socialVerifierProvider: {
                "webview-verifier"
            }
        )

        XCTAssertEqual(resolution.codeVerifier, "webview-verifier")
        XCTAssertEqual(resolution.source, "webview_local_storage")
        XCTAssertNil(resolution.providerError)
    }

    func test_resolveHostedCallbackCodeVerifier_socialFallsBackToLastGeneratedVerifier() async {
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "shared-verifier")

        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: true,
            oauthState: "unexpected-state",
            socialVerifierProvider: {
                throw URLError(.timedOut)
            }
        )

        XCTAssertEqual(resolution.codeVerifier, "shared-verifier")
        XCTAssertEqual(resolution.source, "last_generated_fallback")
        XCTAssertNotNil(resolution.providerError)
    }

    func test_resolveHostedCallbackCodeVerifier_regularFlowRequiresStateMatch() async {
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")

        let missing = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: false,
            oauthState: "unexpected-state",
            socialVerifierProvider: {
                XCTFail("Regular OAuth flow should not request social verifier")
                return "unexpected"
            }
        )

        XCTAssertNil(missing.codeVerifier)
        XCTAssertEqual(missing.source, "missing")

        let matched = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: false,
            oauthState: "expected-state",
            socialVerifierProvider: {
                XCTFail("Regular OAuth flow should not request social verifier")
                return "unexpected"
            }
        )

        XCTAssertEqual(matched.codeVerifier, "expected-verifier")
        XCTAssertEqual(matched.source, "state_match")
    }

    private func clearOAuthState() {
        UserDefaults.standard.removeObject(forKey: KeychainKeys.codeVerifier.rawValue)
        UserDefaults.standard.removeObject(forKey: KeychainKeys.oauthStateVerifiers.rawValue)
    }
}
