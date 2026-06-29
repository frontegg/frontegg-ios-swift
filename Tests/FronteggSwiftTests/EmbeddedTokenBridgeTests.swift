//
//  EmbeddedTokenBridgeTests.swift
//  FronteggSwiftTests
//
//  Tests for the embedded login WebView's native token bridge (getTokens) — the
//  fix that lets step-up / re-auth reuse the native session instead of the cookie
//  token-refresh that 401s in the WebView. Covers the security-critical origin
//  gate, the FronteggNativeBridgeCallbacks resolve/reject JS, and the advertised
//  capability flag.
//

import XCTest
@testable import FronteggSwift

final class EmbeddedTokenBridgeTests: XCTestCase {

    // MARK: - Trusted-origin gate: only the configured Frontegg origin may pull tokens

    func test_isTrustedBridgeOrigin_true_whenSchemeHostPortMatch() {
        XCTAssertTrue(
            FronteggWKContentController.isTrustedBridgeOrigin(
                currentURL: URL(string: "https://acme.frontegg.com/oauth/authorize?response_type=code"),
                baseURL: "https://acme.frontegg.com"
            )
        )
    }

    func test_isTrustedBridgeOrigin_false_forDifferentHost() {
        XCTAssertFalse(
            FronteggWKContentController.isTrustedBridgeOrigin(
                currentURL: URL(string: "https://evil.example.com/oauth/authorize"),
                baseURL: "https://acme.frontegg.com"
            )
        )
    }

    func test_isTrustedBridgeOrigin_false_forDifferentScheme() {
        XCTAssertFalse(
            FronteggWKContentController.isTrustedBridgeOrigin(
                currentURL: URL(string: "http://acme.frontegg.com/oauth/authorize"),
                baseURL: "https://acme.frontegg.com"
            )
        )
    }

    func test_isTrustedBridgeOrigin_false_forNilCurrentURL() {
        XCTAssertFalse(
            FronteggWKContentController.isTrustedBridgeOrigin(
                currentURL: nil,
                baseURL: "https://acme.frontegg.com"
            )
        )
    }

    // MARK: - Callback JS consumed by the redux-store FronteggNativeBridgeCallbacks registry

    func test_tokensJSON_containsBothTokens() {
        let json = FronteggWKContentController.tokensJSON(accessToken: "AT", refreshToken: "RT")
        XCTAssertTrue(json.contains("\"accessToken\":\"AT\""))
        XCTAssertTrue(json.contains("\"refreshToken\":\"RT\""))
    }

    func test_resolveCallbackJS_deliversTokensAndCleansUp() {
        let js = FronteggWKContentController.resolveCallbackJS(
            callbackId: "cb-1",
            json: "{\"accessToken\":\"AT\"}"
        )
        XCTAssertTrue(js.contains("window.FronteggNativeBridgeCallbacks"))
        XCTAssertTrue(js.contains("r[\"cb-1\"].resolve({\"accessToken\":\"AT\"})"))
        XCTAssertTrue(js.contains("delete r[\"cb-1\"]"))
    }

    func test_rejectCallbackJS_escapesDoubleQuotes() {
        let js = FronteggWKContentController.rejectCallbackJS(callbackId: "cb-2", message: "bad \"x\"")
        XCTAssertTrue(js.contains("r[\"cb-2\"].reject(\"bad \\\"x\\\"\")"))
    }

    // MARK: - Capability advertised so the login box takes the native-token path

    func test_bridgeFunctions_advertisesGetTokens() {
        let fns = FronteggWebView.bridgeFunctions(
            loginWithSocialLogin: false,
            loginWithCustomSocialLoginProvider: false,
            loginWithSocialLoginProvider: false,
            loginWithSSO: false,
            loginWithCustomSSO: false,
            shouldPromptSocialLoginConsent: false,
            suggestSavePassword: false
        )
        XCTAssertEqual(
            fns["getTokens"] as? Bool, true,
            "getTokens must be advertised so the login box bootstraps from native tokens"
        )
    }
}
