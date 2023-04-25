//
//  loginWithSAML_test.swift
//  demo-test
//
//  Created by David Frontegg on 25/04/2023.
//

import XCTest

final class loginWithSAML_test: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    
    func testLoginWithSAML() async throws {
        
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
        
        
        app.waitWebPasswordInput("Password is required")
        takeScreenshot(named: "PreLoginPassword")
        
        
        userNameField.clearAndEnterText(app: app, "test@saml-domain.com")
        
        app.getWebButton("Continue").safeTap()
        
        
        app.waitWebLabel("OKTA SAML Mock Server")
        
        
        await Mocker.mock(name: .mockSSOAuthSamlCallback, body: ["options":[
            "success": false,
            "baseUrl": config.baseUrl,
        ]])
        
        
        
        app.getWebButton("Login With Okta").safeTap()
        
        
        let backToLoginButton = app.getWebLabel("Back to Sign-in")
        takeScreenshot(named: "Invalid Saml")
        backToLoginButton.safeTap()
        
        
        app.getWebInput("Email is required").safeTypeText("test@saml-domain.com")

        app.getWebButton("Continue").safeTap()
        
        
        await Mocker.mockSuccessSamlLogin(code)
        
        app.getWebButton("Login With Okta").safeTap()
        
        
        let successField = app.staticTexts["test@saml-domain.com"]
        XCTAssert(successField.waitForExistence(timeout: 10))
        
        DispatchQueue.main.sync { app.terminate() }
        
        let relaunchApp = launchApp()
        
        XCTAssert(relaunchApp.staticTexts["test@saml-domain.com"].waitForExistence(timeout: 10))
        
        
    }
    
    
}
