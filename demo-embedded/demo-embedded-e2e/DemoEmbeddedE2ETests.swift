import UIKit
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

    private func waitForRefreshRecoveryFlowToStart(
        refreshCountAtLeast count: Int,
        timeout: TimeInterval = 10
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let offlineMarkerVisible = app.staticTexts["AuthenticatedOfflineModeEnabled"].exists
            let refreshingTokenValue = app.staticTexts["AuthRefreshingTokenValue"]
            let isRefreshingToken = refreshingTokenValue.exists && refreshingTokenValue.label == "1"

            if refreshRequestCount() >= count || offlineMarkerVisible || isRefreshingToken {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected refresh recovery flow to start. \(screenDebugSummary())")
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

    func testEmbeddedStepUpMfaChallenge() throws {
        launchApp(resetState: true)
        loginWithPassword()
        Self.server.clearRequestLog()

        // Start a native step-up (acr_values + max_age) via the E2E step-up trigger. The embedded
        // box bootstraps on its prelogin path; the native StepUpWebDriver must route it to
        // /account/step-up so the (fixed) box renders the MFA challenge instead of a blank page.
        tapButton("E2EStepUpButton")

        // The stub step-up page renders "Step-Up MFA Mock" ONLY when the driver seeded
        // SHOULD_STEP_UP and rewrote the path to /account/step-up — so this assertion fails if
        // the driver did not inject/route (the production blank-page bug).
        XCTAssertTrue(
            Self.server.waitForRequest(method: "GET", path: "/oauth/prelogin", timeout: 20),
            "Expected the step-up flow to bootstrap the hosted prelogin page. \(screenDebugSummary())"
        )
        app.getWebLabel("Step-Up MFA Mock").waitUntilExists(timeout: 20)
        app.getWebButton("Complete Step-Up").waitUntilExists(timeout: 20).safeTap()

        // Completing the challenge navigates to the driver-seeded after-auth authorize URL,
        // which issues an elevated code that the native OAuth callback exchanges for a token.
        XCTAssertTrue(
            Self.server.waitForRequest(method: "POST", path: "/oauth/token", timeout: 20),
            "Expected the elevated authorization code to be exchanged for a token. \(screenDebugSummary())"
        )

        // The elevated token exchange above is the definitive step-up success signal — it is only
        // reachable because the native driver seeded the after-auth redirect and drove the stub's
        // challenge (which itself only renders when the driver's localStorage + /account/step-up
        // contract is honored). Assert a clean teardown: the step-up webview is dismissed and we
        // are back on the authenticated profile with no connection error.
        let webviewGone = Date().addingTimeInterval(20)
        while app.webViews.count > 0, Date() < webviewGone {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(app.webViews.count, 0, "Step-up webview should dismiss after success. \(screenDebugSummary())")
        waitForScreen("UserPageRoot", timeout: 20)
        assertNoConnectionScreenDoesNotAppear(duration: 1)
    }

    /// FR-27246: an opaque login web view painted white over the host instead of the configured backgroundColor.
    func testLoginWebViewShowsConfiguredBackgroundColorBehindTransparentPage() throws {
        let transparentPage: [String: Any] = [
            "status": 200,
            "headers": ["Content-Type": "text/html; charset=utf-8"],
            "body": """
            <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
            <body style="background: transparent; margin: 0;"><p>Transparent Page</p></body></html>
            """
        ]
        // The SDK reloads an authorize URL that renders a page, so every reload must stay transparent.
        try Self.server.enqueue(method: "GET", path: "/oauth/authorize", responses: Array(repeating: transparentPage, count: 3))

        launchApp(resetState: true)
        openEmbeddedLogin()
        getWebLabel("Transparent Page").waitUntilExists(timeout: 20)

        let configuredBackground = (red: 0x1F, green: 0x6F, blue: 0xEB)
        let deadline = Date().addingTimeInterval(5)
        var sampledColor = screenPixelColor(atNormalizedPoint: CGPoint(x: 0.5, y: 0.8))
        while !isColor(sampledColor, closeTo: configuredBackground), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            sampledColor = screenPixelColor(atNormalizedPoint: CGPoint(x: 0.5, y: 0.8))
        }
        XCTAssertTrue(
            isColor(sampledColor, closeTo: configuredBackground),
            "Expected the configured backgroundColor #1F6FEB behind the transparent page, sampled \(String(describing: sampledColor)). \(screenDebugSummary())"
        )
    }

    private func screenPixelColor(atNormalizedPoint point: CGPoint) -> (red: Int, green: Int, blue: Int)? {
        guard let screenshot = XCUIScreen.main.screenshot().image.cgImage else { return nil }
        let pixelRect = CGRect(
            x: Int(CGFloat(screenshot.width) * point.x),
            y: Int(CGFloat(screenshot.height) * point.y),
            width: 1,
            height: 1
        )
        guard let pixel = screenshot.cropping(to: pixelRect) else { return nil }

        var rgba = [UInt8](repeating: 0, count: 4)
        let didDraw = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard didDraw else { return nil }
        return (red: Int(rgba[0]), green: Int(rgba[1]), blue: Int(rgba[2]))
    }

    private func isColor(
        _ color: (red: Int, green: Int, blue: Int)?,
        closeTo expected: (red: Int, green: Int, blue: Int),
        tolerance: Int = 16
    ) -> Bool {
        guard let color else { return false }
        return abs(color.red - expected.red) <= tolerance
            && abs(color.green - expected.green) <= tolerance
            && abs(color.blue - expected.blue) <= tolerance
    }

    func testUnlockAccountDeepLinkKeepsTheLoginViewOpen() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")

        tapButton("E2EUnlockAccountDeepLinkButton")

        XCTAssertTrue(
            Self.server.waitForRequest(
                method: "GET",
                path: "/oauth/account/redirect/ios/\(LocalMockAuthServer.embeddedDemoBundleIdentifier)",
                timeout: 15
            ),
            "Unlock should redirect through the intermediate hop. \(screenDebugSummary())"
        )

        XCTAssertTrue(
            app.getWebLabel("Mock Embedded Login").waitUntilExists(timeout: 20).exists,
            "Unlock should land the user back on a fresh login page rather than a stuck loader. \(screenDebugSummary())"
        )
        XCTAssertFalse(
            app.staticTexts["UserEmailValue"].exists,
            "Unlock must not authenticate anyone. \(screenDebugSummary())"
        )
    }

    func testEmbeddedSamlLogin() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedSAMLButton")
        app.getWebLabel("OKTA SAML Mock Server").waitUntilExists()
        app.getWebButton("Login With Okta").safeTap()
        waitForUserEmail("test@saml-domain.com")
    }

    func testEmbeddedSamlDeadEndRecoversFromRefreshCookie() throws {
        launchApp(resetState: true)
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedSAMLDeadEndButton")

        app.getWebLabel("OKTA SAML Dead-End Mock").waitUntilExists(timeout: 20)
        app.getWebButton("Login With Okta").safeTap()

        XCTAssertTrue(
            Self.server.waitForRequest(method: "GET", path: "/oauth/account/saml/callback", timeout: 20),
            "SAML should land on the assertion callback. \(screenDebugSummary())"
        )

        waitForUserEmail(LocalMockAuthServer.samlDeadEndEmail, timeout: 30)
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

    func testEmbeddedGoogleSocialLoginSupportsBasePathRootCallbackAlias() throws {
        launchApp(
            resetState: true,
            useTestingWebAuthenticationTransport: false,
            basePathPrefix: "/fe-auth",
            useRootGeneratedCallbackAlias: true
        )
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 10)
        waitForUserEmail("google-social@frontegg.com", timeout: 30)
    }

    func testEmbeddedGoogleSocialLoginSupportsBasePathCanonicalCallbackAlias() throws {
        launchApp(
            resetState: true,
            useTestingWebAuthenticationTransport: false,
            basePathPrefix: "/fe-auth"
        )
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 10)
        waitForUserEmail("google-social@frontegg.com", timeout: 30)
    }

    func testEmbeddedGoogleSocialLoginDoesNotShowOAuthErrorToastOnSuccess() throws {
        launchApp(
            resetState: true,
            useTestingWebAuthenticationTransport: false,
            basePathPrefix: "/fe-auth",
            useRootGeneratedCallbackAlias: true
        )
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 10)
        waitForUserEmailWithoutOAuthError("google-social@frontegg.com", timeout: 30)
    }

    func testEmbeddedGoogleSocialLoginCompletesWhenExistingSessionRedirectsToDashboard() throws {
        Self.server.queueEmbeddedSocialSuccessDashboardRedirect()

        launchApp(
            resetState: true,
            useTestingWebAuthenticationTransport: false,
            basePathPrefix: "/fe-auth",
            useRootGeneratedCallbackAlias: true
        )
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 10)

        XCTAssertTrue(
            Self.server.waitForRequest(method: "POST", path: "/frontegg/oauth/authorize/silent", timeout: 20),
            screenDebugSummary()
        )
        waitForUserEmailWithoutOAuthError("google-social@frontegg.com", timeout: 30)
    }

    func testEmbeddedGoogleSocialLoginCompletesWhenExistingSessionRedirectsToHostedRoot() throws {
        Self.server.queueEmbeddedSocialSuccessRootRedirect()

        launchApp(
            resetState: true,
            useTestingWebAuthenticationTransport: false,
            basePathPrefix: "/fe-auth",
            useRootGeneratedCallbackAlias: true
        )
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 10)

        XCTAssertTrue(
            Self.server.waitForRequest(method: "POST", path: "/frontegg/oauth/authorize/silent", timeout: 20),
            screenDebugSummary()
        )
        waitForUserEmailWithoutOAuthError("google-social@frontegg.com", timeout: 30)
    }

    func testEmbeddedGoogleSocialLoginRecoversFromStalledSocialSuccessPage() throws {
        Self.server.queueEmbeddedSocialSuccessStall()

        launchApp(
            resetState: true,
            useTestingWebAuthenticationTransport: false,
            basePathPrefix: "/fe-auth",
            useRootGeneratedCallbackAlias: true
        )
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

        tapButton("LogoutButton")
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
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())
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
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())
    }

    func testAuthenticatedOfflineModeRecoversToOnlineAndRefreshesToken() throws {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        Self.server.clearRequestLog()

        waitUntilAccessTokenExpiresWithin(immediateRefreshTriggerWindow, timeout: 15)
        let initialVersion = accessTokenVersion()
        Self.server.clearRequestLog()
        let initialRefreshCount = refreshRequestCount()

        try queueRefreshConnectionDrops()
        try Self.server.queueProbeFailures(statusCodes: Array(repeating: 503, count: 6))

        tapGetCurrentAccessTokenButton()
        waitForRefreshRecoveryFlowToStart(
            refreshCountAtLeast: initialRefreshCount + 1,
            timeout: 10
        )
        waitForRefreshRequestCount(atLeast: initialRefreshCount + 1, timeout: 10)
        waitForAuthenticatedOfflineMode(true, timeout: 30)
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())

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
        Self.server.clearRequestLog()

        waitUntilAccessTokenExpiresWithin(immediateRefreshTriggerWindow, timeout: 15)
        let initialVersion = accessTokenVersion()
        Self.server.clearRequestLog()
        let initialRefreshCount = refreshRequestCount()

        try Self.server.queueProbeFailures(
            statusCodes: Array(repeating: 503, count: 25)
        )
        try queueRefreshConnectionDrops()

        tapGetCurrentAccessTokenButton()
        waitForRefreshRecoveryFlowToStart(
            refreshCountAtLeast: initialRefreshCount + 1,
            timeout: 10
        )
        waitForRefreshRequestCount(atLeast: initialRefreshCount + 1, timeout: 10)
        waitForAuthenticatedOfflineMode(true, timeout: 30)
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())

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

    func testLogoutWhileAuthenticatedOfflineShowsNoConnectionPage() throws {
        allowsUnexpectedNoConnectionScreen = true

        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        Self.server.clearRequestLog()

        waitUntilAccessTokenExpiresWithin(immediateRefreshTriggerWindow, timeout: 15)
        let initialRefreshCount = refreshRequestCount()

        try Self.server.queueProbeFailures(
            statusCodes: Array(repeating: 503, count: 25)
        )
        try queueRefreshConnectionDrops()

        tapGetCurrentAccessTokenButton()
        waitForRefreshRecoveryFlowToStart(
            refreshCountAtLeast: initialRefreshCount + 1,
            timeout: 10
        )
        waitForRefreshRequestCount(atLeast: initialRefreshCount + 1, timeout: 10)
        waitForAuthenticatedOfflineMode(true, timeout: 30)
        try Self.server.queueProbeFailures(
            statusCodes: Array(repeating: 503, count: 80)
        )

        tapButton("LogoutButton")
        waitForScreen("NoConnectionPageRoot", timeout: 20)

        XCTAssertTrue(retryConnectionControl().exists, screenDebugSummary())
        XCTAssertFalse(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    func testRetryFromUnauthenticatedOfflineScreenReturnsToLoginWhenNetworkRecovers() throws {
        allowsUnexpectedNoConnectionScreen = true

        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        Self.server.clearRequestLog()

        waitUntilAccessTokenExpiresWithin(immediateRefreshTriggerWindow, timeout: 15)
        let initialRefreshCount = refreshRequestCount()

        try Self.server.queueProbeFailures(
            statusCodes: Array(repeating: 503, count: 25)
        )
        try queueRefreshConnectionDrops()

        tapGetCurrentAccessTokenButton()
        waitForRefreshRecoveryFlowToStart(
            refreshCountAtLeast: initialRefreshCount + 1,
            timeout: 10
        )
        waitForRefreshRequestCount(atLeast: initialRefreshCount + 1, timeout: 10)
        waitForAuthenticatedOfflineMode(true, timeout: 30)

        tapButton("LogoutButton")
        waitForScreen("NoConnectionPageRoot", timeout: 20)
        try Self.server.reset()

        let recoveryDeadline = Date().addingTimeInterval(10)
        while Date() < recoveryDeadline {
            if app.descendants(matching: .any)["LoginPageRoot"].exists {
                break
            }

            let retryControl = retryConnectionControl()
            if retryControl.exists {
                retryControl.safeTap()
                break
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        waitForScreen("LoginPageRoot", timeout: 20)
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())
    }

    func testOnlineLogoutReturnsToLoginWithoutOfflineScreen() throws {
        launchApp(resetState: true)
        loginWithPassword()

        tapButton("LogoutButton")
        waitForScreen("LoginPageRoot")
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())
    }

    func testLogoutDuringTransientConnectivityLossRecoversBackToLoginWhenNetworkReturns() throws {
        allowsUnexpectedNoConnectionScreen = true

        launchApp(resetState: true)
        loginWithPassword()

        try Self.server.queueConnectionDrops(path: "/oauth/logout/token")
        try Self.server.queueProbeFailures(statusCodes: Array(repeating: 503, count: 25))

        tapButton("LogoutButton")
        waitForScreen("NoConnectionPageRoot", timeout: 20)

        try Self.server.reset()

        waitForScreen("LoginPageRoot", timeout: 30)
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())
        XCTAssertFalse(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    func testLogoutTerminateTransientNoConnectionThenCustomSSORecovers() throws {
        allowsUnexpectedNoConnectionScreen = true
        launchApp(resetState: true)
        loginWithPassword()

        tapButton("LogoutButton")
        waitForScreen("LoginPageRoot")

        try Self.server.queueProbeFailures(statusCodes: [503, 503])

        app.terminate()
        launchApp(resetState: false)
        let noConnectionScreen = retryConnectionControl()
        if noConnectionScreen.waitForExistence(timeout: 5) || self.noConnectionScreen().exists {
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

    // MARK: - Offline mode disabled scenarios

    /// Verifies that a cold launch with no tokens and offline mode disabled goes straight to the login
    /// screen without running the 4.5-second connectivity probe race that offline mode uses.
    func testColdLaunchWithOfflineModeDisabledReachesLoginQuickly() throws {
        try Self.server.queueProbeFailures(statusCodes: Array(repeating: 503, count: 6))

        launchApp(resetState: true, enableOfflineMode: false)
        waitForScreen("LoginPageRoot", timeout: 5)

        // No offline markers should be visible
        XCTAssertFalse(app.staticTexts["UnauthenticatedOfflineModeEnabled"].exists, screenDebugSummary())
        XCTAssertFalse(app.staticTexts["OfflineModeBadge"].exists, screenDebugSummary())
        assertNoConnectionScreenDoesNotAppear(duration: 2)
    }

    /// Verifies that with offline mode disabled, an authenticated relaunch through transient
    /// connection failures recovers the session without logging the user out and never shows
    /// offline mode indicators.
    func testOfflineModeDisabledPreservesSessionDuringConnectionLossAndRecovers() throws {
        // 1. Login normally with offline mode disabled, verify profile
        launchApp(resetState: true, enableOfflineMode: false)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")
        let initialVersion = accessTokenVersion()
        XCTAssertGreaterThan(initialVersion, 0, screenDebugSummary())

        // 2. Terminate and queue transient refresh failures.
        //    The standard refresh (POST /oauth/token) is shared with WebView token exchange,
        //    so use a small count — enough to exercise the retry path but not so many that
        //    recovery is blocked for the full test timeout.
        terminateApp()
        for path in refreshTokenPaths {
            try Self.server.queueConnectionDrops(path: path, count: 2)
        }

        // 3. Relaunch with offline mode DISABLED
        launchApp(resetState: false, enableOfflineMode: false)

        // 4. The SDK should recover the session and show the profile — the user must NOT be
        //    logged out. The retry (or WebView-assisted re-auth) should restore the session.
        waitForUserEmail("test@frontegg.com", timeout: 30)
        waitForScreen("UserPageRoot")

        // 5. Verify: offline mode markers must NEVER appear (app didn't opt into offline UX)
        XCTAssertFalse(app.staticTexts["AuthenticatedOfflineModeEnabled"].exists, screenDebugSummary())
        XCTAssertFalse(app.staticTexts["OfflineModeBadge"].exists, screenDebugSummary())

        // 6. Verify the session was preserved (token was refreshed, not re-created from scratch)
        let recoveredVersion = accessTokenVersion()
        XCTAssertGreaterThanOrEqual(recoveredVersion, initialVersion, "Token version should not decrease — session must be preserved, not recreated. \(screenDebugSummary())")
    }

    /// Verifies that password login completes normally when offline mode is disabled,
    /// confirming the setting does not interfere with normal auth flows.
    func testPasswordLoginWorksWithOfflineModeDisabled() throws {
        launchApp(resetState: true, enableOfflineMode: false)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")
    }

    // MARK: - Logout and session lifecycle

    /// Verifies that logout clears all tokens from keychain so a subsequent relaunch
    /// does not restore the session — the user sees the login page, not the profile.
    func testLogoutClearsSessionAndRelaunchShowsLogin() throws {
        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")

        // Logout
        tapButton("LogoutButton")
        waitForScreen("LoginPageRoot")

        // Relaunch without resetting state — keychain should be cleared by logout
        terminateApp()
        launchApp(resetState: false)
        waitForScreen("LoginPageRoot", timeout: 10)

        // Must NOT restore to user page
        XCTAssertFalse(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    // MARK: - Token refresh edge cases

    /// Verifies that when the refresh token itself has expired, the app clears the
    /// session and shows the login page instead of spinning in a loading state.
    func testExpiredRefreshTokenClearsSessionAndShowsLogin() throws {
        let shortRefreshTTL = 5
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: 3,
            refreshTokenTTL: shortRefreshTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")

        // Wait for BOTH tokens to expire
        terminateApp()
        waitForDuration(TimeInterval(shortRefreshTTL + 3))

        // Relaunch — refresh should fail with 401, session should be cleared
        launchApp(resetState: false)
        waitForScreen("LoginPageRoot", timeout: 20)
        XCTAssertFalse(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    /// Verifies that the scheduled token refresh fires automatically before the access
    /// token expires and increments the token version while the app stays in the foreground.
    func testScheduledTokenRefreshFiresBeforeExpiry() throws {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: expiringAccessTokenTTL,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")
        let initialVersion = accessTokenVersion()

        // Wait for the scheduled refresh to fire and produce a new token version.
        // The SDK schedules refresh at ~80% of TTL (≈16.8s for 21s TTL).
        // Use a generous timeout for CI where the simulator may be slower.
        let refreshedVersion = waitForAccessTokenVersionChange(from: initialVersion, timeout: 35)
        XCTAssertGreaterThan(refreshedVersion, initialVersion, screenDebugSummary())
        XCTAssertTrue(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())
    }

    // MARK: - FR-24808 Deep-link recovery regression (multi-app AASA wrong-app routing)

    /// Regression for the SkyPath "stuck on loading after login" incident
    /// (see plan.md in mobile-logs investigation). When a device has more
    /// than one app from the same TeamID claiming the same Universal Link
    /// associated domain, iOS may dispatch an ASWebAuthSession OAuth
    /// callback to the *wrong* app. The receiving app sees a URL whose
    /// scheme/host/path don't match the strict generated redirect URI but
    /// it still carries a usable `code` + `state`.
    ///
    /// Before the fix in `FronteggAuth+EmbeddedAndDeepLink.swift`, the SDK
    /// would early-return false on this URL (`handleOpenUrl` warning
    /// "URL doesn't match baseUrl"), the OAuth code would be silently
    /// dropped, and affected users were stuck on the loader.
    ///
    /// After the fix, the SDK recognises the URL as OAuth-shaped (its
    /// scheme matches one of the app's declared `CFBundleURLSchemes` and
    /// it carries `code`/`error`) and runs the hosted-login token
    /// exchange, recovering the login instead of dropping the code.
    func testMisroutedOpenURLRecoversIntoAuthenticatedState() throws {
        let misroutedCode = "code-e2e-misrouted-\(UUID().uuidString.lowercased())"
        let misroutedState = "state-e2e-misrouted-\(UUID().uuidString.lowercased())"
        let misroutedVerifier = "verifier-e2e-misrouted-\(UUID().uuidString.lowercased())"

        Self.server.seedAuthCode(
            code: misroutedCode,
            email: "test@frontegg.com",
            redirectURI: "",
            state: misroutedState
        )

        launchApp(
            resetState: true,
            misroutedCallbackCode: misroutedCode,
            misroutedCallbackState: misroutedState,
            misroutedCallbackVerifier: misroutedVerifier
        )
        waitForScreen("LoginPageRoot")
        XCTAssertFalse(app.staticTexts["UserEmailValue"].exists, screenDebugSummary())

        tapButton("E2ESimulateMisroutedDeepLinkButton")

        // Recovery path must exchange the seeded code with the mock /oauth/token
        // and land the user on UserPageRoot — *not* leave them stuck on
        // LoginPageRoot / DefaultLoader (the symptom in SP-7114 / SP-6985).
        XCTAssertTrue(
            Self.server.waitForRequest(method: "POST", path: "/oauth/token", timeout: 15),
            "Recovery should drive a token exchange. \(screenDebugSummary())"
        )
        waitForUserEmail("test@frontegg.com", timeout: 20)
        XCTAssertFalse(noConnectionScreen().exists, screenDebugSummary())
    }

    /// Verifies that relaunching with an expired access token but a valid refresh token
    /// restores the session via token refresh (not via cached access token validation).
    func testAuthenticatedRelaunchWithExpiredAccessTokenAndFreshRefreshToken() throws {
        Self.server.configureTokenPolicy(
            email: "test@frontegg.com",
            accessTokenTTL: 3,
            refreshTokenTTL: longLivedRefreshTokenTTL
        )

        launchApp(resetState: true)
        loginWithPassword()
        waitForUserEmail("test@frontegg.com")
        let initialVersion = accessTokenVersion()

        // Terminate and wait just long enough for the access token to expire
        // but NOT the refresh token
        terminateApp()
        waitForDuration(5)

        // Relaunch — access token expired, refresh token valid
        launchApp(resetState: false)
        waitForUserEmail("test@frontegg.com", timeout: 20)

        // Token version should have increased (refreshed, not reused)
        let refreshedVersion = accessTokenVersion()
        XCTAssertGreaterThan(refreshedVersion, initialVersion, screenDebugSummary())
    }
}
