import XCTest

final class DemoEmbeddedE2ETests: DemoEmbeddedUITestCase {
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

        terminateApp()
        launchApp(resetState: false, forceNetworkPathOffline: true)
        waitForUserEmail("test@frontegg.com", timeout: 20)
        XCTAssertTrue(app.staticTexts["AuthenticatedOfflineModeEnabled"].waitForExistence(timeout: 5), screenDebugSummary())
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
