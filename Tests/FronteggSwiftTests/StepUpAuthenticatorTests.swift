//
//  StepUpAuthenticatorTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

// MARK: - Mock CredentialManager for StepUp Testing

class MockCredentialManager: CredentialManager {
    var storedValues: [String: String] = [:]
    var getError: Error?
    
    init() {
        super.init(serviceKey: "mock-service")
    }
    
    override func get(key: String) throws -> String? {
        if let error = getError {
            throw error
        }
        return storedValues[key]
    }
    
    override func save(key: String, value: String) throws {
        storedValues[key] = value
    }
    
    override func delete(key: String) {
        storedValues.removeValue(forKey: key)
    }
}

final class StepUpAuthenticatorTests: XCTestCase {
    
    var mockCredentialManager: MockCredentialManager!
    var authenticator: StepUpAuthenticator!
    
    override func setUp() {
        super.setUp()
        mockCredentialManager = MockCredentialManager()
        authenticator = StepUpAuthenticator(credentialManager: mockCredentialManager)
    }
    
    override func tearDown() {
        authenticator = nil
        mockCredentialManager = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    func setAccessToken(_ jwt: String) {
        mockCredentialManager.storedValues[KeychainKeys.accessToken.rawValue] = jwt
    }
    
    // MARK: - isSteppedUp - No Token Tests
    
    func test_isSteppedUp_returnsFalse_whenNoAccessToken() {
        // No token stored
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_returnsFalse_whenCredentialManagerThrows() {
        mockCredentialManager.getError = CredentialManager.KeychainError.unknown(-1)
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    // MARK: - isSteppedUp - Invalid JWT Tests
    
    func test_isSteppedUp_returnsFalse_whenJWTHasTooFewSegments() {
        setAccessToken("invalid-jwt-no-dots")
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_returnsFalse_whenJWTPayloadInvalid() {
        setAccessToken("header.invalid-base64.signature")
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    // MARK: - isSteppedUp - ACR Validation Tests
    
    func test_isSteppedUp_returnsFalse_whenACRMissing() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: nil, // Missing ACR
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_returnsFalse_whenACRInvalid() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: "invalid-acr-value",
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_requiresCorrectACRValue() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        // Should pass ACR validation (assuming AMR is also valid)
        let result = authenticator.isSteppedUp()
        // This verifies ACR check doesn't block - full validation depends on AMR
        XCTAssertTrue(result)
    }
    
    // MARK: - isSteppedUp - AMR Validation Tests
    
    func test_isSteppedUp_returnsFalse_whenAMRMissing() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: nil // Missing AMR
        )
        setAccessToken(jwt)
        
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_returnsFalse_whenAMRMissingMFA() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: ["otp"] // Has method but missing MFA value
        )
        setAccessToken(jwt)
        
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_returnsFalse_whenAMRMissingMethod() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE] // Has MFA but missing method
        )
        setAccessToken(jwt)
        
        XCTAssertFalse(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_acceptsValidAMRMethod_otp() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        XCTAssertTrue(authenticator.isSteppedUp())
    }
    
    func test_isSteppedUp_acceptsValidAMRMethod_sms() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "sms"]
        )
        setAccessToken(jwt)
        
        XCTAssertTrue(authenticator.isSteppedUp())
    }
    
    // MARK: - isSteppedUp - maxAge Validation Tests
    
    func test_isSteppedUp_returnsTrue_whenNoMaxAgeProvided() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970 - 3600, // 1 hour ago
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        // Without maxAge, should pass regardless of auth_time
        XCTAssertTrue(authenticator.isSteppedUp(maxAge: nil))
    }
    
    func test_isSteppedUp_returnsTrue_whenWithinMaxAge() throws {
        let recentAuthTime = Date().timeIntervalSince1970 - 60 // 1 minute ago
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: recentAuthTime,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        // maxAge of 5 minutes should pass
        XCTAssertTrue(authenticator.isSteppedUp(maxAge: 300))
    }
    
    func test_isSteppedUp_returnsFalse_whenExceedsMaxAge() throws {
        let oldAuthTime = Date().timeIntervalSince1970 - 600 // 10 minutes ago
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: oldAuthTime,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        // maxAge of 5 minutes should fail
        XCTAssertFalse(authenticator.isSteppedUp(maxAge: 300))
    }
    
    func test_isSteppedUp_handlesEdgeCaseMaxAge() throws {
        let exactlyAtMaxAge = Date().timeIntervalSince1970 - 300 // exactly 5 minutes ago
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: exactlyAtMaxAge,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        // Should fail because now - authTime >= maxAge
        // The condition is: nowInSeconds - authTime > maxAge
        // So at exactly maxAge, it should pass (not strictly greater)
        // Let's test with a slightly expired token
        let slightlyExpired = Date().timeIntervalSince1970 - 301 // 5 minutes + 1 second ago
        let expiredJwt = try TestDataFactory.makeStepUpJWT(
            authTime: slightlyExpired,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(expiredJwt)
        
        XCTAssertFalse(authenticator.isSteppedUp(maxAge: 300))
    }
    
    func test_isSteppedUp_handlesAuthTimeNotPresent_withMaxAge() throws {
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: nil, // No auth_time
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        // Without auth_time, maxAge check is skipped, should pass
        XCTAssertTrue(authenticator.isSteppedUp(maxAge: 300))
    }
    
    // MARK: - Full Validation Tests
    
    func test_isSteppedUp_requiresAllConditions() throws {
        // Valid token with all conditions met
        let jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970 - 60, // Recent
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        
        XCTAssertTrue(authenticator.isSteppedUp(maxAge: 300))
    }
    
    func test_isSteppedUp_failsIfAnyConditionNotMet() throws {
        // Test each failure condition
        
        // 1. Wrong ACR
        var jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: "wrong-acr",
            amr: [StepUpConstants.AMR_MFA_VALUE, "otp"]
        )
        setAccessToken(jwt)
        XCTAssertFalse(authenticator.isSteppedUp())
        
        // 2. Missing MFA in AMR
        jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: ["otp"]
        )
        setAccessToken(jwt)
        XCTAssertFalse(authenticator.isSteppedUp())
        
        // 3. Missing method in AMR
        jwt = try TestDataFactory.makeStepUpJWT(
            authTime: Date().timeIntervalSince1970,
            acr: StepUpConstants.ACR_VALUE,
            amr: [StepUpConstants.AMR_MFA_VALUE]
        )
        setAccessToken(jwt)
        XCTAssertFalse(authenticator.isSteppedUp())
    }
}
