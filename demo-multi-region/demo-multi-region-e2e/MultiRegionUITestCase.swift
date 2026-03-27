//
//  MultiRegionUITestCase.swift
//  demo-multi-region-e2e
//

import XCTest

class MultiRegionUITestCase: XCTestCase {

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

    func launchAppWithoutReset() {
        launchApp(resetState: false)
    }

    func terminateAndRelaunch(resetState: Bool = false) {
        app.terminate()
        launchApp(resetState: resetState)
    }

    // MARK: - Screen Waiters

    func waitForScreen(_ identifier: String, timeout: TimeInterval = 15) {
        // SwiftUI may propagate accessibility identifiers to different element types
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let query = app.descendants(matching: .any).matching(predicate)
        let exists = query.firstMatch.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Screen '\(identifier)' did not appear within \(timeout)s")
    }

    func waitForLoginPage(timeout: TimeInterval = 15) {
        waitForScreen("LoginPageRoot", timeout: timeout)
    }

    func waitForUserPage(timeout: TimeInterval = 15) {
        waitForScreen("UserPageRoot", timeout: timeout)
    }

    func waitForSelectRegionPage(timeout: TimeInterval = 15) {
        waitForScreen("SelectRegionRoot", timeout: timeout)
    }

    func waitForUserEmail(_ expected: String, timeout: TimeInterval = 15) {
        let label = app.staticTexts["UserEmailValue"]
        let exists = label.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "UserEmailValue did not appear")
        XCTAssertEqual(label.label, expected)
    }

    // MARK: - Interaction Helpers

    func tapButton(_ identifier: String, timeout: TimeInterval = 10) {
        // First try standard buttons query
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            return
        }
        // Fall back to descendants search (SwiftUI may propagate identifiers differently)
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 3), "Button '\(identifier)' not found")
        match.tap()
    }

    func loginWithPassword(email: String = "test@frontegg.com") {
        waitForLoginPage()

        // Use the E2E button which passes loginHint — the mock server auto-fills and
        // auto-submits the password form, bypassing unreliable WKWebView text field interaction
        let e2eButton = app.buttons["E2EPasswordButton"]
        guard e2eButton.waitForExistence(timeout: 10) else {
            XCTFail("E2EPasswordButton not found. Is MultiRegionTestMode enabled?")
            return
        }
        e2eButton.tap()
        waitForUserPage()
    }

    func waitForWebElement(
        elementType: XCUIElement.ElementType,
        text: String,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@ OR placeholderValue == %@", text, text, text)
        let query = app.webViews.descendants(matching: elementType).matching(predicate)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let matches = query.allElementsBoundByIndex.filter(\.exists)
            if let match = matches.last(where: \.isHittable) ?? matches.last {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        XCTFail("Web element '\(text)' (\(elementType)) not found within \(timeout)s")
        return query.firstMatch
    }

    // MARK: - Debug

    func printScreenContents() {
        for text in app.staticTexts.allElementsBoundByIndex.prefix(15) {
            print("E2E TEXT: '\(text.label)' id='\(text.identifier)'")
        }
        for btn in app.buttons.allElementsBoundByIndex.prefix(10) {
            print("E2E BUTTON: '\(btn.label)' id='\(btn.identifier)'")
        }
    }

    func screenDebugSummary() -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
        let buttons = app.buttons.allElementsBoundByIndex.prefix(10).map { $0.label }
        return "Texts: \(texts)\nButtons: \(buttons)"
    }
}

// MARK: - XCUIElement Helpers

extension XCUIElement {
    @discardableResult
    func waitUntilExists(timeout: TimeInterval = 10) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "Element did not appear within \(timeout)s")
        return self
    }

    func safeTap() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func safeTypeText(_ text: String) {
        for char in text {
            typeText(String(char))
        }
    }
}
