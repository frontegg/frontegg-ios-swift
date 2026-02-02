//
//  FronteggStateTests.swift
//  FronteggSwiftTests
//

import XCTest
import Combine
@testable import FronteggSwift

final class FronteggStateTests: XCTestCase {
    
    var state: FronteggState!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        state = FronteggState()
        cancellables = []
    }
    
    override func tearDown() {
        cancellables = nil
        state = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func test_initialState_hasCorrectDefaults() {
        XCTAssertNil(state.accessToken)
        XCTAssertNil(state.refreshToken)
        XCTAssertNil(state.user)
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertFalse(state.isOfflineMode)
        XCTAssertFalse(state.isStepUpAuthorization)
        XCTAssertTrue(state.isLoading)
        XCTAssertTrue(state.webLoading)
        XCTAssertFalse(state.loginBoxLoading)
        XCTAssertTrue(state.initializing)
        XCTAssertFalse(state.lateInit)
        XCTAssertTrue(state.showLoader)
        XCTAssertFalse(state.appLink)
        XCTAssertFalse(state.externalLink)
        XCTAssertNil(state.selectedRegion)
        XCTAssertFalse(state.refreshingToken)
    }
    
    // MARK: - Access Token Tests
    
    func test_setAccessToken_updatesValue() {
        state.setAccessToken("new-access-token")
        XCTAssertEqual(state.accessToken, "new-access-token")
    }
    
    func test_setAccessToken_allowsNil() {
        state.setAccessToken("token")
        state.setAccessToken(nil)
        XCTAssertNil(state.accessToken)
    }
    
    func test_setAccessToken_doesNotPublishWhenSameValue() {
        let expectation = expectation(description: "Should publish only once for different value")
        expectation.expectedFulfillmentCount = 1
        
        state.$accessToken
            .dropFirst() // Skip initial value
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        
        state.setAccessToken("token")
        state.setAccessToken("token") // Same value, should not trigger
        
        waitForExpectations(timeout: 0.1)
    }
    
    // MARK: - Refresh Token Tests
    
    func test_setRefreshToken_updatesValue() {
        state.setRefreshToken("new-refresh-token")
        XCTAssertEqual(state.refreshToken, "new-refresh-token")
    }
    
    func test_setRefreshToken_allowsNil() {
        state.setRefreshToken("token")
        state.setRefreshToken(nil)
        XCTAssertNil(state.refreshToken)
    }
    
    // MARK: - User Tests
    
    func test_setUser_updatesValue() throws {
        let userDict = TestDataFactory.makeUser(id: "test-user", name: "Test User")
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        state.setUser(user)
        
        XCTAssertNotNil(state.user)
        XCTAssertEqual(state.user?.id, "test-user")
        XCTAssertEqual(state.user?.name, "Test User")
    }
    
    func test_setUser_allowsNil() throws {
        let userDict = TestDataFactory.makeUser()
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        state.setUser(user)
        state.setUser(nil)
        
        XCTAssertNil(state.user)
    }
    
    // MARK: - Boolean State Tests
    
    func test_setIsAuthenticated_updatesValue() {
        state.setIsAuthenticated(true)
        XCTAssertTrue(state.isAuthenticated)
        
        state.setIsAuthenticated(false)
        XCTAssertFalse(state.isAuthenticated)
    }
    
    func test_setIsStepUpAuthorization_updatesValue() {
        state.setIsStepUpAuthorization(true)
        XCTAssertTrue(state.isStepUpAuthorization)
        
        state.setIsStepUpAuthorization(false)
        XCTAssertFalse(state.isStepUpAuthorization)
    }
    
    func test_setIsLoading_updatesValue() {
        state.setIsLoading(false)
        XCTAssertFalse(state.isLoading)
        
        state.setIsLoading(true)
        XCTAssertTrue(state.isLoading)
    }
    
    func test_setWebLoading_updatesValue() {
        state.setWebLoading(false)
        XCTAssertFalse(state.webLoading)
        
        state.setWebLoading(true)
        XCTAssertTrue(state.webLoading)
    }
    
    func test_setLoginBoxLoading_updatesValue() {
        state.setLoginBoxLoading(true)
        XCTAssertTrue(state.loginBoxLoading)
        
        state.setLoginBoxLoading(false)
        XCTAssertFalse(state.loginBoxLoading)
    }
    
    func test_setInitializing_updatesValue() {
        state.setInitializing(false)
        XCTAssertFalse(state.initializing)
        
        state.setInitializing(true)
        XCTAssertTrue(state.initializing)
    }
    
    func test_setLateInit_updatesValue() {
        state.setLateInit(true)
        XCTAssertTrue(state.lateInit)
        
        state.setLateInit(false)
        XCTAssertFalse(state.lateInit)
    }
    
    func test_setShowLoader_updatesValue() {
        state.setShowLoader(false)
        XCTAssertFalse(state.showLoader)
        
        state.setShowLoader(true)
        XCTAssertTrue(state.showLoader)
    }
    
    func test_setAppLink_updatesValue() {
        state.setAppLink(true)
        XCTAssertTrue(state.appLink)
        
        state.setAppLink(false)
        XCTAssertFalse(state.appLink)
    }
    
    func test_setExternalLink_updatesValue() {
        state.setExternalLink(true)
        XCTAssertTrue(state.externalLink)
        
        state.setExternalLink(false)
        XCTAssertFalse(state.externalLink)
    }
    
    // MARK: - Selected Region Tests
    
    func test_setSelectedRegion_updatesValue() throws {
        let regionDict: [String: Any] = [
            "key": "us",
            "baseUrl": "https://us.example.com",
            "clientId": "client-us"
        ]
        let data = try TestDataFactory.jsonData(from: regionDict)
        let region = try JSONDecoder().decode(RegionConfig.self, from: data)
        
        state.setSelectedRegion(region)
        
        XCTAssertNotNil(state.selectedRegion)
        XCTAssertEqual(state.selectedRegion?.key, "us")
        XCTAssertEqual(state.selectedRegion?.baseUrl, "https://us.example.com")
    }
    
    func test_setSelectedRegion_allowsNil() throws {
        let regionDict: [String: Any] = [
            "key": "us",
            "baseUrl": "https://us.example.com",
            "clientId": "client-us"
        ]
        let data = try TestDataFactory.jsonData(from: regionDict)
        let region = try JSONDecoder().decode(RegionConfig.self, from: data)
        
        state.setSelectedRegion(region)
        state.setSelectedRegion(nil)
        
        XCTAssertNil(state.selectedRegion)
    }
    
    // MARK: - Offline Mode Tests (Main Thread Handling)
    
    func test_setIsOfflineMode_updatesValueOnMainThread() {
        let expectation = expectation(description: "Value should be updated")
        
        DispatchQueue.main.async {
            self.state.setIsOfflineMode(true)
            XCTAssertTrue(self.state.isOfflineMode)
            
            self.state.setIsOfflineMode(false)
            XCTAssertFalse(self.state.isOfflineMode)
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func test_setIsOfflineMode_handlesBackgroundThread() {
        let expectation = expectation(description: "Value should be updated from background")
        
        DispatchQueue.global().async {
            self.state.setIsOfflineMode(true)
            
            // Give time for the main queue dispatch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertTrue(self.state.isOfflineMode)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - Refreshing Token Tests (Main Thread Handling)
    
    func test_setRefreshingToken_updatesValueOnMainThread() {
        let expectation = expectation(description: "Value should be updated")
        
        DispatchQueue.main.async {
            self.state.setRefreshingToken(true)
            XCTAssertTrue(self.state.refreshingToken)
            
            self.state.setRefreshingToken(false)
            XCTAssertFalse(self.state.refreshingToken)
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func test_setRefreshingToken_handlesBackgroundThread() {
        let expectation = expectation(description: "Value should be updated from background")
        
        DispatchQueue.global().async {
            self.state.setRefreshingToken(true)
            
            // Give time for the main queue dispatch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertTrue(self.state.refreshingToken)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - Publisher Tests
    
    func test_accessToken_publishes_whenValueChanges() {
        let expectation = expectation(description: "Should receive published value")
        var receivedValues: [String?] = []
        
        state.$accessToken
            .dropFirst() // Skip initial nil
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        state.setAccessToken("first")
        state.setAccessToken("second")
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(receivedValues, ["first", "second"])
    }
    
    func test_isAuthenticated_publishes_whenValueChanges() {
        let expectation = expectation(description: "Should receive published value")
        var receivedValues: [Bool] = []
        
        state.$isAuthenticated
            .dropFirst() // Skip initial false
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        state.setIsAuthenticated(true)
        state.setIsAuthenticated(false)
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(receivedValues, [true, false])
    }
    
    // MARK: - Guard Tests (setIfChanged)
    
    func test_setIfChanged_preventsUnnecessaryUpdates() {
        var updateCount = 0
        
        state.$isLoading
            .dropFirst() // Skip initial value
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)
        
        // Initial state is true, so setting to true should not trigger update
        state.setIsLoading(true)
        XCTAssertEqual(updateCount, 0)
        
        // Setting to false should trigger update
        state.setIsLoading(false)
        XCTAssertEqual(updateCount, 1)
        
        // Setting to false again should not trigger update
        state.setIsLoading(false)
        XCTAssertEqual(updateCount, 1)
    }
    
    func test_setIfChanged_forOptionalStrings() {
        var updateCount = 0
        
        state.$accessToken
            .dropFirst() // Skip initial nil
            .sink { _ in updateCount += 1 }
            .store(in: &cancellables)
        
        // Setting same nil should not trigger update
        state.setAccessToken(nil)
        XCTAssertEqual(updateCount, 0)
        
        // Setting to value should trigger update
        state.setAccessToken("token")
        XCTAssertEqual(updateCount, 1)
        
        // Setting same value should not trigger update
        state.setAccessToken("token")
        XCTAssertEqual(updateCount, 1)
        
        // Setting different value should trigger update
        state.setAccessToken("different-token")
        XCTAssertEqual(updateCount, 2)
    }
}
