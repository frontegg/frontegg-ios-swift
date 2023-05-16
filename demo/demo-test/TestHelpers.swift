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
        app.launchArguments = [
            "-AppleLanguages", "(es)",
            "-AppleLocale", "es_ES"
        ]
        DispatchQueue.main.sync { app.launch() }
        return app
    }
    
    
    func waitForLoader(_ app: XCUIApplication) async {
        // Wait for the loading indicator to disappear = content is ready
        let activityIndicator = app.otherElements["LoaderView"]
        expectation(for: NSPredicate(format: "exists == 0"), evaluatedWith: activityIndicator)
        await waitForExpectations(timeout: 30)
    }
}


extension XCUIApplication {
    
    func getWebButton(_ text: String) ->XCUIElement {
        return self.webViews.buttons[text].waitUntilExists()
    }
    
    func getWebInput(_ text: String) -> XCUIElement {
        return self.webViews.textFields[text].waitUntilExists()
    }
    func waitWebInput(_ text: String) {
        self.webViews.textFields[text].waitUntilExists()
    }
    
    func getWebPasswordInput(_ text: String) -> XCUIElement {
        return self.webViews.secureTextFields[text].waitUntilExists()
    }
    func waitWebPasswordInput(_ text: String) {
        self.webViews.secureTextFields[text].waitUntilExists()
    }
    
    func getWebLabel(_ text: String) -> XCUIElement {
        return self.webViews.staticTexts[text].waitUntilExists()
    }
    
    func waitWebLabel(_ text: String) {
        self.webViews.staticTexts[text].waitUntilExists()
    }
}

extension XCUIElement {
    /**
     Removes any current text in the field before typing in the new value
     - Parameter text: the text to enter into the field
     */
    func clearAndEnterText(app: XCUIApplication, _ text: String) {
        guard let stringValue = self.value as? String else {
            XCTFail("Tried to clear and enter text into a non string value")
            return
        }
        
        self.safeTap()
        
        DispatchQueue.main.sync {
            
            self.press(forDuration: 1)
            app.collectionViews.staticTexts["Select All"].waitUntilExists().tap()
            
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            
            self.typeText(deleteString)
            self.typeText(text)
        }
    }
    func clearText() {
        guard let stringValue = self.value as? String else {
            return
        }
        // workaround for apple bug
        if let placeholderString = self.placeholderValue, placeholderString == stringValue {
            return
        }
        
        var deleteString = String()
        for _ in stringValue {
            deleteString += XCUIKeyboardKey.delete.rawValue
        }
        typeText(deleteString)
    }
    
    func waitUntilExists(timeout: TimeInterval = 30, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        XCTAssert(self.waitForExistence(timeout: timeout))
        return self
    }
    
    
    
    func safeTap(){
        DispatchQueue.main.sync {
            self.tap()
        }
    }
    
    func safeTypeText(_ text:String) {
        self.safeTap()
        DispatchQueue.main.sync {
            self.typeText(text)
        }
    }
}



struct DeepLinkUtils {
    static func openFromSafari(with urlString: String) -> XCUIApplication {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        
        DispatchQueue.main.sync {
            
            
            safari.launch()
            XCTAssert(safari.wait(for: .runningForeground, timeout: 30))
            
            tapIfExists(app: safari, title: "Continue")
            
            safari.textFields["Address"].tap()
            
            safari.typeText(urlString)
            safari.buttons["Go"].tap()
            
            tapIfExists(app: safari, title: "Open")
            
        }
        return safari;
    }
    
    static func tapIfExists(app: XCUIApplication, title: String) {
        let button = app.buttons[title]
        _ = button.waitForExistence(timeout: 10)
        if button.exists {
            button.tap()
        }
    }
}
