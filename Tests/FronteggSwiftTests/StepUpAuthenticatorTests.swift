//
//  StepUpAuthenticatorTests.swift
//  FronteggSwiftTests
//
//  Regression coverage for `StepUpAuthenticator` — in particular the embedded
//  mode routing fix where `stepUp(...)` must reuse the SDK's WKWebView session
//  instead of opening `ASWebAuthenticationSession` (which lives in
//  `SafariViewService` with a separate cookie jar and forces a full re-login).
//

import XCTest
@testable import FronteggSwift

final class StepUpAuthenticatorTests: XCTestCase {

    private let testBaseUrl = "https://test.frontegg.com"
    private let testClientId = "test-step-up-client"

    private var stepUpAuthenticator: StepUpAuthenticator!
    private var mockCredentialManager: MockCredentialManager!

    private var savedEmbeddedMode: Bool = true
    private var savedActiveFlow: FronteggOAuthFlow = .login
    private var savedPendingAppLink: URL?
    private var savedLoginCompletion: FronteggAuth.CompletionHandler?

    override func setUp() {
        super.setUp()

        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: testBaseUrl, clientId: testClientId)),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: testBaseUrl, cliendId: testClientId)
        CredentialManager.clearPendingOAuthFlows()

        mockCredentialManager = MockCredentialManager()
        stepUpAuthenticator = StepUpAuthenticator(credentialManager: mockCredentialManager)

        let auth = FronteggAuth.shared
        savedEmbeddedMode = auth.embeddedMode
        savedActiveFlow = auth.activeEmbeddedOAuthFlow
        savedPendingAppLink = auth.pendingAppLink
        savedLoginCompletion = auth.loginCompletion

        auth.activeEmbeddedOAuthFlow = .login
        auth.pendingAppLink = nil
        auth.loginCompletion = nil
        auth.setIsStepUpAuthorization(false)
        auth.setIsLoading(true)
        auth.setWebLoading(false)
    }

    override func tearDown() {
        let auth = FronteggAuth.shared
        auth.embeddedMode = savedEmbeddedMode
        auth.activeEmbeddedOAuthFlow = savedActiveFlow
        auth.pendingAppLink = savedPendingAppLink
        auth.loginCompletion = savedLoginCompletion
        auth.setIsStepUpAuthorization(false)
        auth.setIsLoading(true)
        auth.setWebLoading(true)

        CredentialManager.clearPendingOAuthFlows()
        PlistHelper.testConfigOverride = nil
        stepUpAuthenticator = nil
        mockCredentialManager = nil

        super.tearDown()
    }

    // MARK: - isSteppedUp(maxAge:)

    func test_isSteppedUp_returns_false_when_no_access_token() {
        mockCredentialManager.accessToken = nil
        XCTAssertFalse(stepUpAuthenticator.isSteppedUp())
    }

    func test_isSteppedUp_returns_false_when_access_token_is_not_a_valid_jwt() {
        mockCredentialManager.accessToken = "not-a-jwt"
        XCTAssertFalse(stepUpAuthenticator.isSteppedUp())
    }

    func test_isSteppedUp_returns_true_for_stepped_up_jwt() {
        mockCredentialManager.accessToken = makeAccessToken(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )

        XCTAssertTrue(stepUpAuthenticator.isSteppedUp())
    }

    func test_isSteppedUp_returns_false_when_acr_is_missing() {
        mockCredentialManager.accessToken = makeAccessToken(
            authTime: Date().timeIntervalSince1970,
            acr: nil,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )

        XCTAssertFalse(stepUpAuthenticator.isSteppedUp())
    }

    func test_isSteppedUp_returns_false_when_amr_does_not_contain_mfa_value() {
        mockCredentialManager.accessToken = makeAccessToken(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: ["otp"]
        )

        XCTAssertFalse(stepUpAuthenticator.isSteppedUp())
    }

    func test_isSteppedUp_returns_false_when_amr_has_no_additional_factor() {
        mockCredentialManager.accessToken = makeAccessToken(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE]
        )

        XCTAssertFalse(stepUpAuthenticator.isSteppedUp())
    }

    func test_isSteppedUp_returns_true_when_auth_time_within_maxAge() {
        mockCredentialManager.accessToken = makeAccessToken(
            authTime: Date().timeIntervalSince1970 - 60,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )

        XCTAssertTrue(stepUpAuthenticator.isSteppedUp(maxAge: 3600))
    }

    func test_isSteppedUp_returns_false_when_auth_time_exceeds_maxAge() {
        mockCredentialManager.accessToken = makeAccessToken(
            authTime: Date().timeIntervalSince1970 - 7200,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )

        XCTAssertFalse(stepUpAuthenticator.isSteppedUp(maxAge: 3600))
    }

    // MARK: - stepUp(...) routing — regression for embedded mode session reuse

    /// In embedded mode the user is already authenticated inside the SDK's
    /// `WKWebView` (its cookie jar holds the Frontegg session cookie). The
    /// previous implementation always launched `ASWebAuthenticationSession`,
    /// which runs in `SafariViewService` with an isolated cookie store and
    /// therefore demanded a full re-login instead of just the MFA challenge.
    ///
    /// This test guarantees the embedded branch sets up the embedded WebView
    /// to navigate to the step-up authorize URL — mirroring the MFA flow and
    /// the Android SDK's `StepUpAuthenticator.authenticateWithStepUp`.
    func test_stepUp_in_embeddedMode_routes_through_embedded_webview() throws {
        let auth = FronteggAuth.shared
        auth.embeddedMode = true

        stepUpAuthenticator.stepUp(maxAge: 60) { _ in /* ignored — embeddedLogin no-ops without a host app under XCTest */ }

        waitForMainQueue()

        XCTAssertTrue(
            auth.isStepUpAuthorization,
            "isStepUpAuthorization must be set so EmbeddedLoginModal does not auto-dismiss"
        )
        XCTAssertFalse(
            auth.isLoading,
            "Global isLoading must be cleared before handing off to the embedded WebView"
        )
        XCTAssertEqual(
            auth.activeEmbeddedOAuthFlow,
            .stepUp,
            "Embedded OAuth callback handler must classify the running flow as .stepUp"
        )
        XCTAssertTrue(
            auth.webLoading,
            "Embedded WebView loader must be shown while it navigates to the step-up URL"
        )

        let pendingAppLink = try XCTUnwrap(
            auth.pendingAppLink,
            "Embedded WKWebView must be redirected to the step-up authorize URL — without this it would never trigger MFA"
        )

        let components = URLComponents(url: pendingAppLink, resolvingAgainstBaseURL: false)
        let params = components?.queryItems?.reduce(into: [String: String]()) { acc, item in
            acc[item.name] = item.value
        } ?? [:]

        XCTAssertTrue(
            pendingAppLink.absoluteString.hasPrefix("\(testBaseUrl)/oauth/authorize"),
            "Step-up authorize URL must point at /oauth/authorize, got: \(pendingAppLink.absoluteString)"
        )
        XCTAssertEqual(
            params["acr_values"],
            StepUpConstants.ACR_VALUE,
            "Step-up URL must carry the step-up ACR value so the hosted page renders the MFA challenge"
        )
        XCTAssertEqual(
            params["max_age"],
            "60",
            "Step-up URL must propagate the maxAge requested by the host app (OIDC integer seconds)"
        )
        XCTAssertNil(
            params["prompt"],
            "Step-up must not include prompt=login (would force a fresh login instead of just MFA)"
        )
    }

    /// Step-up now ALWAYS routes through the embedded bridge WebView — like the
    /// Admin Portal — regardless of the app's login mode. The embedded WebView can
    /// reuse the existing native session via the getTokens bridge, while a system
    /// browser (ASWebAuthenticationSession) cannot, which white-pages / forces a
    /// second login for hosted-login apps. So even with `embeddedMode = false`
    /// the embedded-WebView routing state must be set up.
    func test_stepUp_in_nonEmbeddedMode_also_routes_through_embedded_webview() throws {
        let auth = FronteggAuth.shared
        auth.embeddedMode = false

        stepUpAuthenticator.stepUp(maxAge: 30) { _ in /* embeddedLogin no-ops without a host app under XCTest */ }

        waitForMainQueue()

        XCTAssertTrue(
            auth.isStepUpAuthorization,
            "isStepUpAuthorization must be set for the step-up flow"
        )
        XCTAssertFalse(
            auth.isLoading,
            "Global isLoading must be cleared before handing off to the embedded WebView"
        )
        XCTAssertEqual(
            auth.activeEmbeddedOAuthFlow,
            .stepUp,
            "Step-up now always uses the embedded WebView, so the flow is .stepUp even when embeddedMode is false"
        )
        XCTAssertTrue(
            auth.webLoading,
            "Embedded WebView loader must be shown while it navigates to the step-up URL"
        )

        let pendingAppLink = try XCTUnwrap(
            auth.pendingAppLink,
            "Step-up must push the authorize URL as pendingAppLink for the embedded WebView, even in non-embedded mode"
        )
        XCTAssertTrue(
            pendingAppLink.absoluteString.hasPrefix("\(testBaseUrl)/oauth/authorize"),
            "Step-up authorize URL must point at /oauth/authorize, got: \(pendingAppLink.absoluteString)"
        )
    }

    // MARK: - Helpers

    /// Drains queued `DispatchQueue.main.async` blocks scheduled by
    /// `StepUpAuthenticator.stepUp(...)`. Tests run on the main thread, so a
    /// brief expectation + main-queue async hop is enough to ensure all the
    /// dispatched side effects have executed before assertions.
    private func waitForMainQueue() {
        let drained = expectation(description: "stepUp main-queue side effects")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2.0)
    }

    private func makeAccessToken(authTime: Double?, acr: String?, amr: [String]?) -> String {
        var payload: [String: Any] = ["sub": "test-user"]
        if let authTime { payload["auth_time"] = authTime }
        if let acr { payload["acr"] = acr }
        if let amr { payload["amr"] = amr }

        let header: [String: Any] = ["alg": "none", "typ": "JWT"]
        return [base64UrlJson(header), base64UrlJson(payload), "signature"].joined(separator: ".")
    }

    private func base64UrlJson(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Mocks

/// CredentialManager subclass that intercepts only `get(key:)` for the access
/// token key. Everything else falls through to the base implementation. Using
/// a subclass keeps the `isSteppedUp(...)` tests independent of the keychain
/// (which is flaky in the iOS Simulator due to missing entitlements).
private final class MockCredentialManager: CredentialManager {

    var accessToken: String?

    init() {
        super.init(serviceKey: "frontegg-step-up-tests")
    }

    override func get(key: String) throws -> String? {
        if key == KeychainKeys.accessToken.rawValue {
            return accessToken
        }
        return try super.get(key: key)
    }
}
