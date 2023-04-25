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
        
        let userNameField = app.webViews.textFields["Email is required"]
        
        
        takeScreenshot(named: "LoginPage")
        DispatchQueue.main.sync {
            userNameField.waitUntilExists().tap()
            userNameField.typeText("test@frontegg.com")
        }
        
        await Mocker.mock(name: .mockSSOPrelogin, body: ["options": ["success":"true", "idpType": "saml"],
                                                         "partialRequestBody": ["email": "test@saml-domain.com"]])
        
        let continueButton = app.webViews.buttons["Continue"]
        DispatchQueue.main.sync {
            continueButton.waitUntilExists().tap()
        }
        
        
        let passwordField = app.webViews.secureTextFields["Enter your password"]
        XCTAssert(passwordField.waitForExistence(timeout: 5))
        takeScreenshot(named: "PreLoginPassword")
        
        
        DispatchQueue.main.sync {
            userNameField.waitUntilExists().tap()
            userNameField.press(forDuration: 1)
            app.collectionViews.staticTexts["Select All"].waitUntilExists().tap()
            userNameField.clearAndEnterText(text: "test@saml-domain.com")
        }
        
        
        XCTAssert(continueButton.waitForExistence(timeout: 5))
        DispatchQueue.main.sync {continueButton.tap()}
        
        
        let oktaLabel = app.webViews.staticTexts["OKTA SAML Mock Server"]
        XCTAssert(oktaLabel.waitForExistence(timeout: 5))
        
        let oktaButton = app.webViews.buttons["Login With Okta"]
        XCTAssert(oktaButton.waitForExistence(timeout: 5))
        takeScreenshot(named: "OktaSaml")
        
        await Mocker.mockSuccessSamlLogin(code)
        
        DispatchQueue.main.sync {oktaButton.tap()}
        
        
        let successField = app.staticTexts["test@saml-domain.com"]
        XCTAssert(successField.waitForExistence(timeout: 100))
        
        DispatchQueue.main.sync { app.terminate() }
        
        let relaunchApp = launchApp()
        
        XCTAssert(relaunchApp.staticTexts["test@saml-domain.com"].waitForExistence(timeout: 100))
        
        
    }
}
