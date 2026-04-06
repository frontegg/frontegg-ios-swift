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

    func test_resolveHostedCallbackCodeVerifier_socialFallsBackToPendingSocialStateStore() async throws {
        let rawState = try makeRawSocialState(
            provider: "google",
            appId: "app-1",
            action: "login"
        )
        let canonicalState = SocialLoginUrlGenerator.canonicalizeSocialState(rawState)

        SocialLoginUrlGenerator.shared.storePendingSocialCodeVerifier(
            "pending-social-verifier",
            for: rawState
        )

        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: true,
            oauthState: canonicalState,
            socialVerifierProvider: {
                throw URLError(.timedOut)
            }
        )

        XCTAssertEqual(resolution.codeVerifier, "pending-social-verifier")
        XCTAssertEqual(resolution.source, "pending_social_state_store")
        XCTAssertNotNil(resolution.providerError)
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

    func test_resolveHostedCallbackRedirect_generatedCallbackAliasUsesActualAlias() {
        let resolution = CustomWebView.resolveHostedCallbackRedirect(
            url: URL(string: "com.frontegg.demo://auth.example.com/ios/oauth/callback?code=123")!,
            magicLinkRedirectUri: nil,
            baseUrl: "https://auth.example.com/fe-auth",
            bundleIdentifier: "com.frontegg.demo",
            embeddedMode: true
        )

        XCTAssertEqual(
            resolution.redirectUri,
            "com.frontegg.demo://auth.example.com/ios/oauth/callback"
        )
        XCTAssertFalse(resolution.isMagicLink)
    }

    func test_resolveHostedCallbackRedirect_socialSuccessUsesRedirectUriQuery() {
        let encodedRedirectUri = "com.frontegg.demo://auth.example.com/ios/oauth/callback"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(
            string: "https://auth.example.com/fe-auth/oauth/account/social/success?code=123&redirectUri=\(encodedRedirectUri)"
        )!

        let resolution = CustomWebView.resolveHostedCallbackRedirect(
            url: url,
            magicLinkRedirectUri: nil,
            baseUrl: "https://auth.example.com/fe-auth",
            bundleIdentifier: "com.frontegg.demo",
            embeddedMode: true
        )

        XCTAssertEqual(
            resolution.redirectUri,
            "com.frontegg.demo://auth.example.com/ios/oauth/callback"
        )
        XCTAssertFalse(resolution.isMagicLink)
    }

    func test_resolveHostedCallbackRedirect_socialSuccessFallsBackWhenRedirectUriQueryIsUnexpected() {
        let encodedRedirectUri = "com.bad.actor://evil.example.com/ios/oauth/callback"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(
            string: "https://auth.example.com/fe-auth/oauth/account/social/success?code=123&redirectUri=\(encodedRedirectUri)"
        )!

        let resolution = CustomWebView.resolveHostedCallbackRedirect(
            url: url,
            magicLinkRedirectUri: nil,
            baseUrl: "https://auth.example.com/fe-auth",
            bundleIdentifier: "com.frontegg.demo",
            embeddedMode: true
        )

        XCTAssertEqual(
            resolution.redirectUri,
            "com.frontegg.demo://auth.example.com/fe-auth/ios/oauth/callback"
        )
        XCTAssertFalse(resolution.isMagicLink)
    }

    func test_resolveHostedCallbackRedirect_intermediateRedirectUsesExactPath() {
        let resolution = CustomWebView.resolveHostedCallbackRedirect(
            url: URL(
                string: "https://auth.example.com/fe-auth/oauth/account/redirect/ios/com.frontegg.demo/google?code=123"
            )!,
            magicLinkRedirectUri: nil,
            baseUrl: "https://auth.example.com/fe-auth",
            bundleIdentifier: "com.frontegg.demo",
            embeddedMode: true
        )

        XCTAssertEqual(
            resolution.redirectUri,
            "https://auth.example.com/fe-auth/oauth/account/redirect/ios/com.frontegg.demo/google"
        )
        XCTAssertTrue(resolution.isMagicLink)
    }

    func test_resolveHostedCallbackRedirect_intermediateRedirectPreservesNonDefaultPort() {
        let resolution = CustomWebView.resolveHostedCallbackRedirect(
            url: URL(
                string: "https://auth.example.com:8443/fe-auth/oauth/account/redirect/ios/com.frontegg.demo/google?code=123"
            )!,
            magicLinkRedirectUri: nil,
            baseUrl: "https://auth.example.com:8443/fe-auth",
            bundleIdentifier: "com.frontegg.demo",
            embeddedMode: true
        )

        XCTAssertEqual(
            resolution.redirectUri,
            "https://auth.example.com:8443/fe-auth/oauth/account/redirect/ios/com.frontegg.demo/google"
        )
        XCTAssertTrue(resolution.isMagicLink)
    }

    // MARK: - OIDC SSO Flow Tests
    //
    // SSO OIDC (enterprise SSO via Auth0, Okta, etc.) uses Frontegg's standard OAuth PKCE flow.
    // The code_verifier must come from CredentialManager (state-matched), NOT from webview localStorage.
    // webview localStorage holds FRONTEGG_CODE_VERIFIER which is for social login PKCE (Google/Microsoft).
    // See: https://github.com/frontegg/frontegg-ios-swift — "Invalid_code_verifier" fix.

    func test_oidcSso_usesCredentialManagerVerifier_notWebviewLocalStorage() async {
        // Simulate: SDK generated authorize URL with state=S and codeVerifier=A
        let nativeVerifier = "native-verifier-from-authorize-url"
        let oauthState = "oidc-sso-state-123"
        CredentialManager.registerPendingOAuth(state: oauthState, codeVerifier: nativeVerifier)

        // OIDC SSO flow: isSocialLogin must be false — the OIDC callback should NOT set isSocialLoginFlow
        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: false, // OIDC SSO is NOT social login
            oauthState: oauthState,
            socialVerifierProvider: {
                XCTFail("OIDC SSO must NOT read code_verifier from webview localStorage")
                return "wrong-webview-verifier"
            }
        )

        XCTAssertEqual(resolution.codeVerifier, nativeVerifier,
                        "OIDC SSO must use the code_verifier from CredentialManager that matches the code_challenge in /oauth/authorize")
        XCTAssertEqual(resolution.source, "state_match")
        XCTAssertNil(resolution.providerError)
    }

    func test_oidcSso_withMismatchedState_returnsNil() async {
        // Simulate: SDK registered state=S1 but callback returned state=S2 (should not happen, but tests safety)
        CredentialManager.registerPendingOAuth(state: "registered-state", codeVerifier: "registered-verifier")

        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: false,
            oauthState: "different-state-from-callback",
            socialVerifierProvider: {
                XCTFail("OIDC SSO must NOT read code_verifier from webview localStorage")
                return "wrong-webview-verifier"
            }
        )

        XCTAssertNil(resolution.codeVerifier,
                      "When state doesn't match and isSocialLogin is false, code_verifier must be nil (no fallback)")
        XCTAssertEqual(resolution.source, "missing")
    }

    func test_oidcSso_treatedAsSocialLogin_wouldUseWrongVerifier() async {
        // This test documents the bug that was fixed:
        // If isSocialLogin were true (the old buggy behavior), the webview localStorage verifier
        // would be used instead of the CredentialManager one, causing "Invalid_code_verifier".
        let nativeVerifier = "correct-native-verifier"
        let webviewVerifier = "wrong-webview-verifier"
        let oauthState = "oidc-state-456"
        CredentialManager.registerPendingOAuth(state: oauthState, codeVerifier: nativeVerifier)

        // Simulating the OLD buggy behavior where isSocialLogin was incorrectly true
        let buggyResolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: true, // BUG: this was the old behavior for OIDC SSO
            oauthState: oauthState,
            socialVerifierProvider: {
                return webviewVerifier
            }
        )

        // The CORRECT behavior (isSocialLogin: false)
        let correctResolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: false, // FIX: OIDC SSO should not be treated as social login
            oauthState: oauthState,
            socialVerifierProvider: {
                XCTFail("Should not be called when isSocialLogin is false")
                return webviewVerifier
            }
        )

        // Document that the two behaviors produce different verifiers
        XCTAssertEqual(buggyResolution.codeVerifier, webviewVerifier,
                        "When incorrectly treated as social login, the wrong verifier from webview is used")
        XCTAssertEqual(buggyResolution.source, "webview_local_storage")

        XCTAssertEqual(correctResolution.codeVerifier, nativeVerifier,
                        "When correctly treated as regular OAuth, the native verifier from CredentialManager is used")
        XCTAssertEqual(correctResolution.source, "state_match")

        XCTAssertNotEqual(buggyResolution.codeVerifier, correctResolution.codeVerifier,
                           "The bug caused a different (wrong) code_verifier to be sent to /oauth/token")
    }

    func test_socialLogin_stillUsesWebviewVerifier() async {
        // Regression test: actual social logins (Google, Microsoft) should still use webview localStorage
        let nativeVerifier = "native-verifier"
        let webviewVerifier = "social-pkce-webview-verifier"
        CredentialManager.registerPendingOAuth(state: "social-state", codeVerifier: nativeVerifier)

        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: true, // Social login correctly identified
            oauthState: "social-state",
            socialVerifierProvider: {
                return webviewVerifier
            }
        )

        XCTAssertEqual(resolution.codeVerifier, webviewVerifier,
                        "Social login flows should use the code_verifier from webview localStorage")
        XCTAssertEqual(resolution.source, "webview_local_storage")
    }

    func test_socialLogin_fallsBackToCredentialManager_whenWebviewFails() async {
        // If webview localStorage is unavailable, social login should fall back to CredentialManager
        let nativeVerifier = "fallback-native-verifier"
        CredentialManager.registerPendingOAuth(state: "social-state", codeVerifier: nativeVerifier)

        let resolution = await CustomWebView.resolveHostedCallbackCodeVerifier(
            isMagicLink: false,
            isSocialLogin: true,
            oauthState: "social-state",
            socialVerifierProvider: {
                throw URLError(.cannotFindHost)
            }
        )

        XCTAssertEqual(resolution.codeVerifier, nativeVerifier,
                        "When webview localStorage fails, social login should fall back to CredentialManager")
        XCTAssertEqual(resolution.source, "state_match")
        XCTAssertNotNil(resolution.providerError)
    }

    private func clearOAuthState() {
        UserDefaults.standard.removeObject(forKey: KeychainKeys.codeVerifier.rawValue)
        UserDefaults.standard.removeObject(forKey: KeychainKeys.oauthStateVerifiers.rawValue)
        SocialLoginUrlGenerator.shared.clearPendingSocialCodeVerifiers()
    }

    private func makeRawSocialState(
        provider: String,
        appId: String,
        action: String,
        oauthState: String? = nil
    ) throws -> String {
        var payload: [String: String] = [
            "provider": provider,
            "appId": appId,
            "action": action,
            "bundleId": "com.frontegg.tests",
            "platform": "ios"
        ]

        if let oauthState {
            payload["oauthState"] = oauthState
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
