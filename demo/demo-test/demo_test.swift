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
    
    func testExample() async throws {
        // UI tests must launch the application that they test.
        
        let config = try Mocker.fronteggConfig(bundle:Bundle(for: type(of: self)))
//        await Mocker.mockSuccessLogin()
//        return
        
        
        let app = XCUIApplication()
        
        app.launchEnvironment = ["frontegg-testing":"true"]
        
        DispatchQueue.main.sync { app.launch() }
        
        
//        let config = try Mocker.fronteggConfig(bundle:Bundle(for: type(of: self)))
        
        
        // Check that the app is displaying an activity indicator
        let activityIndicator = app.otherElements["LoaderView"]
        
        
        
        // Wait for the loading indicator to disappear = content is ready
        expectation(for: NSPredicate(format: "exists == 0"), evaluatedWith: activityIndicator)
        
        await waitForExpectations(timeout: 10)
        
        let userNameField = app.webViews.textFields["name@example.com"]
        if userNameField.waitForExistence(timeout: 5) {
            DispatchQueue.main.sync {
                userNameField.tap()
                userNameField.typeText("test@frontegg.com")
            }
        }
        
        await Mocker.mock(name: .mockSSOPrelogin, body: [ "options": ["success": false]])
        
        let continueButton = app.webViews.buttons["Continue"]
        XCTAssert(continueButton.waitForExistence(timeout: 5))
        
        DispatchQueue.main.sync {
            continueButton.tap()
        }
        
        let passwordField = app.webViews.secureTextFields["Set a password"]
        if passwordField.waitForExistence(timeout: 5) {
            DispatchQueue.main.sync {
                passwordField.tap()
                passwordField.typeText("TestTest")
            }
        }
        
        
        await Mocker.mockSuccessLogin()
        
        let signInButton = app.webViews.buttons["Sign in"]
        XCTAssert(signInButton.waitForExistence(timeout: 5))
        DispatchQueue.main.sync {
            signInButton.tap()
        }
        
        
        let successField = app.webViews.staticTexts["Sccee"]
        XCTAssert(successField.waitForExistence(timeout: 100))
        
        
        
        
        //            let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        //            safari.launch()
        //            XCTAssert(safari.wait(for: .runningForeground, timeout: 5))
        
        // Type the deeplink and execute it
        
        //            let firstLaunchContinueButton = safari.buttons["Continue"]
        
        //            if firstLaunchContinueButton.exists {
        //
        //                firstLaunchContinueButton.tap()
        //
        //            }
        
        
        //            safari.textFields["Address"].tap()
        //
        //            let keyboardTutorialButton = safari.buttons["Continue"]
        //
        //            if keyboardTutorialButton.exists {
        //
        //                keyboardTutorialButton.tap()
        //
        //            }
        //
        //            safari.typeText("https://gmail.com")
        //
        //            safari.buttons["go"].tap()
        
        
        //            XCTAssert(magicLink.waitForExistence(timeout: 5))
    }
    
}
