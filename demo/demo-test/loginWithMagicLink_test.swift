//
//  loginWithMagicLink_test.swift
//  demo-test
//
//  Created by David Frontegg on 25/04/2023.
//

import XCTest

final class loginWithMagicLink_test: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    
    func testLoginWithMagicLink() async throws {
        
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
        
        
        await Mocker.mock(name: .mockSSOPrelogin, body: ["options": ["success": false]])
        await Mocker.mock(name: .mockVendorConfig, body: ["partialBody": ["authStrategy": "MagicLink"]])
        
        
        
        let app = launchApp()
        
        takeScreenshot(named: "Loader")
        
        await waitForLoader(app)
        
        
        let userNameField = app.getWebInput("Email is required")
        userNameField.safeTypeText("test@frontegg.com")
        
        
        await Mocker.mock(name: .mockPreLoginWithMagicLink, body: [:])
        
        app.getWebButton("Continue").safeTap()
        
        
        app.waitWebLabel("Magic link sent!")
        
    }
}
