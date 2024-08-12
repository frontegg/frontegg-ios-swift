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
        
        
        let userNameField = await app.getWebInput("Email is required")
        sleep(1)
        await userNameField.safeTypeText("test@frontegg.com")
        
        
        await Mocker.mock(name: .mockPreLoginWithMagicLink, body: [:])
        
        await app.getWebButton("Continue").safeTap()
        
        
        await app.waitWebLabel("Magic link sent!")
        
        takeScreenshot(named: "MagicLinkSent")
        
        let magicLinkUrl = await Mocker.mockSuccessMagicLink(code)
        let safari = DeepLinkUtils.openFromSafari(with: magicLinkUrl)
        
        await safari.getWebButton("Sign In").safeTap()
        
        
        XCTAssert(app.wait(for: .runningForeground, timeout: 10))
        
        
        let successField = await app.staticTexts["test@frontegg.com"]
        XCTAssert(successField.waitForExistence(timeout: 20))
        
        DispatchQueue.main.sync { app.terminate() }
        
        let relaunchApp = launchApp()
        
        XCTAssert(relaunchApp.staticTexts["test@frontegg.com"].waitForExistence(timeout: 10))
    }
}
