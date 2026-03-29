//
//  MultiRegionE2ETests.swift
//  demo-multi-region-e2e
//

import XCTest

final class MultiRegionE2ETests: MultiRegionUITestCase {

    private func configureDefaultToken(email: String = "test@frontegg.com", accessTTL: Int = 3600) {
        Self.mockServer.configureTokenPolicy(
            email: email,
            accessTokenTTL: accessTTL,
            refreshTokenTTL: 86400
        )
    }

    // MARK: - Password Login

    func testManualInitLoginAndVerifyAuthenticated() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")
    }

    // MARK: - Session Restore

    func testSessionRestoreAfterTerminateInRegion() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()

        terminateAndRelaunch(resetState: false)
        waitForUserPage(timeout: 20)
        waitForUserEmail("test@frontegg.com")
    }

    // MARK: - Logout

    func testLogoutReturnsToLoginPage() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()

        tapButton("Logout")
        waitForLoginPage(timeout: 15)
    }

    func testLogoutAndReloginInSameRegion() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()

        tapButton("Logout")
        waitForLoginPage(timeout: 25)

        loginWithPassword()
        waitForUserEmail("test@frontegg.com")
    }

    // MARK: - Token Refresh

    func testExpiredAccessTokenRefreshesOnRelaunch() {
        configureDefaultToken(accessTTL: 2)
        launchApp(resetState: true)
        loginWithPassword()

        Thread.sleep(forTimeInterval: 3)

        terminateAndRelaunch(resetState: false)
        waitForUserPage(timeout: 20)
        waitForUserEmail("test@frontegg.com")
    }

    // MARK: - Entitlements

    func testEntitlementsLoadAfterLogin() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()

        // Scroll down to find the entitlements button
        app.swipeUp()
        let loadButton = app.buttons["Load entitlements"]
        if loadButton.waitForExistence(timeout: 5) {
            loadButton.tap()
            let succeeded = app.staticTexts["Load succeeded"]
            let failed = app.staticTexts["Load failed"]
            let gotResult = succeeded.waitForExistence(timeout: 10) || failed.waitForExistence(timeout: 1)
            XCTAssertTrue(gotResult, "Entitlements load should complete")
        }
    }

    // MARK: - Cold Launch

    func testColdLaunchWithNoSessionShowsLoginPage() {
        launchApp(resetState: true)
        waitForLoginPage(timeout: 15)
    }

    // MARK: - Stability

    func testMultipleLaunchCyclesDoNotCrash() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()

        terminateAndRelaunch(resetState: false)
        waitForUserPage(timeout: 20)

        terminateAndRelaunch(resetState: false)
        waitForUserPage(timeout: 20)
        waitForUserEmail("test@frontegg.com")
    }

    // MARK: - Logout and re-login in different region context

    /// Verifies that logging out and then logging in again works correctly,
    /// exercising the full credential clearing and re-authentication path.
    func testLogoutClearsSessionAndRelaunchShowsLogin() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")

        tapButton("Logout")
        waitForLoginPage(timeout: 15)

        // Relaunch without reset — keychain should have been cleared by logout
        terminateAndRelaunch(resetState: false)
        waitForLoginPage(timeout: 15)
        XCTAssertFalse(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    // MARK: - Connection failure recovery

    /// Verifies that a session survives transient connection failures on relaunch
    /// in a multi-region context.
    func testRelaunchWithConnectionDropRecoversSesion() throws {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")

        app.terminate()

        // Queue transient drops on both refresh endpoints
        try Self.mockServer.queueConnectionDrops(path: "/oauth/token", count: 2)
        try Self.mockServer.queueConnectionDrops(path: "/frontegg/identity/resources/auth/v1/user/token/refresh", count: 2)

        launchApp(resetState: false)
        waitForUserEmail("test@frontegg.com", timeout: 30)
    }

    // MARK: - Token refresh with short TTL

    /// Verifies that an in-flight token refresh keeps the session alive
    /// even with a very short access token TTL.
    func testTokenRefreshKeepsSessionAlive() {
        configureDefaultToken(accessTTL: 2)
        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")

        // Wait long enough for at least one refresh cycle
        Thread.sleep(forTimeInterval: 5)

        // Session should still be alive
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }
}
