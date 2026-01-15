//
//  keepSessionAlive_test.swift
//  demo-test
//
//  Created by David Frontegg on 10/05/2023.
//

import XCTest


final class keepSessionAlive_test: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    
    func testKeepSessionAlive() async throws {
        let config = try Mocker.fronteggConfig(bundle:Bundle(for: type(of: self)))
        
        do {
            try await Mocker.mockClearMocks()
            try await Mocker.mockRefreshToken()
            
            let app = launchApp()
            
            await waitForLoader(app)
            
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
