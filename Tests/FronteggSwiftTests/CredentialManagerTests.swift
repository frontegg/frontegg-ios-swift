//
//  CredentialManagerTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class CredentialManagerTests: XCTestCase {
    
    // Test-specific keys to avoid conflicts with real app data
    private let testCodeVerifierKey = "fe_codeVerifier_test"
    private let testRegionKey = "fe_region_test"
    
    override func setUp() {
        super.setUp()
        // Clean up any existing test data
        UserDefaults.standard.removeObject(forKey: KeychainKeys.codeVerifier.rawValue)
        UserDefaults.standard.removeObject(forKey: KeychainKeys.oauthStateVerifiers.rawValue)
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)
    }
    
    override func tearDown() {
        // Clean up test data
        UserDefaults.standard.removeObject(forKey: KeychainKeys.codeVerifier.rawValue)
        UserDefaults.standard.removeObject(forKey: KeychainKeys.oauthStateVerifiers.rawValue)
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)
        super.tearDown()
    }
    
    // MARK: - KeychainKeys Tests
    
    func test_keychainKeys_hasCorrectRawValues() {
        XCTAssertEqual(KeychainKeys.accessToken.rawValue, "accessToken")
        XCTAssertEqual(KeychainKeys.refreshToken.rawValue, "refreshToken")
        XCTAssertEqual(KeychainKeys.codeVerifier.rawValue, "fe_codeVerifier")
        XCTAssertEqual(KeychainKeys.oauthStateVerifiers.rawValue, "fe_oauthStateVerifiers")
        XCTAssertEqual(KeychainKeys.region.rawValue, "fe_region")
        XCTAssertEqual(KeychainKeys.userInfo.rawValue, "user_me")
        XCTAssertEqual(KeychainKeys.lastActiveTenantId.rawValue, "fe_lastActiveTenantId")
    }
    
    // MARK: - Code Verifier Tests (UserDefaults-based)
    
    func test_saveCodeVerifier_savesValue() {
        CredentialManager.saveCodeVerifier("test-code-verifier-123")
        
        let retrieved = UserDefaults.standard.string(forKey: KeychainKeys.codeVerifier.rawValue)
        XCTAssertEqual(retrieved, "test-code-verifier-123")
    }
    
    func test_getCodeVerifier_retrievesValue() {
        UserDefaults.standard.set("stored-verifier", forKey: KeychainKeys.codeVerifier.rawValue)
        
        let retrieved = CredentialManager.getCodeVerifier()
        XCTAssertEqual(retrieved, "stored-verifier")
    }
    
    func test_getCodeVerifier_returnsNil_whenNoValue() {
        // Ensure no value exists
        UserDefaults.standard.removeObject(forKey: KeychainKeys.codeVerifier.rawValue)
        
        let retrieved = CredentialManager.getCodeVerifier()
        XCTAssertNil(retrieved)
    }
    
    func test_saveCodeVerifier_overwritesExistingValue() {
        CredentialManager.saveCodeVerifier("first-value")
        CredentialManager.saveCodeVerifier("second-value")
        
        let retrieved = CredentialManager.getCodeVerifier()
        XCTAssertEqual(retrieved, "second-value")
    }
    
    func test_codeVerifier_roundtrip() {
        let originalVerifier = "code-verifier-abc123"
        
        CredentialManager.saveCodeVerifier(originalVerifier)
        let retrieved = CredentialManager.getCodeVerifier()
        
        XCTAssertEqual(retrieved, originalVerifier)
    }

    func test_registerPendingOAuth_savesStateSpecificVerifier() {
        CredentialManager.registerPendingOAuth(state: "state-123", codeVerifier: "verifier-123")

        XCTAssertEqual(CredentialManager.getCodeVerifier(for: "state-123"), "verifier-123")
        XCTAssertTrue(CredentialManager.hasPendingOAuthStates())
    }

    func test_consumeCodeVerifier_matchingState_returnsVerifierAndPreservesFallback() {
        CredentialManager.registerPendingOAuth(state: "state-abc", codeVerifier: "verifier-abc")

        let consumed = CredentialManager.consumeCodeVerifier(for: "state-abc")

        XCTAssertEqual(consumed, "verifier-abc")
        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "verifier-abc")
    }

    func test_consumeCodeVerifier_unknownState_returnsFallbackAndKeepsPendingState() {
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")

        let consumed = CredentialManager.consumeCodeVerifier(for: "unexpected-state")

        XCTAssertEqual(consumed, "expected-verifier")
        XCTAssertTrue(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(for: "expected-state"), "expected-verifier")
    }

    func test_clearPendingOAuth_nil_preservesFallbackVerifier() {
        CredentialManager.registerPendingOAuth(state: "state-clear", codeVerifier: "verifier-clear")

        CredentialManager.clearPendingOAuth(state: nil)

        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "verifier-clear")
    }

    func test_resolveCodeVerifier_stateMatchWinsOverFallback() {
        CredentialManager.registerPendingOAuth(state: "state-123", codeVerifier: "state-verifier")
        CredentialManager.saveCodeVerifier("fallback-verifier")

        let resolution = CredentialManager.resolveCodeVerifier(for: "state-123", allowFallback: true)

        XCTAssertEqual(resolution.verifier, "state-verifier")
        XCTAssertEqual(resolution.source, .stateMatch)
        XCTAssertTrue(resolution.hasPendingOAuthStates)
    }

    func test_resolveCodeVerifier_unknownState_usesLastGeneratedFallback() {
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")

        let resolution = CredentialManager.resolveCodeVerifier(for: "unexpected-state", allowFallback: true)

        XCTAssertEqual(resolution.verifier, "expected-verifier")
        XCTAssertEqual(resolution.source, .lastGeneratedFallback)
        XCTAssertTrue(resolution.hasPendingOAuthStates)
    }

    func test_resolveCodeVerifier_unknownState_withoutFallback_returnsMissing() {
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")
        CredentialManager.clearCodeVerifier()

        let resolution = CredentialManager.resolveCodeVerifier(for: "unexpected-state", allowFallback: false)

        XCTAssertNil(resolution.verifier)
        XCTAssertEqual(resolution.source, .missing)
        XCTAssertTrue(resolution.hasPendingOAuthStates)
    }

    func test_completePendingOAuthFlow_clearsStatesAndMatchingFallback() {
        CredentialManager.registerPendingOAuth(state: "state-complete", codeVerifier: "verifier-complete")

        CredentialManager.completePendingOAuthFlow(using: "verifier-complete")

        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertNil(CredentialManager.getCodeVerifier())
    }

    func test_completePendingOAuthFlow_doesNotClearNewerFallback() {
        CredentialManager.registerPendingOAuth(state: "state-complete", codeVerifier: "original-verifier")
        CredentialManager.saveCodeVerifier("newer-verifier")

        CredentialManager.completePendingOAuthFlow(using: "original-verifier")

        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "newer-verifier")
    }

    func test_multipleStatesCanShareVerifier_whenReusingCodeVerifier() {
        CredentialManager.saveCodeVerifier("shared-verifier")
        CredentialManager.registerPendingOAuth(state: "state-a", codeVerifier: "shared-verifier")
        CredentialManager.registerPendingOAuth(state: "state-b", codeVerifier: "shared-verifier")

        let firstResolution = CredentialManager.resolveCodeVerifier(for: "state-a", allowFallback: true)
        let secondResolution = CredentialManager.resolveCodeVerifier(for: "state-b", allowFallback: true)

        XCTAssertEqual(firstResolution.verifier, "shared-verifier")
        XCTAssertEqual(firstResolution.source, .stateMatch)
        XCTAssertEqual(secondResolution.verifier, "shared-verifier")
        XCTAssertEqual(secondResolution.source, .stateMatch)
        XCTAssertTrue(CredentialManager.hasPendingOAuthStates())
    }

    func test_clearPendingOAuthFlows_clearsStateVerifiersAndLegacyVerifier() {
        CredentialManager.registerPendingOAuth(state: "state-clear", codeVerifier: "verifier-clear")

        CredentialManager.clearPendingOAuthFlows()

        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertNil(CredentialManager.getCodeVerifier())
        XCTAssertNil(CredentialManager.getCodeVerifier(for: "state-clear"))
    }
    
    // MARK: - Selected Region Tests (UserDefaults-based)
    
    func test_saveSelectedRegion_savesValue() {
        CredentialManager.saveSelectedRegion("us-east-1")
        
        let retrieved = UserDefaults.standard.string(forKey: KeychainKeys.region.rawValue)
        XCTAssertEqual(retrieved, "us-east-1")
    }
    
    func test_getSelectedRegion_retrievesValue() {
        UserDefaults.standard.set("eu-west-1", forKey: KeychainKeys.region.rawValue)
        
        let retrieved = CredentialManager.getSelectedRegion()
        XCTAssertEqual(retrieved, "eu-west-1")
    }
    
    func test_getSelectedRegion_returnsNil_whenNoValue() {
        // Ensure no value exists
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)
        
        let retrieved = CredentialManager.getSelectedRegion()
        XCTAssertNil(retrieved)
    }
    
    func test_saveSelectedRegion_overwritesExistingValue() {
        CredentialManager.saveSelectedRegion("region-1")
        CredentialManager.saveSelectedRegion("region-2")
        
        let retrieved = CredentialManager.getSelectedRegion()
        XCTAssertEqual(retrieved, "region-2")
    }
    
    func test_selectedRegion_roundtrip() {
        let originalRegion = "ap-southeast-2"
        
        CredentialManager.saveSelectedRegion(originalRegion)
        let retrieved = CredentialManager.getSelectedRegion()
        
        XCTAssertEqual(retrieved, originalRegion)
    }
    
    // MARK: - KeychainError Tests
    
    func test_keychainError_duplicateEntry_exists() {
        let error = CredentialManager.KeychainError.duplicateEntry
        XCTAssertNotNil(error)
    }
    
    func test_keychainError_valueDataIsNil_exists() {
        let error = CredentialManager.KeychainError.valueDataIsNil
        XCTAssertNotNil(error)
    }
    
    func test_keychainError_unknown_containsOSStatus() {
        let error = CredentialManager.KeychainError.unknown(-25300) // errSecItemNotFound
        
        if case .unknown(let status) = error {
            XCTAssertEqual(status, -25300)
        } else {
            XCTFail("Expected unknown error with status code")
        }
    }
    
    // MARK: - CredentialManager Instance Tests
    
    func test_credentialManager_initializesWithServiceKey() {
        let manager = CredentialManager(serviceKey: "test-service")
        XCTAssertNotNil(manager)
    }
    
    func test_credentialManager_initializesWithNilServiceKey() {
        let manager = CredentialManager(serviceKey: nil)
        XCTAssertNotNil(manager)
    }
    
    // MARK: - Token for Tenant Key Generation Tests
    
    func test_tokenForTenantKeyFormat() {
        // This tests the key generation format used internally
        let tenantId = "tenant-123"
        let accessTokenKey = "\(KeychainKeys.accessToken.rawValue)_\(tenantId)"
        let refreshTokenKey = "\(KeychainKeys.refreshToken.rawValue)_\(tenantId)"
        
        XCTAssertEqual(accessTokenKey, "accessToken_tenant-123")
        XCTAssertEqual(refreshTokenKey, "refreshToken_tenant-123")
    }
}
