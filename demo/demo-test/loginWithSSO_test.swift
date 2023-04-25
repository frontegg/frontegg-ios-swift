//
//  loginWithSSO_test.swift
//  demo-test
//
//  Created by David Frontegg on 25/04/2023.
//

import XCTest

final class loginWithSSO_test: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    
    func testLoginWithSSO() async throws {
        
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
        
        let userNameField = app.getWebInput("Email is required")
        
        
        takeScreenshot(named: "LoginPage")
        
        userNameField.safeTypeText("test@frontegg.com")
        
        await Mocker.mock(name: .mockSSOPrelogin, body: ["options": ["success":"true", "idpType": "saml"],
                                                         "partialRequestBody": ["email": "test@saml-domain.com"]])
        
        
        app.getWebButton("Continue").safeTap()
        
        
        let passwordField = app.getWebPasswordInput("Password is required")
        takeScreenshot(named: "PreLoginPassword")
        
        
        userNameField.clearAndEnterText(app: app, "test@saml-domain.com")
        
        app.getWebButton("Continue").safeTap()
        
        
        let oktaLabel = app.webViews.staticTexts["OKTA SAML Mock Server"]
        XCTAssert(oktaLabel.waitForExistence(timeout: 5))
        
        await Mocker.mock(name: .mockSSOAuthCallback, body: ["options":[
            "success": false,
            "baseUrl": config.baseUrl,
        ]])
        
        
        
        app.getWebButton("Login With Okta").safeTap()
        
        
        DispatchQueue.main.sync {
            
            let backToLoginButton = app.webViews.staticTexts["Back to Sign-in"]
            backToLoginButton.waitUntilExists().tap()
            
            takeScreenshot(named: "Invalid Saml")
        }
        
        DispatchQueue.main.sync {
            let emailField = app.webViews.textFields["Email is required"]
                .waitUntilExists()
            emailField.tap()
            emailField.typeText("test@saml-domain.com")
        }
        

        
        DispatchQueue.main.sync {
            app.webViews.buttons["Continue"].waitUntilExists().tap()
            
        }
        
        
        await Mocker.mockSuccessSamlLogin(code)
        DispatchQueue.main.sync {
            app.webViews.buttons["Login With Okta"].waitUntilExists().tap()
            
        }
        
        
        let successField = app.staticTexts["test@saml-domain.com"]
        XCTAssert(successField.waitForExistence(timeout: 10))
        
        DispatchQueue.main.sync { app.terminate() }
        
        let relaunchApp = launchApp()
        
        XCTAssert(relaunchApp.staticTexts["test@saml-domain.com"].waitForExistence(timeout: 10))
        
        
    }
}
