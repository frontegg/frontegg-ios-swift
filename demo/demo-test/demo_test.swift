//
//  demo_test.swift
//  demo-test
//
//  Created by David Frontegg on 22/01/2023.
//

import XCTest

final class demo_test: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        
    }
    
    func testExample() async throws {
        let code = UUID().uuidString
        let config = try Mocker.fronteggConfig(bundle:Bundle(for: type(of: self)))
        await Mocker.mockClearMocks()
        
        await Mocker.mock(name: .mockHostedLoginAuthorize, body:[
            "options": [
                "code":code,
                "baseUrl": config.baseUrl,
                "appUrl":config.baseUrl
            ]
        ])
        
        
        let app = launchApp()
        
        await waitForLoader(app)
        
        
        let userNameField = app.webViews.textFields["name@example.com"]
        XCTAssert(userNameField.waitForExistence(timeout: 5))
        
        takeScreenshot(named: "LoginPage")
        DispatchQueue.main.sync {
            userNameField.tap()
            userNameField.typeText("test@frontegg.com")
        }
        
        await Mocker.mock(name: .mockSSOPrelogin, body: [ "options": ["success": false]])
        
        let continueButton = app.webViews.buttons["Continue"]
        
        XCTAssert(continueButton.waitForExistence(timeout: 5))
        
        takeScreenshot(named: "PreLogin")
        DispatchQueue.main.sync {continueButton.tap()}
        
        //        let passwordField = app.webViews.secureTextFields["Set a password"]
        //        let passwordField = app.webViews.secureTextFields["Set a password"]
        //        if passwordField.waitForExistence(timeout: 5) {
        //            DispatchQueue.main.sync {
        //                passwordField.tap()
        //                passwordField.typeText("TestTest")
        //            }
        //        }
        //
        //
        //        await Mocker.mockSuccessPasswordLogin()
        //
        //        let signInButton = app.webViews.buttons["Sign in"]
        //        XCTAssert(signInButton.waitForExistence(timeout: 5))
        //        DispatchQueue.main.sync {
        //            signInButton.tap()
        //        }
        //
        //
        //        let successField = app.staticTexts["test@frontegg.com"]
        //        XCTAssert(successField.waitForExistence(timeout: 5))
        //
        //
        //
        
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
