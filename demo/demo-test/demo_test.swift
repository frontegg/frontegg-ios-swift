//
//  demo_test.swift
//  demo-test
//
//  Created by David Frontegg on 22/01/2023.
//

import XCTest

final class demo_test: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Check that the app is displaying an activity indicator
        let activityIndicator = app.otherElements["LoaderView"]

        // Wait for the loading indicator to disappear = content is ready
            expectation(for: NSPredicate(format: "exists == 0"),
                        evaluatedWith: activityIndicator)
        waitForExpectations(timeout: 10)

        
        let userNameField = app.webViews.textFields["name@example.com"]
        if userNameField.waitForExistence(timeout: 5) {
            userNameField.tap()
            userNameField.typeText("david+123123@frontegg.com")
        }
        
        let continueButton = app.webViews.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 5) {
            continueButton.tap()
        }
        
        
    }

}
