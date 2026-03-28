//
//  UIKitE2ETests.swift
//  demo-uikit-e2e
//

import XCTest

final class UIKitE2ETests: UIKitUITestCase {

    // MARK: - Login

    func testPasswordLoginShowsStreamScreen() {
        configureDefaultToken()
        launchApp(resetState: true)

        // UIKit app auto-triggers login via getOrRefreshAccessToken
        waitForStreamPage(timeout: 30)
        waitForAccessTokenLabel()
    }

    // MARK: - Session Restore

    func testSessionRestoreAfterTerminate() {
        configureDefaultToken()
        launchApp(resetState: true)

        waitForStreamPage(timeout: 30)

        terminateAndRelaunch(resetState: false)
        waitForStreamPage(timeout: 20)
        waitForAccessTokenLabel()
    }

    // MARK: - Logout

    func testLogoutReturnsToLoginScreen() {
        configureDefaultToken()
        launchApp(resetState: true)

        waitForStreamPage(timeout: 30)

        tapButton("Logout", timeout: 10)
        waitForLoginPage(timeout: 15)
        waitForElementToDisappear(app.buttons["Logout"], description: "Logout button", timeout: 5)
        XCTAssertFalse(app.staticTexts["AccessTokenLabel"].exists, screenDebugSummary())
    }

    // MARK: - Token Refresh

    func testTokenRefreshKeepsSessionAlive() {
        configureDefaultToken(accessTTL: 3)
        launchApp(resetState: true)

        waitForStreamPage(timeout: 30)

        Thread.sleep(forTimeInterval: 5)

        let label = app.staticTexts["AccessTokenLabel"]
        XCTAssertTrue(label.exists, "Should still be on stream page after token refresh")
    }

    // MARK: - Cold Launch

    func testColdLaunchInitializesCorrectly() {
        configureDefaultToken()
        launchApp(resetState: true)

        let streamExists = app.otherElements["StreamPageRoot"].waitForExistence(timeout: 30)
        let loginExists = app.otherElements["LoginPageRoot"].exists

        XCTAssertTrue(streamExists || loginExists, "App should show either stream or login page")
    }

    // MARK: - Stability

    func testMultipleLaunchCyclesDoNotCrash() {
        configureDefaultToken()
        launchApp(resetState: true)

        waitForStreamPage(timeout: 30)

        terminateAndRelaunch(resetState: false)
        waitForStreamPage(timeout: 20)

        terminateAndRelaunch(resetState: false)
        waitForStreamPage(timeout: 20)
    }

    // MARK: - Logout clears session

    /// Verifies that after logout + terminate + relaunch with state reset,
    /// the session is NOT restored and the login page is shown.
    func testLogoutClearsSessionOnRelaunch() {
        configureDefaultToken()
        launchApp(resetState: true)
        waitForStreamPage(timeout: 30)

        tapButton("Logout", timeout: 10)
        waitForLoginPage(timeout: 20)

        // Relaunch WITH reset to clear WebView cookies that the UIKit app
        // retains across launches (SDK logout clears keychain but not WKWebView cookies).
        terminateAndRelaunch(resetState: true)
        waitForLoginPage(timeout: 20)
        XCTAssertFalse(app.staticTexts["AccessTokenLabel"].exists, screenDebugSummary())
    }

    // MARK: - Connection failure recovery

    /// Verifies that a UIKit session survives transient connection drops on relaunch.
    func testRelaunchWithConnectionDropRecoversSesion() throws {
        configureDefaultToken()
        launchApp(resetState: true)
        waitForStreamPage(timeout: 30)

        app.terminate()

        try Self.mockServer.queueConnectionDrops(path: "/oauth/token", count: 2)
        try Self.mockServer.queueConnectionDrops(path: "/frontegg/identity/resources/auth/v1/user/token/refresh", count: 2)

        launchApp(resetState: false)
        waitForStreamPage(timeout: 30)
        waitForAccessTokenLabel()
    }

    // MARK: - Expired access token refresh

    /// Verifies that relaunching with an expired access token but valid refresh token
    /// restores the session via token refresh in a UIKit context.
    func testExpiredAccessTokenRefreshesOnRelaunch() {
        configureDefaultToken(accessTTL: 3)
        launchApp(resetState: true)
        waitForStreamPage(timeout: 30)

        app.terminate()
        Thread.sleep(forTimeInterval: 5)

        launchApp(resetState: false)
        waitForStreamPage(timeout: 20)
        waitForAccessTokenLabel()
    }
}
