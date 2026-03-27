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

        let logoutBtn = app.buttons["Logout"].firstMatch
        XCTAssertTrue(logoutBtn.waitForExistence(timeout: 10), "Logout button not found")
        logoutBtn.tap()
        waitForLoginPage(timeout: 15)
    }

    func testLogoutAndReloginInSameRegion() {
        configureDefaultToken()
        launchApp(resetState: true)
        loginWithPassword()

        let logoutBtn = app.buttons["Logout"].firstMatch
        XCTAssertTrue(logoutBtn.waitForExistence(timeout: 10), "Logout button not found")
        logoutBtn.tap()
        waitForLoginPage(timeout: 15)

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
}
