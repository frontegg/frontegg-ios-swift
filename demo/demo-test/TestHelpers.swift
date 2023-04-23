//
//  TestHelpers.swift
//  demo-test
//
//  Created by David Frontegg on 23/04/2023.
//

import XCTest

extension XCTestCase {
    func takeScreenshot(named name: String) {
        // Take the screenshot
        let fullScreenshot = XCUIScreen.main.screenshot()
        
        // Create a new attachment to save our screenshot
        // and give it a name consisting of the "named"
        // parameter and the device name, so we can find
        // it later.
        let screenshotAttachment = XCTAttachment(
            uniformTypeIdentifier: "public.png",
            name: "Screenshot-\(UIDevice.current.name)-\(name).png",
            payload: fullScreenshot.pngRepresentation,
            userInfo: nil)
        
        // Usually Xcode will delete attachments after
        // the test has run; we don't want that!
        screenshotAttachment.lifetime = .keepAlways
        
        // Add the attachment to the test log,
        // so we can retrieve it later
        add(screenshotAttachment)
    }
    
    
    
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["frontegg-testing":"true"]
        DispatchQueue.main.sync { app.launch() }
        return app
    }
    
    
    func waitForLoader(_ app: XCUIApplication) async {
        // Wait for the loading indicator to disappear = content is ready
        let activityIndicator = app.otherElements["LoaderView"]
        expectation(for: NSPredicate(format: "exists == 0"), evaluatedWith: activityIndicator)
        await waitForExpectations(timeout: 10)
    }
}
