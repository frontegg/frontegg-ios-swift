//
//  loginWithOIDC_test.swift
//  demo-test
//
//  Created by David Frontegg on 25/04/2023.
//

import Foundation

import XCTest

final class loginWithOIDC_test: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    
    func testLoginWithOIDC() async throws {
        
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
        
        app.getWebInput("Email is required")
            .safeTypeText("test@oidc-domain.com")
        
        await Mocker.mock(name: .mockSSOPrelogin, body: ["options": ["success":"true", "idpType": "oidc"],
                                                         "partialRequestBody": ["email": "test@oidc-domain.com"]])
        
        app.getWebButton("Continue").safeTap()
        
        app.waitWebLabel("OKTA OIDC Mock Server")
        
        
        await Mocker.mockSuccessOidcLogin(code)
        
        app.getWebButton("Login With Okta").safeTap()
        
        
        let successField = app.staticTexts["test@oidc-domain.com"]
        XCTAssert(successField.waitForExistence(timeout: 10))
        
        DispatchQueue.main.sync { app.terminate() }
        
        let relaunchApp = launchApp()
        
        XCTAssert(relaunchApp.staticTexts["test@oidc-domain.com"].waitForExistence(timeout: 10))
        
        
    }
}
