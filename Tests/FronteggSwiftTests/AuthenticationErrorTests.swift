//
//  AuthenticationErrorTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class AuthenticationErrorTests: XCTestCase {
    
    // MARK: - Error Description Tests
    
    func test_couldNotExchangeToken_errorDescription() {
        let error = FronteggError.authError(.couldNotExchangeToken("Token exchange failed"))
        XCTAssertEqual(error.errorDescription, "Token exchange failed")
    }
    
    func test_failedToAuthenticate_errorDescription() {
        let error = FronteggError.authError(.failedToAuthenticate)
        XCTAssertEqual(error.errorDescription, "Failed to authenticate with frontegg")
    }
    
    func test_failedToRefreshToken_errorDescription_withMessage() {
        let error = FronteggError.authError(.failedToRefreshToken("Token expired"))
        XCTAssertEqual(error.errorDescription, "Token expired")
    }
    
    func test_failedToRefreshToken_errorDescription_withEmptyMessage() {
        let error = FronteggError.authError(.failedToRefreshToken(""))
        XCTAssertEqual(error.errorDescription, "Failed to refresh token")
    }
    
    func test_failedToLoadUserData_errorDescription() {
        let error = FronteggError.authError(.failedToLoadUserData("Network error"))
        XCTAssertEqual(error.errorDescription, "Failed to load user data: Network error")
    }
    
    func test_failedToExtractCode_errorDescription() {
        let error = FronteggError.authError(.failedToExtractCode)
        XCTAssertEqual(error.errorDescription, "Failed to get extract code from hostedLoginCallback url")
    }
    
    func test_failedToSwitchTenant_errorDescription() {
        let error = FronteggError.authError(.failedToSwitchTenant)
        XCTAssertEqual(error.errorDescription, "Failed to switch tenant")
    }
    
    func test_failedToMFA_errorDescription() {
        let error = FronteggError.authError(.failedToMFA)
        XCTAssertEqual(error.errorDescription, "Failed MFA")
    }
    
    func test_codeVerifierNotFound_errorDescription() {
        let error = FronteggError.authError(.codeVerifierNotFound)
        XCTAssertEqual(error.errorDescription, "Code verifier not found")
    }
    
    func test_couldNotFindRootViewController_errorDescription() {
        let error = FronteggError.authError(.couldNotFindRootViewController)
        XCTAssertEqual(error.errorDescription, "Unable to find root viewController")
    }
    
    func test_invalidPasskeysRequest_errorDescription() {
        let error = FronteggError.authError(.invalidPasskeysRequest)
        XCTAssertEqual(error.errorDescription, "Invalid passkeys request")
    }
    
    func test_failedToAuthenticateWithPasskeys_errorDescription() {
        let error = FronteggError.authError(.failedToAuthenticateWithPasskeys("Biometric failed"))
        XCTAssertEqual(error.errorDescription, "Failed to authenticate with Passkeys, Biometric failed")
    }
    
    func test_operationCanceled_errorDescription() {
        let error = FronteggError.authError(.operationCanceled)
        XCTAssertEqual(error.errorDescription, "Operation canceled by user")
    }
    
    func test_mfaRequired_errorDescription() {
        let json: [String: Any] = ["mfaRequired": true, "method": "totp"]
        let error = FronteggError.authError(.mfaRequired(json))
        XCTAssertEqual(error.errorDescription, "MFA is required for authentication")
    }
    
    func test_mfaRequired_withRefreshToken_errorDescription() {
        let json: [String: Any] = ["mfaRequired": true]
        let error = FronteggError.authError(.mfaRequired(json, refreshToken: "refresh-123"))
        XCTAssertEqual(error.errorDescription, "MFA is required for authentication")
    }
    
    func test_notAuthenticated_errorDescription() {
        let error = FronteggError.authError(.notAuthenticated)
        XCTAssertEqual(error.errorDescription, "Not authenticated exception")
    }
    
    func test_invalidResponse_errorDescription() {
        let error = FronteggError.authError(.invalidResponse)
        XCTAssertEqual(error.errorDescription, "Invalid Response")
    }
    
    func test_unknown_errorDescription() {
        let error = FronteggError.authError(.unknown)
        XCTAssertEqual(error.errorDescription, "Unknown error occurred")
    }
    
    func test_other_errorDescription() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Underlying error message"])
        let error = FronteggError.authError(.other(underlyingError))
        XCTAssertEqual(error.errorDescription, "Underlying error message")
    }
    
    func test_oauthError_errorDescription() {
        let error = FronteggError.authError(.oauthError("access_denied: User denied the request"))
        XCTAssertEqual(error.errorDescription, "access_denied: User denied the request")
    }
    
    // MARK: - Failure Reason Tests
    
    func test_couldNotExchangeToken_failureReason() {
        let error = FronteggError.Authentication.couldNotExchangeToken("message")
        XCTAssertEqual(error.failureReason, "couldNotExchangeToken")
    }
    
    func test_failedToAuthenticate_failureReason() {
        let error = FronteggError.Authentication.failedToAuthenticate
        XCTAssertEqual(error.failureReason, "failedToAuthenticate")
    }
    
    func test_failedToRefreshToken_failureReason() {
        let error = FronteggError.Authentication.failedToRefreshToken("message")
        XCTAssertEqual(error.failureReason, "failedToRefreshToken")
    }
    
    func test_failedToLoadUserData_failureReason() {
        let error = FronteggError.Authentication.failedToLoadUserData("message")
        XCTAssertEqual(error.failureReason, "failedToLoadUserData")
    }
    
    func test_failedToExtractCode_failureReason() {
        let error = FronteggError.Authentication.failedToExtractCode
        XCTAssertEqual(error.failureReason, "failedToExtractCode")
    }
    
    func test_failedToSwitchTenant_failureReason() {
        let error = FronteggError.Authentication.failedToSwitchTenant
        XCTAssertEqual(error.failureReason, "failedToSwitchTenant")
    }
    
    func test_failedToMFA_failureReason() {
        let error = FronteggError.Authentication.failedToMFA
        XCTAssertEqual(error.failureReason, "failedToMFA")
    }
    
    func test_codeVerifierNotFound_failureReason() {
        let error = FronteggError.Authentication.codeVerifierNotFound
        XCTAssertEqual(error.failureReason, "codeVerifierNotFound")
    }
    
    func test_couldNotFindRootViewController_failureReason() {
        let error = FronteggError.Authentication.couldNotFindRootViewController
        XCTAssertEqual(error.failureReason, "couldNotFindRootViewController")
    }
    
    func test_invalidPasskeysRequest_failureReason() {
        let error = FronteggError.Authentication.invalidPasskeysRequest
        XCTAssertEqual(error.failureReason, "invalidPasskeysRequest")
    }
    
    func test_failedToAuthenticateWithPasskeys_failureReason() {
        let error = FronteggError.Authentication.failedToAuthenticateWithPasskeys("message")
        XCTAssertEqual(error.failureReason, "failedToAuthenticateWithPasskeys")
    }
    
    func test_operationCanceled_failureReason() {
        let error = FronteggError.Authentication.operationCanceled
        XCTAssertEqual(error.failureReason, "operationCanceled")
    }
    
    func test_mfaRequired_failureReason() {
        let error = FronteggError.Authentication.mfaRequired([:])
        XCTAssertEqual(error.failureReason, "mfaRequired")
    }
    
    func test_notAuthenticated_failureReason() {
        let error = FronteggError.Authentication.notAuthenticated
        XCTAssertEqual(error.failureReason, "notAuthenticated")
    }
    
    func test_invalidResponse_failureReason() {
        let error = FronteggError.Authentication.invalidResponse
        XCTAssertEqual(error.failureReason, "invalidResponse")
    }
    
    func test_unknown_failureReason() {
        let error = FronteggError.Authentication.unknown
        XCTAssertEqual(error.failureReason, "unknown")
    }
    
    func test_other_failureReason() {
        let error = FronteggError.Authentication.other(NSError(domain: "Test", code: 0))
        XCTAssertEqual(error.failureReason, "other")
    }
    
    func test_oauthError_failureReason() {
        let error = FronteggError.Authentication.oauthError("message")
        XCTAssertEqual(error.failureReason, "oauthError")
    }
    
    // MARK: - FronteggError Wrapper Tests
    
    func test_fronteggError_authError_passesThrough() {
        let innerError = FronteggError.Authentication.failedToAuthenticate
        let error = FronteggError.authError(innerError)
        XCTAssertEqual(error.errorDescription, "Failed to authenticate with frontegg")
    }
    
    func test_fronteggError_networkError_passesThrough() {
        let innerError = FronteggError.Authentication.failedToRefreshToken("Network unreachable")
        let error = FronteggError.networkError(innerError)
        XCTAssertEqual(error.errorDescription, "Network unreachable")
    }
    
    // MARK: - LocalizedError Conformance Tests
    
    func test_authenticationError_conformsToLocalizedError() {
        let error: LocalizedError = FronteggError.Authentication.failedToAuthenticate
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.failureReason)
    }
    
    func test_fronteggError_conformsToLocalizedError() {
        let error: LocalizedError = FronteggError.authError(.failedToAuthenticate)
        XCTAssertNotNil(error.errorDescription)
    }
}
