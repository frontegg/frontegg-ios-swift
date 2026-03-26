import XCTest

class DemoEmbeddedUITestCase: XCTestCase {
    static var server: LocalMockAuthServer!
    private let knownScreenIdentifiers = ["LoginPageRoot", "NoConnectionPageRoot", "UserPageRoot", "AuthenticatedOfflineRoot"]

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

    @discardableResult
    func launchApp(
        resetState: Bool = true,
        useTestingWebAuthenticationTransport: Bool = true,
        forceNetworkPathOffline: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = Self.server.launchEnvironment(
            resetState: resetState,
            useTestingWebAuthenticationTransport: useTestingWebAuthenticationTransport,
            forceNetworkPathOffline: forceNetworkPathOffline
        )
        app.launch()
        self.app = app
        return app
    }

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
        waitForScreen("UserPageRoot", timeout: timeout)
        XCTAssertTrue(app.staticTexts[email].waitForExistence(timeout: timeout), "Expected user email \(email)")
        assertNoUnexpectedNoConnectionScreenSeen()
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

    func openEmbeddedLogin() {
        waitForScreen("LoginPageRoot")
        app.buttons["NativeLoginButton"].tap()
    }

    func tapButton(_ identifier: String, timeout: TimeInterval = 20, maxScrollAttempts: Int = 6) {
        let element = app.buttons[identifier].waitUntilExists(timeout: timeout)
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

    func loginWithPassword(email: String = "test@frontegg.com", password: String = "Testpassword1!") {
        if email == "test@frontegg.com",
           app.buttons["E2EEmbeddedPasswordButton"].exists {
            waitForScreen("LoginPageRoot")
            app.buttons["E2EEmbeddedPasswordButton"].tap()
            waitForUserEmail(email)
            return
        }

        openEmbeddedLogin()
        app.getWebInput("Email is required").safeTypeText(email)
        app.getWebButton("Continue").safeTap()
        app.getWebPasswordInput("Password is required").safeTypeText(password)
        app.getWebButton("Sign in").safeTap()
        waitForUserEmail(email)
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
            "Sign in",
            "No internet connection",
            "Authenticated (offline)",
            "Welcome!",
        ].filter { app.staticTexts[$0].exists }

        return "Visible screens: \(visibleScreens.joined(separator: ", ")); prominent texts: \(prominentTexts.joined(separator: ", ")); webViews: \(app.webViews.count); buttons: \(app.buttons.count)"
    }

    func terminateApp() {
        assertNoUnexpectedNoConnectionScreenSeen()
        app?.terminate()
    }

    private func assertNoUnexpectedNoConnectionScreenSeen() {
        guard !allowsUnexpectedNoConnectionScreen else { return }
        guard app != nil else { return }
        if unexpectedNoConnectionScreenWasSeen() {
            XCTFail("Unexpected NoConnectionPageRoot appeared during the test. \(screenDebugSummary())")
        }
    }

    private func unexpectedNoConnectionScreenWasSeen() -> Bool {
        let currentScreenVisible = app.buttons["RetryConnectionButton"].exists
        let stickyMarkerVisible = app.staticTexts["NoConnectionPageSeenEver"].exists
        return currentScreenVisible || stickyMarkerVisible
    }

    private func screenAnchor(for identifier: String) -> XCUIElement {
        switch identifier {
        case "LoginPageRoot":
            return app.buttons["NativeLoginButton"]
        case "NoConnectionPageRoot":
            return app.buttons["RetryConnectionButton"]
        case "UserPageRoot":
            return app.staticTexts["UserEmailValue"]
        case "AuthenticatedOfflineRoot":
            return app.staticTexts["Authenticated (offline)"]
        case "BootstrapLoaderView":
            return app.otherElements["BootstrapLoaderView"]
        case "DefaultLoaderRoot":
            return app.otherElements["DefaultLoaderRoot"]
        case "LoaderView":
            return app.otherElements["LoaderView"]
        default:
            return app.otherElements[identifier]
        }
    }
}

extension XCUIApplication {
    func getWebButton(_ text: String) -> XCUIElement {
        preferredWebElement(
            elementType: .button,
            text: text
        )
    }

    func getWebInput(_ text: String) -> XCUIElement {
        preferredWebElement(
            elementType: .textField,
            text: text
        )
    }

    func getWebPasswordInput(_ text: String) -> XCUIElement {
        preferredWebElement(
            elementType: .secureTextField,
            text: text
        )
    }

    func getWebLabel(_ text: String) -> XCUIElement {
        preferredWebElement(
            elementType: .staticText,
            text: text
        )
    }

    private func preferredWebElement(
        elementType: XCUIElement.ElementType,
        text: String,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", text, text)
        let query = webViews.descendants(matching: elementType).matching(predicate)
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

        XCTFail("Expected web element \(text) of type \(elementType) within \(timeout)s")
        return query.firstMatch
    }
}

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
