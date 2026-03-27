//
//  AuthorizeUrlGeneratorTests.swift
//  FronteggSwiftTests
//

import XCTest
import CryptoKit
@testable import FronteggSwift

final class AuthorizeUrlGeneratorTests: XCTestCase {

    private let testBaseUrl = "https://test.frontegg.com"
    private let testClientId = "test-client-id-123"

    override func setUp() {
        super.setUp()
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(
                .init(baseUrl: testBaseUrl, clientId: testClientId)
            ),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(
            baseUrl: testBaseUrl,
            cliendId: testClientId,
            applicationId: nil
        )
        // Clear any pending OAuth state from prior tests
        CredentialManager.clearPendingOAuthFlows()
    }

    override func tearDown() {
        CredentialManager.clearPendingOAuthFlows()
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func queryItems(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        var dict: [String: String] = [:]
        for item in items {
            dict[item.name] = item.value
        }
        return dict
    }

    // MARK: - Default generate()

    func test_generate_default_produces_valid_authorize_url() {
        let (url, _) = AuthorizeUrlGenerator.shared.generate()
        let params = queryItems(from: url)

        XCTAssertTrue(url.path.hasSuffix("/oauth/authorize"), "Path should end with /oauth/authorize, got: \(url.path)")
        XCTAssertNotNil(params["redirect_uri"])
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["client_id"], testClientId)
        XCTAssertEqual(params["scope"], "openid email profile")
        XCTAssertNotNil(params["code_challenge"])
        XCTAssertEqual(params["code_challenge_method"], "S256")
        XCTAssertNotNil(params["nonce"])
        XCTAssertNotNil(params["state"])
        XCTAssertEqual(params["prompt"], "login")
    }

    func test_generate_returns_codeVerifier_and_registers_pending_oauth() {
        let (url, codeVerifier) = AuthorizeUrlGenerator.shared.generate()
        let params = queryItems(from: url)

        XCTAssertFalse(codeVerifier.isEmpty)

        let state = params["state"]!
        let resolved = CredentialManager.getCodeVerifier(for: state)
        XCTAssertEqual(resolved, codeVerifier)
    }

    // MARK: - loginHint

    func test_generate_with_loginHint_adds_param() {
        let (url, _) = AuthorizeUrlGenerator.shared.generate(loginHint: "user@example.com")
        let params = queryItems(from: url)
        XCTAssertEqual(params["login_hint"], "user@example.com")
    }

    func test_generate_with_loginHint_plus_encoding() {
        let (url, _) = AuthorizeUrlGenerator.shared.generate(loginHint: "user+tag@example.com")
        // The + should be percent-encoded in the URL
        XCTAssertTrue(url.absoluteString.contains("%2B"), "Plus sign should be encoded as %2B, got: \(url.absoluteString)")
    }

    // MARK: - loginAction

    func test_generate_with_loginAction_adds_param() {
        let action = "eyJ0eXBlIjoiZGlyZWN0In0=" // base64 encoded action
        let (url, _) = AuthorizeUrlGenerator.shared.generate(loginAction: action)
        let params = queryItems(from: url)
        XCTAssertEqual(params["login_direct_action"], action)
    }

    // MARK: - stepUp

    func test_generate_stepUp_adds_acr_values_omits_prompt() {
        let (url, _) = AuthorizeUrlGenerator.shared.generate(stepUp: true)
        let params = queryItems(from: url)
        XCTAssertEqual(params["acr_values"], StepUpConstants.ACR_VALUE)
        XCTAssertNil(params["prompt"], "stepUp should not include prompt param")
    }

    func test_generate_stepUp_with_maxAge_adds_param() {
        let (url, _) = AuthorizeUrlGenerator.shared.generate(stepUp: true, maxAge: 300)
        let params = queryItems(from: url)
        XCTAssertEqual(params["max_age"], "300.0")
    }

    // MARK: - organization

    func test_generate_with_organization_adds_param() {
        let (url, _) = AuthorizeUrlGenerator.shared.generate(organization: "acme-corp")
        let params = queryItems(from: url)
        XCTAssertEqual(params[AuthorizeUrlGenerator.organizationQueryParameterName], "acme-corp")
    }

    func test_generate_organization_nil_uses_app_alias() {
        FronteggApp.shared.loginOrganizationAlias = "default-org"
        let (url, _) = AuthorizeUrlGenerator.shared.generate()
        let params = queryItems(from: url)
        XCTAssertEqual(params[AuthorizeUrlGenerator.organizationQueryParameterName], "default-org")
        FronteggApp.shared.loginOrganizationAlias = nil
    }

    // MARK: - remainCodeVerifier

    func test_generate_remainCodeVerifier_reuses_existing() {
        CredentialManager.saveCodeVerifier("existing-verifier-abc")
        let (_, codeVerifier) = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: true)
        XCTAssertEqual(codeVerifier, "existing-verifier-abc")
    }

    func test_generate_remainCodeVerifier_false_generates_new() {
        CredentialManager.saveCodeVerifier("old-verifier")
        let (_, codeVerifier) = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: false)
        XCTAssertNotEqual(codeVerifier, "old-verifier")
    }

    // MARK: - registerPendingFlow

    func test_generate_registerPendingFlow_false_does_not_register() {
        CredentialManager.clearPendingOAuthFlows()
        let _ = AuthorizeUrlGenerator.shared.generate(registerPendingFlow: false)
        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
    }

    // MARK: - PKCE validation

    func test_generate_code_challenge_is_valid_s256() {
        let (url, codeVerifier) = AuthorizeUrlGenerator.shared.generate()
        let params = queryItems(from: url)
        let codeChallenge = params["code_challenge"]!

        // Independently compute SHA256 base64url of codeVerifier
        let verifierData = Data(codeVerifier.utf8)
        let hash = SHA256.hash(data: verifierData)
        let expected = Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        XCTAssertEqual(codeChallenge, expected, "code_challenge should be S256 of code_verifier")
    }

    // MARK: - Uniqueness

    func test_generate_nonce_and_state_unique_across_calls() {
        let (url1, _) = AuthorizeUrlGenerator.shared.generate(registerPendingFlow: false)
        let (url2, _) = AuthorizeUrlGenerator.shared.generate(registerPendingFlow: false)
        let params1 = queryItems(from: url1)
        let params2 = queryItems(from: url2)

        XCTAssertNotEqual(params1["nonce"], params2["nonce"])
        XCTAssertNotEqual(params1["state"], params2["state"])
    }
}
