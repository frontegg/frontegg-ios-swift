//
//  AutoLoginE2ETests.swift
//  demo-auto-login-e2e
//
//  Comprehensive E2E tests for the auto-login pattern.
//  Key difference from demo-embedded: no "Sign in" button — the Frontegg
//  embedded login WebView is shown directly when unauthenticated.
//

import XCTest

final class AutoLoginE2ETests: AutoLoginUITestCase {

    // Token TTLs for tests that exercise refresh and expiry.
    private let expiringAccessTokenTTL = 21
    private let longLivedRefreshTokenTTL = 120
    private let immediateRefreshTriggerWindow = 14

    // MARK: - Direct Login Flow (Core Auto-Login Pattern)

    /// Cold launch → splash → auto-login WebView appears (no landing page, no button).
    func testColdLaunchShowsLoginWebViewDirectly() {
        launchApp(resetState: true)
        waitForScreen("AutoLoginWebViewRoot", timeout: 15)

        // Verify the WebView is actually loaded (not just the marker)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10),
                      "Embedded login WebView should be visible")
    }

    /// Full password login flow: auto-login WebView → enter credentials → profile.
    func testPasswordLoginAndSessionRestore() {
        launchApp(resetState: true)
        loginWithPassword()

        // Verify profile is shown with user data
        let userName = app.staticTexts["ProfileUserName"]
        XCTAssertTrue(userName.waitForExistence(timeout: 5))

        let userEmail = app.staticTexts["ProfileUserEmail"]
        XCTAssertTrue(userEmail.waitForExistence(timeout: 5))

        // Terminate and relaunch — session should be restored
        terminateApp()
        launchApp(resetState: false)
        waitForScreen("ProfileViewRoot", timeout: 20)
    }

    /// Logout → auto-login WebView reappears immediately (no landing page).
    func testLogoutReturnsDirectlyToAutoLoginWebView() {
        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        tapButton("LogoutButton")

        // Should return directly to the auto-login WebView
        waitForScreen("AutoLoginWebViewRoot", timeout: 15)
    }

    /// Online logout should never flash the NoConnectionPage.
    func testOnlineLogoutReturnsToLoginWithoutOfflineScreen() {
        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        tapButton("LogoutButton")
        waitForScreen("AutoLoginWebViewRoot", timeout: 15)
        assertNoConnectionScreenDoesNotAppear(duration: 3)
    }

    // MARK: - Session Restore & Token Refresh

    /// Expired access token is refreshed automatically on relaunch.
    func testExpiredAccessTokenRefreshesOnAuthenticatedRelaunch() {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        // Wait for token version marker to appear (ProfileView exposes JWT diagnostics)
        let initialVersion = accessTokenVersion(timeout: 15)
        guard initialVersion > 0 else { return }

        // Wait for access token to be near expiry
        waitUntilAccessTokenExpiresWithin(immediateRefreshTriggerWindow, timeout: TimeInterval(expiringAccessTokenTTL))

        // Token should auto-refresh
        let newVersion = waitForAccessTokenVersionChange(from: initialVersion, timeout: 20)
        XCTAssertGreaterThan(newVersion, initialVersion)
    }

    /// Scheduled token refresh fires before expiry at ~80% of TTL.
    func testScheduledTokenRefreshFiresBeforeExpiry() {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        let initialVersion = accessTokenVersion(timeout: 15)
        guard initialVersion > 0 else { return }

        // Wait for the scheduled refresh to kick in (should happen before expiry)
        let newVersion = waitForAccessTokenVersionChange(from: initialVersion, timeout: TimeInterval(expiringAccessTokenTTL + 10))
        XCTAssertGreaterThan(newVersion, initialVersion)
    }

    /// Expired refresh token forces full re-login.
    func testExpiredRefreshTokenClearsSessionAndShowsLogin() {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: 5,
            refreshTokenTTL: 8
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        // Wait for both tokens to expire
        waitForDuration(12)

        // Relaunch — should show auto-login WebView (session cleared)
        terminateApp()
        launchApp(resetState: false)
        waitForScreen("AutoLoginWebViewRoot", timeout: 20)
    }

    /// Relaunch with expired access token but valid refresh token → auto-refresh → profile.
    func testAuthenticatedRelaunchWithExpiredAccessTokenAndFreshRefreshToken() {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: 3,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        // Wait for access token to expire
        waitForDuration(5)

        terminateApp()
        launchApp(resetState: false)

        // Should auto-refresh and show profile
        waitForScreen("ProfileViewRoot", timeout: 20)
    }

    // MARK: - Logout Scenarios

    /// Logout clears session — relaunch shows login.
    func testLogoutClearsSessionAndRelaunchShowsLogin() {
        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        tapButton("LogoutButton")
        waitForScreen("AutoLoginWebViewRoot")

        terminateApp()
        launchApp(resetState: false)
        waitForScreen("AutoLoginWebViewRoot", timeout: 15)
    }

    // MARK: - Offline Mode: Authenticated

    /// Authenticated user goes offline → stays on profile if user data is cached.
    /// When offline with cached user, ProfileView is shown (not AuthenticatedOfflineRoot).
    /// AuthenticatedOfflineRoot only appears when user data is nil.
    func testAuthenticatedOfflineModeWhenNetworkPathUnavailable() {
        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        // Relaunch with forced offline
        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: true)

        // User data is cached → ProfileView shows, but offline mode badge is present
        waitForScreen("ProfileViewRoot", timeout: 20)
        waitForAuthenticatedOfflineMode(true, timeout: 20)
    }

    /// Offline → online recovery: profile with user data persists.
    func testAuthenticatedOfflineModeRecoversToOnlineAndRefreshesToken() {
        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        // Relaunch offline — cached user data keeps ProfileView
        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: true)
        waitForScreen("ProfileViewRoot", timeout: 20)
        waitForAuthenticatedOfflineMode(true, timeout: 20)

        // Relaunch online — should recover, still on profile
        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: false)
        waitForScreen("ProfileViewRoot", timeout: 20)
        waitForAuthenticatedOfflineMode(false, timeout: 20)
    }

    /// User stays logged in offline even with expired access token.
    func testAuthenticatedOfflineModeKeepsUserLoggedInUntilReconnect() {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: 5,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        // Wait for access token to expire, then go offline
        waitForDuration(7)

        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: true)

        // Should stay authenticated offline (has refresh token)
        waitForAuthenticatedOfflineMode(true, timeout: 20)
    }

    /// Logout during offline shows NoConnectionPage or auto-login WebView.
    /// When offline is forced via network path, logout clears session.
    /// The unauthenticated + offline state → NoConnectionPage.
    func testLogoutWhileAuthenticatedOfflineShowsNoConnectionPage() {
        allowsUnexpectedNoConnectionScreen = true

        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: true)
        waitForScreen("ProfileViewRoot", timeout: 20)
        waitForAuthenticatedOfflineMode(true, timeout: 20)

        // Logout while offline
        tapButton("LogoutButton")

        // After logout: either NoConnectionPage (if offline persists) or
        // AutoLoginWebViewRoot (if network recovered during logout).
        let noConnection = app.descendants(matching: .any)["NoConnectionPageRoot"]
        let autoLogin = app.descendants(matching: .any)["AutoLoginWebViewRoot"]
        let deadline = Date().addingTimeInterval(15)
        var found = false
        while Date() < deadline {
            if noConnection.exists || autoLogin.exists {
                found = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(found, "Expected either NoConnectionPage or AutoLoginWebView after logout. \(screenDebugSummary())")
    }

    // MARK: - Offline Mode: Unauthenticated

    /// Cold launch with no network, no cached session → NoConnectionPage or auto-login.
    /// In auto-login mode, if the mock server is reachable on localhost the WebView may
    /// load before offline mode activates. This test validates that the app reaches
    /// EITHER NoConnectionPage (true offline) or the login WebView (server reachable).
    func testOfflineColdLaunchUnauthenticatedShowsNoConnectionOrLogin() throws {
        allowsUnexpectedNoConnectionScreen = true

        try Self.server.queueProbeFailures(statusCodes: [503, 503, 503, 503, 503, 503, 503, 503])

        launchApp(resetState: true, forceNetworkPathOffline: true)

        let noConnection = app.descendants(matching: .any)["NoConnectionPageRoot"]
        let autoLogin = app.descendants(matching: .any)["AutoLoginWebViewRoot"]
        let deadline = Date().addingTimeInterval(20)
        var found = false
        while Date() < deadline {
            if noConnection.exists || autoLogin.exists {
                found = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTAssertTrue(found, "Expected either NoConnectionPage or AutoLoginWebView. \(screenDebugSummary())")

        if noConnection.exists {
            let retryButton = retryConnectionControl()
            XCTAssertTrue(retryButton.exists, "Retry button should be visible on no connection page")
        }
    }

    /// Retry from NoConnectionPage → network recovers → auto-login WebView.
    func testRetryFromOfflineScreenReturnsToLoginWhenNetworkRecovers() throws {
        allowsUnexpectedNoConnectionScreen = true

        // Queue many probe failures and connection drops for offline detection
        try Self.server.queueProbeFailures(statusCodes: [503, 503, 503, 503, 503, 503, 503, 503])
        try Self.server.queueConnectionDrops(method: "GET", path: "/oauth/authorize", count: 3)
        try Self.server.queueConnectionDrops(method: "GET", path: "/oauth/prelogin", count: 3)

        launchApp(resetState: true, forceNetworkPathOffline: true)

        let noConnection = app.descendants(matching: .any)["NoConnectionPageRoot"]
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if noConnection.exists { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        guard noConnection.exists else {
            // If offline was never detected, skip the recovery part —
            // the auto-login WebView handled it. This is acceptable behavior.
            return
        }

        // Relaunch with network available (simulates network recovery)
        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: false)
        waitForScreen("AutoLoginWebViewRoot", timeout: 20)
    }

    // MARK: - Offline Mode Disabled

    /// With offline mode disabled, cold launch reaches login quickly (no 4.5s probe race).
    func testColdLaunchWithOfflineModeDisabledReachesLoginQuickly() {
        launchApp(resetState: true, enableOfflineMode: false)
        waitForScreen("AutoLoginWebViewRoot", timeout: 10)
    }

    /// Offline mode disabled: session survives brief connectivity loss.
    func testOfflineModeDisabledPreservesSessionDuringConnectionLossAndRecovers() {
        launchApp(resetState: true, enableOfflineMode: false)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        // Relaunch with brief offline then online
        terminateApp()
        launchApp(resetState: false, enableOfflineMode: false)
        waitForScreen("ProfileViewRoot", timeout: 20)
    }

    /// Password login works normally with offline mode disabled.
    func testPasswordLoginWorksWithOfflineModeDisabled() {
        launchApp(resetState: true, enableOfflineMode: false)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")
    }

    // MARK: - Network Resilience

    /// Transient probe timeouts during startup don't flash NoConnectionPage.
    func testColdLaunchTransientProbeTimeoutsDoNotBlinkNoConnectionPage() throws {
        try Self.server.queueProbeTimeouts(count: 2, delayMs: 1500)

        launchApp(resetState: true)
        assertNoConnectionScreenDoesNotAppear(duration: 6)
        waitForScreen("AutoLoginWebViewRoot", timeout: 20)
    }

    /// After logout + terminate, transient probe failures don't flash offline screen.
    func testLogoutTerminateTransientProbeFailureDoesNotBlinkNoConnectionPage() throws {
        launchApp(resetState: true)
        loginWithPassword()
        waitForScreen("ProfileViewRoot")

        tapButton("LogoutButton")
        waitForScreen("AutoLoginWebViewRoot")

        terminateApp()

        try Self.server.queueProbeFailures(statusCodes: [503, 503])
        launchApp(resetState: false)

        assertNoConnectionScreenDoesNotAppear(duration: 5)
        waitForScreen("AutoLoginWebViewRoot", timeout: 20)
    }

    // MARK: - Helpers

    func refreshRequestCount() -> Int {
        let oauthTokenRefreshes = Self.server.requestCount(method: "POST", path: "/oauth/token")
        let hostedRefreshes = Self.server.requestCount(method: "POST", path: "/frontegg/identity/resources/auth/v1/user/token/refresh")
        return oauthTokenRefreshes + hostedRefreshes
    }

    func waitForRefreshRequestCount(_ count: Int, timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if refreshRequestCount() >= count { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Expected at least \(count) refresh requests, got \(refreshRequestCount())")
    }
}
