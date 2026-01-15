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
        
        do {
            try await Mocker.mockClearMocks()
            
            let code = UUID().uuidString
            try await Mocker.mock(name: .mockHostedLoginAuthorize, body:[
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
            
            let userNameField = await app.getWebInput("Email is required")
            
            takeScreenshot(named: "LoginPage")
            
            try await Mocker.mock(name: .mockSSOPrelogin, body: ["options": ["success":"true", "idpType": "saml"],
                                                                 "partialRequestBody": ["email": "test@saml-domain.com"]])
            
            await userNameField.safeTypeText("test@saml-domain.com")
            
            await app.getWebButton("Continue").safeTap()
            
            await app.waitWebLabel("OKTA SAML Mock Server")
            
            try await Mocker.mock(name: .mockSSOAuthSamlCallback, body: ["options":[
                "success": false,
                "baseUrl": config.baseUrl,
            ] as [String : Any]])
            
            await app.getWebButton("Login With Okta").safeTap()
            
            let backToLoginButton = await app.getWebLabel("Back to Sign-in")
            takeScreenshot(named: "Invalid Saml")
            await backToLoginButton.safeTap()
            
            await app.getWebInput("Email is required").safeTypeText("test@saml-domain.com")

            await app.getWebButton("Continue").safeTap()
            
            try await Mocker.mockSuccessSamlLogin(code)
            
            await app.getWebButton("Login With Okta").safeTap()
            
            let successField = await app.staticTexts["test@saml-domain.com"]
            XCTAssert(successField.waitForExistence(timeout: 10))
            
            DispatchQueue.main.sync { app.terminate() }
            
            let relaunchApp = launchApp()
            
            XCTAssert(relaunchApp.staticTexts["test@saml-domain.com"].waitForExistence(timeout: 10))
        } catch let error as MockServerError {
            XCTSkip("Mock server unavailable: \(error). Skipping E2E test.")
        }
    }
    
    
}
