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
        app.terminate()
        launchApp(resetState: resetState)
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

    // MARK: - Interaction Helpers

    func tapButton(_ identifier: String, timeout: TimeInterval = 10) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Button '\(identifier)' not found")
        button.tap()
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
