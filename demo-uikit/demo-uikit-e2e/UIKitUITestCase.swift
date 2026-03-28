//
//  UIKitUITestCase.swift
//  demo-uikit-e2e
//

import XCTest

class UIKitUITestCase: XCTestCase {

    static var mockServer: LocalMockAuthServer!

    var app: XCUIApplication!

    override class func setUp() {
        super.setUp()
        mockServer = try! LocalMockAuthServer()
    }

    override class func tearDown() {
        mockServer?.stop()
        mockServer = nil
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        try! Self.mockServer.reset()
        app = XCUIApplication()
    }

    override func tearDown() {
        terminateAppIfNeeded(assertOnTimeout: false)
        app = nil
        super.tearDown()
    }

    // MARK: - Launch Helpers

    func launchApp(resetState: Bool = true) {
        var env = Self.mockServer.launchEnvironment(resetState: resetState)
        env["frontegg-testing"] = "true"
        app.launchEnvironment = env
        app.launch()
    }

    func terminateAndRelaunch(resetState: Bool = false) {
        terminateAppIfNeeded(assertOnTimeout: true)
        launchApp(resetState: resetState)
    }

    func terminateAppIfNeeded(
        timeout: TimeInterval = 5,
        assertOnTimeout: Bool = true
    ) {
        guard let app else { return }
        guard app.state != .notRunning else { return }

        app.terminate()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.state == .notRunning {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        if assertOnTimeout {
            XCTFail("App did not terminate within \(timeout)s. Debug: \(screenDebugSummary())")
        }
    }

    // MARK: - Screen Waiters

    func waitForScreen(_ identifier: String, timeout: TimeInterval = 15) {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let query = app.descendants(matching: .any).matching(predicate)
        let exists = query.firstMatch.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Screen '\(identifier)' did not appear within \(timeout)s. Debug: \(screenDebugSummary())")
    }

    func waitForLoginPage(timeout: TimeInterval = 15) {
        waitForScreen("LoginPageRoot", timeout: timeout)
    }

    func waitForStreamPage(timeout: TimeInterval = 15) {
        waitForScreen("StreamPageRoot", timeout: timeout)
    }

    func waitForAccessTokenLabel(timeout: TimeInterval = 15) {
        let label = app.staticTexts["AccessTokenLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: timeout), "AccessTokenLabel did not appear")
    }

    func waitForElementToDisappear(
        _ element: XCUIElement,
        description: String,
        timeout: TimeInterval = 15
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("\(description) did not disappear within \(timeout)s. Debug: \(screenDebugSummary())")
    }

    // MARK: - Interaction Helpers

    func tapButton(_ identifier: String, timeout: TimeInterval = 10) {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: timeout) {
            button.safeTap()
            return
        }

        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 3), "Button '\(identifier)' not found")
        match.safeTap()
    }

    func configureDefaultToken(email: String = "test@frontegg.com", accessTTL: Int = 3600) {
        Self.mockServer.configureTokenPolicy(
            email: email,
            accessTokenTTL: accessTTL,
            refreshTokenTTL: 86400
        )
    }

    // MARK: - Debug

    func screenDebugSummary() -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
        let buttons = app.buttons.allElementsBoundByIndex.prefix(10).map { $0.label }
        return "Texts: \(texts)\nButtons: \(buttons)"
    }
}

extension XCUIElement {
    @discardableResult
    func waitUntilExists(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), file: file, line: line)
        return self
    }

    func safeTap() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
