import XCTest

final class DemoEmbeddedE2ETests: DemoEmbeddedUITestCase {
    private let expiringAccessTokenTTL = 21
    private let longLivedRefreshTokenTTL = 120
    private let immediateRefreshTriggerWindow = 14
    private let refreshTokenPaths = [
        "/oauth/token",
        "/frontegg/identity/resources/auth/v1/user/token/refresh"
    ]

    private func refreshRequestCount() -> Int {
        refreshTokenPaths.reduce(0) { total, path in
            total + Self.server.requestCount(path: path)
        }
    }

    private func waitForRefreshRequestCount(
        atLeast count: Int,
        timeout: TimeInterval = 10
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if refreshRequestCount() >= count {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail(
            "Expected refresh request count >= \(count), got \(refreshRequestCount()). \(screenDebugSummary())"
        )
    }

    private func queueRefreshConnectionDrops(count: Int = 1) throws {
        for path in refreshTokenPaths {
            try Self.server.queueConnectionDrops(path: path, count: count)
        }
    }

    func testPasswordLoginAndSessionRestore() throws {
        launchApp(resetState: true)
        loginWithPassword()

        terminateApp()
        launchApp(resetState: false)
        waitForUserEmail("test@frontegg.com")
    }

    func testEmbeddedSamlLogin() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedSAMLButton")
        app.getWebLabel("OKTA SAML Mock Server").waitUntilExists()
        app.getWebButton("Login With Okta").safeTap()
        waitForUserEmail("test@saml-domain.com")
    }

