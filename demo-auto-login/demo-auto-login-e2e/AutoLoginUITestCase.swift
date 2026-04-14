//
//  AutoLoginUITestCase.swift
//  demo-auto-login-e2e
//
//  Base test case for demo-auto-login E2E tests.
//  Adapted from DemoEmbeddedUITestCase with auto-login screen identifiers.
//

import XCTest

class AutoLoginUITestCase: XCTestCase {
    static var server: LocalMockAuthServer!
    private let knownScreenIdentifiers = [
        "AutoLoginWebViewRoot",
        "NoConnectionPageRoot",
        "ProfileViewRoot",
        "AuthenticatedOfflineRoot",
        "BootstrapLoaderView",
        "LoaderView",
    ]

    var app: XCUIApplication!
    var allowsUnexpectedNoConnectionScreen = false

    override class func setUp() {
        super.setUp()
        if server == nil {
            server = try! LocalMockAuthServer()
        }
    }

    override class func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        allowsUnexpectedNoConnectionScreen = false
        try Self.server.reset()
    }

    override func tearDownWithError() throws {
        assertNoUnexpectedNoConnectionScreenSeen()
        app?.terminate()
    }

    // MARK: - Launch Helpers

    @discardableResult
    func launchApp(
        resetState: Bool = true,
        useTestingWebAuthenticationTransport: Bool = true,
        forceNetworkPathOffline: Bool = false,
        enableOfflineMode: Bool? = nil,
        basePathPrefix: String = "",
        useRootGeneratedCallbackAlias: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = Self.server.launchEnvironment(
            resetState: resetState,
            useTestingWebAuthenticationTransport: useTestingWebAuthenticationTransport,
            forceNetworkPathOffline: forceNetworkPathOffline,
            enableOfflineMode: enableOfflineMode,
            basePathPrefix: basePathPrefix,
            useRootGeneratedCallbackAlias: useRootGeneratedCallbackAlias
        )
        app.launch()
        self.app = app
        return app
    }

    // MARK: - Screen Wait Helpers

    @discardableResult
    func waitForScreen(_ identifier: String, timeout: TimeInterval = 20) -> XCUIElement {
        let element = screenAnchor(for: identifier)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !allowsUnexpectedNoConnectionScreen,
               identifier != "NoConnectionPageRoot",
               unexpectedNoConnectionScreenWasSeen() {
                XCTFail("Unexpected NoConnectionPageRoot appeared while waiting for \(identifier). \(screenDebugSummary())")
                return element
            }

            if element.exists {
                return element
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected screen \(identifier). \(screenDebugSummary())")
        return element
    }

    func waitForUserEmail(_ email: String, timeout: TimeInterval = 20) {
        waitForScreen("ProfileViewRoot", timeout: timeout)
        XCTAssertTrue(app.staticTexts[email].waitForExistence(timeout: timeout), "Expected user email \(email)")
        assertNoUnexpectedNoConnectionScreenSeen()
    }

    func waitForUserEmailWithoutOAuthError(
        _ email: String,
        timeout: TimeInterval = 20,
        postAppearanceGuard: TimeInterval = 2
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let profileRoot = app.descendants(matching: .any)["ProfileViewRoot"]
        let emailLabel = app.staticTexts[email]

        while Date() < deadline {
            if oauthErrorToastIsVisible() {
                XCTFail("Unexpected OAuth error toast appeared while waiting for user email \(email). \(screenDebugSummary())")
                return
            }

            if profileRoot.exists && emailLabel.exists {
                assertNoOAuthErrorToastAppears(duration: postAppearanceGuard)
                assertNoUnexpectedNoConnectionScreenSeen()
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected user email \(email) without OAuth error. \(screenDebugSummary())")
    }

    func assertNoConnectionScreenDoesNotAppear(duration: TimeInterval, pollInterval: TimeInterval = 0.1) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            if unexpectedNoConnectionScreenWasSeen() {
                XCTFail("Unexpected NoConnectionPageRoot appeared. \(screenDebugSummary())")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
    }

    func waitForAuthenticatedOfflineMode(_ enabled: Bool, timeout: TimeInterval = 20) {
        let offlineMarker = app.staticTexts["AuthenticatedOfflineModeEnabled"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !allowsUnexpectedNoConnectionScreen,
               unexpectedNoConnectionScreenWasSeen() {
                XCTFail("Unexpected NoConnectionPageRoot appeared while waiting for authenticated offline mode \(enabled). \(screenDebugSummary())")
                return
            }

            let conditionSatisfied = enabled ? offlineMarker.exists : !offlineMarker.exists
            if conditionSatisfied {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected authenticated offline mode \(enabled). \(screenDebugSummary())")
    }

    // MARK: - Token Diagnostics

    func accessTokenVersion(timeout: TimeInterval = 10) -> Int {
        let value = textValue(for: "AccessTokenVersionValue", timeout: timeout)
        let cleaned = value.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let version = Int(cleaned) else {
            XCTFail("Expected integer token version, got \(value). \(screenDebugSummary())")
            return -1
        }
        return version
    }

    func accessTokenExpiration(timeout: TimeInterval = 10) -> Int {
        let value = textValue(for: "AccessTokenExpValue", timeout: timeout)
        let cleaned = value.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let expiration = Int(cleaned) else {
            XCTFail("Expected integer token expiration, got \(value). \(screenDebugSummary())")
            return -1
        }
        return expiration
    }

    @discardableResult
    func waitForAccessTokenVersionChange(from initialVersion: Int, timeout: TimeInterval = 20) -> Int {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let currentVersion = accessTokenVersion(timeout: 2)
            if currentVersion != initialVersion {
                return currentVersion
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected access token version to change from \(initialVersion). \(screenDebugSummary())")
        return initialVersion
    }

    func waitUntilAccessTokenExpiresWithin(_ seconds: Int, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let expiration = accessTokenExpiration(timeout: 2)
            let now = Int(Date().timeIntervalSince1970)
            if expiration - now <= seconds {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected access token to expire within \(seconds)s. \(screenDebugSummary())")
    }

    // MARK: - OAuth Error Helpers

    @discardableResult
    func waitForOAuthErrorToast(timeout: TimeInterval = 20) -> XCUIElement {
        let anyToast = app.descendants(matching: .any).matching(identifier: "OAuthErrorToast").firstMatch
        let staticToast = app.staticTexts["OAuthErrorToast"]
        let otherToast = app.otherElements["OAuthErrorToast"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            for candidate in [anyToast, staticToast, otherToast] where candidate.exists {
                return candidate
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected OAuth error toast within \(timeout)s. \(screenDebugSummary())")
        return anyToast
    }

    func assertNoOAuthErrorToastAppears(duration: TimeInterval, pollInterval: TimeInterval = 0.1) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            if oauthErrorToastIsVisible() {
                XCTFail("Unexpected OAuth error toast appeared. \(screenDebugSummary())")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
    }

    // MARK: - Login Flow Helpers

    /// In auto-login mode, the WebView is shown directly — no "Sign in" button.
    /// This helper waits for the WebView to load and enters password credentials
    /// into the mock server's hosted login form.
    func loginWithPassword(email: String = "test@frontegg.com", password: String = "Testpassword1!") {
        // Auto-login: WebView appears directly, no landing page
        waitForScreen("AutoLoginWebViewRoot")

        // Wait for the mock server's hosted login form to render.
        // The form uses placeholder attributes which XCUI may expose as label, value, or placeholderValue.
        let emailField = waitForAnyWebTextField(timeout: 20)
        emailField.safeTap()
        emailField.safeTypeText(email)

        // Tap Continue to advance to the password step
        waitForWebElement(elementType: .button, text: "Continue").safeTap()

        // Enter password — the mock renders a secure text field or a regular text field
        let passwordField = waitForAnyWebSecureTextField(timeout: 20)
        passwordField.safeTap()
        passwordField.safeTypeText(password)

        // Submit (button may say "Sign in" or "Continue")
        let signIn = app.webViews.buttons["Sign in"]
        let continueBtn = app.webViews.buttons["Continue"]
        if signIn.waitForExistence(timeout: 5) {
            signIn.safeTap()
        } else if continueBtn.exists {
            continueBtn.safeTap()
        } else {
            // Fallback: tap the last button in the webview
            let lastButton = app.webViews.buttons.allElementsBoundByIndex.last
            lastButton?.safeTap()
        }

        waitForUserEmail(email)
    }

    /// Find any text field in web views (for email input).
    private func waitForAnyWebTextField(timeout: TimeInterval = 20) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fields = app.webViews.textFields.allElementsBoundByIndex.filter(\.exists)
            if let field = fields.first(where: \.isHittable) ?? fields.first {
                return field
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("No text field found in webViews within \(timeout)s. \(screenDebugSummary())")
        return app.webViews.textFields.firstMatch
    }

    /// Find any secure text field in web views (for password input).
    private func waitForAnyWebSecureTextField(timeout: TimeInterval = 20) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // Try secure text fields first, then regular text fields (mock may use type=text)
            let secureFields = app.webViews.secureTextFields.allElementsBoundByIndex.filter(\.exists)
            if let field = secureFields.first(where: \.isHittable) ?? secureFields.first {
                return field
            }
            // Some mock forms use regular text fields for password
            let textFields = app.webViews.textFields.allElementsBoundByIndex.filter(\.exists)
            if textFields.count > 1, let field = textFields.last {
                return field
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("No password field found in webViews within \(timeout)s. \(screenDebugSummary())")
        return app.webViews.secureTextFields.firstMatch
    }

    func loginWithSocialGoogle() {
        waitForScreen("AutoLoginWebViewRoot")

        // Trigger Google social login via the mock server's ASWebAuthentication transport
        // The WebView should show the login form with social buttons
        // For E2E, the mock server handles the Google OAuth flow
    }

    // MARK: - Button Helpers

    func tapButton(_ identifier: String, timeout: TimeInterval = 20, maxScrollAttempts: Int = 6) {
        let element = app.buttons[identifier]
        if !element.waitForExistence(timeout: timeout) {
            let predicate = NSPredicate(format: "identifier == %@", identifier)
            let fallback = app.descendants(matching: .any).matching(predicate).firstMatch
            XCTAssertTrue(
                fallback.waitForExistence(timeout: 3),
                "Button \(identifier) did not appear. \(screenDebugSummary())"
            )
            fallback.safeTap()
            return
        }
        if element.isHittable {
            element.safeTap()
            return
        }

        for _ in 0..<maxScrollAttempts {
            if element.isHittable {
                element.safeTap()
                return
            }
            app.swipeUp()
        }

        if element.isHittable {
            element.safeTap()
            return
        }

        XCTFail("Button \(identifier) was not hittable after scrolling. \(screenDebugSummary())")
    }

    func acceptSystemDialogIfNeeded(timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let buttonTitles = ["Continue", "Open", "Allow", "OK"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for title in buttonTitles {
                let button = springboard.buttons[title]
                if button.exists {
                    button.tap()
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    func waitForDuration(_ duration: TimeInterval, pollInterval: TimeInterval = 0.1) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
    }

    func terminateApp() {
        assertNoUnexpectedNoConnectionScreenSeen()
        app?.terminate()
    }

    // MARK: - Connection Helpers

    func noConnectionScreen() -> XCUIElement {
        screenAnchor(for: "NoConnectionPageRoot")
    }

    func retryConnectionControl() -> XCUIElement {
        let candidates: [XCUIElement] = [
            app.buttons["RetryConnectionButton"],
            app.buttons["Retry"],
            app.otherElements["RetryConnectionButton"],
            app.otherElements["Retry"],
        ]

        for candidate in candidates where candidate.exists {
            return candidate
        }

        return candidates[0]
    }

    // MARK: - Debug

    func screenDebugSummary() -> String {
        let visibleScreens = knownScreenIdentifiers.compactMap { identifier -> String? in
            let element = screenAnchor(for: identifier)
            guard element.exists else { return nil }

            if let value = element.value as? String, !value.isEmpty {
                return "\(identifier)[\(value)]"
            }
            return identifier
        }

        let prominentTexts = [
            "No Connection",
            "Authenticated (offline)",
        ].filter { app.staticTexts[$0].exists }

        let diagnostics = [
            "rootAuth": diagnosticValue(for: "RootIsAuthenticatedValue"),
            "rootOffline": diagnosticValue(for: "RootIsOfflineModeValue"),
            "rootLoading": diagnosticValue(for: "RootIsLoadingValue"),
            "rootInitializing": diagnosticValue(for: "RootInitializingValue"),
            "rootShowLoader": diagnosticValue(for: "RootShowLoaderValue"),
            "rootHasUser": diagnosticValue(for: "RootHasUserValue"),
        ]
            .compactMap { key, value in value.map { "\(key)=\($0)" } }
            .joined(separator: ", ")

        return "Visible screens: \(visibleScreens.joined(separator: ", ")); texts: \(prominentTexts.joined(separator: ", ")); diagnostics: \(diagnostics); webViews: \(app.webViews.count)"
    }

    // MARK: - Private

    private func assertNoUnexpectedNoConnectionScreenSeen() {
        guard !allowsUnexpectedNoConnectionScreen else { return }
        guard app != nil else { return }
        if unexpectedNoConnectionScreenWasSeen() {
            XCTFail("Unexpected NoConnectionPageRoot appeared during the test. \(screenDebugSummary())")
        }
    }

    private func unexpectedNoConnectionScreenWasSeen() -> Bool {
        let currentScreenVisible = noConnectionScreen().exists
        let stickyMarkerVisible = app.staticTexts["NoConnectionPageSeenEver"].exists
        return currentScreenVisible || stickyMarkerVisible
    }

    private func oauthErrorToastIsVisible() -> Bool {
        let candidates: [XCUIElement] = [
            app.descendants(matching: .any).matching(identifier: "OAuthErrorToast").firstMatch,
            app.staticTexts["OAuthErrorToast"],
            app.otherElements["OAuthErrorToast"],
        ]

        return candidates.contains { $0.exists }
    }

    private func textValue(for identifier: String, timeout: TimeInterval) -> String {
        app.staticTexts[identifier].waitUntilExists(timeout: timeout).label
    }

    private func diagnosticValue(for identifier: String) -> String? {
        let element = app.staticTexts[identifier]
        return element.exists ? element.label : nil
    }

    private func waitForWebElement(
        elementType: XCUIElement.ElementType,
        text: String,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", text, text)
        let query = app.webViews.descendants(matching: elementType).matching(predicate)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let matches = query.allElementsBoundByIndex.filter(\.exists)
            if let hittableMatch = matches.last(where: \.isHittable) {
                return hittableMatch
            }
            if let visibleMatch = matches.last {
                return visibleMatch
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Expected web element \(text) of type \(elementType) within \(timeout)s. \(screenDebugSummary())")
        return query.firstMatch
    }

    private func screenAnchor(for identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    @discardableResult
    func waitUntilExists(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), file: file, line: line)
        return self
    }

    func safeTap() {
        if isHittable {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        let normalized = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        normalized.tap()
    }

    func safeTypeText(_ text: String) {
        tap()
        typeText(text)
    }
}
