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
            
            await userNameField.safeTypeText("test@frontegg.com")
            
            try await Mocker.mock(name: .mockSSOPrelogin, body: [ "options": ["success": false]])
            
            let continueButton = await app.getWebButton("Continue")
            
            takeScreenshot(named: "PreLogin")
            await continueButton.safeTap()
            
            let passwordField = await app.getWebPasswordInput("Password is required")
            
            await passwordField.safeTypeText("Testpassword")
            
            try await Mocker.mockSuccessPasswordLogin(code)
            
            await app.getWebButton("Sign in").safeTap()
            
            let successField = await app.staticTexts["test@frontegg.com"]
            XCTAssert(successField.waitForExistence(timeout: 10))
            
            DispatchQueue.main.sync { app.terminate() }
            
            let relaunchApp = launchApp()
            
            XCTAssert(relaunchApp.staticTexts["test@frontegg.com"].waitForExistence(timeout: 10))
        } catch let error as MockServerError {
            XCTSkip("Mock server unavailable: \(error). Skipping E2E test.")
        }
        
    }    
}
