//
//  loginWithPassword_test.swift
//  demo-test
//
//  Created by David Frontegg on 23/04/2023.
//

import XCTest

final class loginWithPassword_test: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    
    func testLoginWithPassword() async throws {
        
        let config = try Mocker.fronteggConfig(bundle:Bundle(for: type(of: self)))
        await Mocker.mockClearMocks()
        
        
        let code = UUID().uuidString
        await Mocker.mock(name: .mockHostedLoginAuthorize, body:[
            "delay": 500,
            "options": [
                "code":code,
                "baseUrl": config.baseUrl,
                "appUrl":config.baseUrl
            ]
        ])
        
        
        let app = launchApp()
        
        takeScreenshot(named: "Loader")
        
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
        
        let passwordField = app.webViews.secureTextFields["Set a password"]
        XCTAssert(passwordField.waitForExistence(timeout: 5))
        DispatchQueue.main.sync {
            passwordField.tap()
            passwordField.typeText("TestTest")
        }
        
        await Mocker.mockSuccessPasswordLogin(code)
        
        
        
        let signInButton = app.webViews.buttons["Sign in"]
        XCTAssert(signInButton.waitForExistence(timeout: 5))
        DispatchQueue.main.sync { signInButton.tap() }
        
        
        let successField = app.staticTexts["test@frontegg.com"]
        XCTAssert(successField.waitForExistence(timeout: 100))
        
        DispatchQueue.main.sync { app.terminate() }
        
        let relaunchApp = launchApp()
        
        XCTAssert(relaunchApp.staticTexts["test@frontegg.com"].waitForExistence(timeout: 100))
    }    
}
