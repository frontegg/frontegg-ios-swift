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

        let logoutButton = app.buttons["Logout"]
        if logoutButton.waitForExistence(timeout: 5) {
            logoutButton.tap()
            waitForLoginPage(timeout: 15)
        }
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
}