    func testEmbeddedOidcLogin() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedOIDCButton")
        app.getWebLabel("OKTA OIDC Mock Server").waitUntilExists()
        app.getWebButton("Login With Okta").safeTap()
        waitForUserEmail("test@oidc-domain.com")
    }

    func testRequestAuthorizeFlow() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")
        tapButton("E2ESeedRequestAuthorizeTokenButton")
        tapButton("RequestAuthorizeButton")
        waitForUserEmail("signup@frontegg.com")
    }

    func testCustomSSOBrowserHandoff() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")
        tapButton("E2ECustomSSOButton")
        acceptSystemDialogIfNeeded()
        app.getWebLabel("Custom SSO Mock Server").waitUntilExists(timeout: 20)
        app.getWebButton("Continue to Custom SSO").safeTap()
        waitForUserEmail("custom-sso@frontegg.com")
    }

    func testDirectSocialBrowserHandoff() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")
        tapButton("E2EDirectSocialLoginButton")
        acceptSystemDialogIfNeeded()
        app.getWebLabel("Mock Social Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Social").safeTap()
        waitForUserEmail("social-login@frontegg.com")
    }

    func testEmbeddedGoogleSocialLoginWithSystemWebAuthenticationSession() throws {
        launchApp(resetState: true, useTestingWebAuthenticationTransport: false)
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 10)
        waitForUserEmail("google-social@frontegg.com", timeout: 30)
    }

    func testEmbeddedGoogleSocialLoginOAuthErrorShowsToastAndKeepsLoginOpen() throws {
        Self.server.queueEmbeddedSocialSuccessOAuthError(
            errorCode: "ER-05001",
            errorDescription: "JWT token size exceeded the maximum allowed size. Please contact support to reduce token payload size."
        )

        launchApp(resetState: true, useTestingWebAuthenticationTransport: false)
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 2)

        XCTAssertTrue(
            Self.server.waitForRequestCount(path: "/oauth/account/social/success", count: 2, timeout: 20),
            screenDebugSummary()
        )
        let toast = waitForOAuthErrorToast(timeout: 20)
        let toastMessage = (toast.value as? String) ?? toast.label
        XCTAssertTrue(toastMessage.contains("ER-05001"), screenDebugSummary())
        XCTAssertTrue(toastMessage.contains("JWT token size exceeded"), screenDebugSummary())
        XCTAssertFalse(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())

        let continueButton = app.getWebButton("Continue").waitUntilExists(timeout: 20)
        XCTAssertTrue(continueButton.exists, screenDebugSummary())
    }

    func testColdLaunchTransientProbeTimeoutsDoNotBlinkNoConnectionPage() throws {
        try Self.server.queueProbeTimeouts(count: 2, delayMs: 1_500)

        launchApp(resetState: true)
        waitForScreen("LoginPageRoot", timeout: 15)
        assertNoConnectionScreenDoesNotAppear(duration: 2)
    }

    func testLogoutTerminateTransientProbeFailureDoesNotBlinkNoConnectionPage() throws {
        launchApp(resetState: true)
        loginWithPassword()

        let logoutButton = app.buttons["LogoutButton"]
        if logoutButton.exists {
            logoutButton.tap()
        } else {
            app.buttons["Logout"].waitUntilExists().safeTap()
        }
        waitForScreen("LoginPageRoot")

        try Self.server.queueProbeFailures(statusCodes: [503, 503])

        terminateApp()
        launchApp(resetState: false)
        waitForScreen("LoginPageRoot", timeout: 10)
        assertNoConnectionScreenDoesNotAppear(duration: 2)
    }

    func testAuthenticatedOfflineModeWhenNetworkPathUnavailable() throws {
        launchApp(resetState: true)
        loginWithPassword()
        let initialVersion = accessTokenVersion()

        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: true)
        waitForUserEmail("test@frontegg.com", timeout: 20)
        XCTAssertTrue(app.staticTexts["AuthenticatedOfflineModeEnabled"].waitForExistence(timeout: 5), screenDebugSummary())
        XCTAssertTrue(app.staticTexts["OfflineModeBadge"].waitForExistence(timeout: 5), screenDebugSummary())
        XCTAssertEqual(accessTokenVersion(), initialVersion, screenDebugSummary())
        XCTAssertFalse(app.buttons["RetryConnectionButton"].exists, screenDebugSummary())
    }

    func testExpiredAccessTokenRefreshesOnAuthenticatedRelaunch() throws {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()

        let initialVersion = accessTokenVersion()
        let initialRefreshCount = refreshRequestCount()

        terminateApp()
        waitForDuration(TimeInterval(expiringAccessTokenTTL + 2))

        launchApp(resetState: false)
        waitForUserEmail("test@frontegg.com", timeout: 20)

        let refreshedVersion = waitForAccessTokenVersionChange(from: initialVersion, timeout: 20)
        XCTAssertGreaterThan(refreshedVersion, initialVersion, screenDebugSummary())
        XCTAssertGreaterThan(refreshRequestCount(), initialRefreshCount, screenDebugSummary())
        XCTAssertFalse(app.staticTexts["AuthenticatedOfflineModeEnabled"].exists, screenDebugSummary())
        XCTAssertFalse(app.buttons["RetryConnectionButton"].exists, screenDebugSummary())
    }

    func testAuthenticatedOfflineModeRecoversToOnlineAndRefreshesToken() throws {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()

        waitUntilAccessTokenExpiresWithin(immediateRefreshTriggerWindow, timeout: 15)
        let initialVersion = accessTokenVersion()
        let initialRefreshCount = refreshRequestCount()

        try queueRefreshConnectionDrops()
        try Self.server.queueProbeFailures(statusCodes: Array(repeating: 503, count: 6))

        tapGetCurrentAccessTokenButton()
        waitForRefreshRequestCount(atLeast: initialRefreshCount + 1, timeout: 10)
        waitForAuthenticatedOfflineMode(true, timeout: 30)
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
        XCTAssertFalse(app.buttons["RetryConnectionButton"].exists, screenDebugSummary())

        let recoveredVersion = waitForAccessTokenVersionChange(from: initialVersion, timeout: 25)
        waitForAuthenticatedOfflineMode(false, timeout: 10)

        XCTAssertGreaterThan(recoveredVersion, initialVersion, screenDebugSummary())
        XCTAssertGreaterThanOrEqual(
            refreshRequestCount(),
            initialRefreshCount + 2,
            screenDebugSummary()
        )
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    func testAuthenticatedOfflineModeKeepsUserLoggedInUntilReconnectRefreshesExpiredToken() throws {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()

        waitUntilAccessTokenExpiresWithin(immediateRefreshTriggerWindow, timeout: 15)
        let initialVersion = accessTokenVersion()
        let initialRefreshCount = refreshRequestCount()

        try Self.server.queueProbeFailures(
            statusCodes: Array(repeating: 503, count: 25)
        )
        try queueRefreshConnectionDrops()

        tapGetCurrentAccessTokenButton()
        waitForRefreshRequestCount(atLeast: initialRefreshCount + 1, timeout: 10)
        waitForAuthenticatedOfflineMode(true, timeout: 30)
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
        XCTAssertFalse(app.buttons["RetryConnectionButton"].exists, screenDebugSummary())

        let accessTokenExpiration = accessTokenExpiration()
        let secondsUntilExpiry = max(accessTokenExpiration - Int(Date().timeIntervalSince1970), 0)
        waitForDuration(TimeInterval(secondsUntilExpiry + 2))
        XCTAssertGreaterThan(Int(Date().timeIntervalSince1970), accessTokenExpiration, screenDebugSummary())
        XCTAssertTrue(app.staticTexts["AuthenticatedOfflineModeEnabled"].exists, screenDebugSummary())
        XCTAssertTrue(app.staticTexts["OfflineModeBadge"].exists, screenDebugSummary())
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())

        let recoveredVersion = waitForAccessTokenVersionChange(from: initialVersion, timeout: 30)
        waitForAuthenticatedOfflineMode(false, timeout: 10)

        XCTAssertGreaterThan(recoveredVersion, initialVersion, screenDebugSummary())
        XCTAssertGreaterThanOrEqual(
            refreshRequestCount(),
            initialRefreshCount + 2,
            screenDebugSummary()
        )
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    func testLogoutTerminateTransientNoConnectionThenCustomSSORecovers() throws {
        allowsUnexpectedNoConnectionScreen = true
        launchApp(resetState: true)
        loginWithPassword()

        let logoutButton = app.buttons["LogoutButton"]
        if logoutButton.exists {
            logoutButton.tap()
        } else {
            app.buttons["Logout"].waitUntilExists().safeTap()
        }
        waitForScreen("LoginPageRoot")

        try Self.server.queueProbeFailures(statusCodes: [503, 503])

        app.terminate()
        launchApp(resetState: false)
        let noConnectionScreen = app.buttons["RetryConnectionButton"]
        if noConnectionScreen.waitForExistence(timeout: 5) {
            waitForScreen("NoConnectionPageRoot")
            app.terminate()
            try Self.server.reset()
            launchApp(resetState: false)
        }

        waitForScreen("LoginPageRoot")
        tapButton("E2ECustomSSOButton")
        acceptSystemDialogIfNeeded()
        app.getWebLabel("Custom SSO Mock Server").waitUntilExists(timeout: 20)
        app.getWebButton("Continue to Custom SSO").safeTap()
        waitForUserEmail("custom-sso@frontegg.com")
    }
}
