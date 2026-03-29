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

    // MARK: - pendingOAuthState URL Parsing Tests

    func test_pendingOAuthState_extracts_state_from_url() {
        let url = URL(string: "https://example.com/callback?state=abc123&code=xyz")!
        XCTAssertEqual(CredentialManager.pendingOAuthState(from: url), "abc123")
    }

    func test_pendingOAuthState_returnsNil_when_no_state_param() {
        let url = URL(string: "https://example.com/callback?code=xyz")!
        XCTAssertNil(CredentialManager.pendingOAuthState(from: url))
    }

    func test_pendingOAuthState_returnsNil_when_state_is_empty() {
        let url = URL(string: "https://example.com/callback?state=&code=xyz")!
        XCTAssertNil(CredentialManager.pendingOAuthState(from: url))
    }

    func test_pendingOAuthState_handles_encoded_state() {
        let url = URL(string: "https://example.com/callback?state=abc%20123")!
        XCTAssertEqual(CredentialManager.pendingOAuthState(from: url), "abc 123")
    }

    func test_pendingOAuthState_picks_first_non_empty_state() {
        let url = URL(string: "https://example.com/callback?state=first&state=second")!
        XCTAssertEqual(CredentialManager.pendingOAuthState(from: url), "first")
    }

    // MARK: - Instance Keychain CRUD Tests

    private func makeKeychainManager() throws -> CredentialManager {
        let cm = CredentialManager(serviceKey: "frontegg-test-\(UUID().uuidString)")
        // Probe keychain availability — skip if entitlements are missing (simulator)
        do {
            try cm.save(key: "__probe__", value: "1")
            cm.delete(key: "__probe__")
        } catch {
            throw XCTSkip("Keychain unavailable in this environment: \(error)")
        }
        return cm
    }

    func test_save_and_get_roundtrip() throws {
        let cm = try makeKeychainManager()
        try cm.save(key: "testKey", value: "testValue")
        let result = try cm.get(key: "testKey")
        XCTAssertEqual(result, "testValue")
    }

    func test_save_overwrites_existing_value() throws {
        let cm = try makeKeychainManager()
        try cm.save(key: "key1", value: "first")
        try cm.save(key: "key1", value: "second")
        XCTAssertEqual(try cm.get(key: "key1"), "second")
    }

    func test_get_throws_for_nonexistent_key() throws {
        let cm = try makeKeychainManager()
        XCTAssertThrowsError(try cm.get(key: "nonexistent"))
    }

    func test_delete_removes_saved_value() throws {
        let cm = try makeKeychainManager()
        try cm.save(key: "delKey", value: "val")
        cm.delete(key: "delKey")
        XCTAssertThrowsError(try cm.get(key: "delKey"))
    }

    func test_delete_nonexistent_key_doesNotThrow() throws {
        let cm = try makeKeychainManager()
        cm.delete(key: "neverSaved") // should not crash
    }

    func test_clear_removes_all_saved_values() throws {
        let cm = try makeKeychainManager()
        try cm.save(key: "a", value: "1")
        try cm.save(key: "b", value: "2")
        cm.clear()
        XCTAssertThrowsError(try cm.get(key: "a"))
        XCTAssertThrowsError(try cm.get(key: "b"))
    }

    func test_clear_excludingKeys_preserves_specified_keys() throws {
        let cm = try makeKeychainManager()
        try cm.save(key: "keep", value: "preserved")
        try cm.save(key: "remove", value: "gone")
        cm.clear(excludingKeys: ["keep"])
        XCTAssertEqual(try cm.get(key: "keep"), "preserved")
        XCTAssertThrowsError(try cm.get(key: "remove"))
    }

    func test_clear_excludingKeys_empty_behaves_like_clear() throws {
        let cm = try makeKeychainManager()
        try cm.save(key: "x", value: "1")
        cm.clear(excludingKeys: [])
        XCTAssertThrowsError(try cm.get(key: "x"))
    }

    // MARK: - Offline User Persistence Tests

    private func makeTestUser(email: String = "test@example.com", tenantId: String = "t1") throws -> User {
        let dict = TestDataFactory.makeUser(email: email, tenantId: tenantId)
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(User.self, from: data)
    }

    func test_saveOfflineUser_and_getOfflineUser_roundtrip() throws {
        let cm = try makeKeychainManager()
        let user = try makeTestUser(email: "offline@test.com", tenantId: "t1")
        cm.saveOfflineUser(user: user)
        let retrieved = cm.getOfflineUser()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.email, "offline@test.com")
    }

    func test_saveOfflineUser_nil_deletes_stored_user() throws {
        let cm = try makeKeychainManager()
        let user = try makeTestUser(email: "temp@test.com", tenantId: "t1")
        cm.saveOfflineUser(user: user)
        cm.saveOfflineUser(user: nil)
        XCTAssertNil(cm.getOfflineUser())
    }

    func test_getOfflineUser_returnsNil_when_nothing_saved() throws {
        let cm = try makeKeychainManager()
        XCTAssertNil(cm.getOfflineUser())
    }

    // MARK: - Multi-Tenant Token Storage Tests

    func test_saveTokenForTenant_and_getTokenForTenant_roundtrip() throws {
        let cm = try makeKeychainManager()
        try cm.saveTokenForTenant("access-tok-1", tenantId: "tenant-1", tokenType: .accessToken)
        let result = try cm.getTokenForTenant(tenantId: "tenant-1", tokenType: .accessToken)
        XCTAssertEqual(result, "access-tok-1")
    }

    func test_saveTokenForTenant_different_tenants_are_independent() throws {
        let cm = try makeKeychainManager()
        try cm.saveTokenForTenant("tok-a", tenantId: "t-a", tokenType: .accessToken)
        try cm.saveTokenForTenant("tok-b", tenantId: "t-b", tokenType: .accessToken)
        XCTAssertEqual(try cm.getTokenForTenant(tenantId: "t-a", tokenType: .accessToken), "tok-a")
        XCTAssertEqual(try cm.getTokenForTenant(tenantId: "t-b", tokenType: .accessToken), "tok-b")
    }

    func test_deleteTokenForTenant_removes_specific_token() throws {
        let cm = try makeKeychainManager()
        try cm.saveTokenForTenant("tok", tenantId: "t1", tokenType: .accessToken)
        cm.deleteTokenForTenant(tenantId: "t1", tokenType: .accessToken)
        XCTAssertThrowsError(try cm.getTokenForTenant(tenantId: "t1", tokenType: .accessToken))
    }

    func test_deleteAllTokensForTenant_removes_both_token_types() throws {
        let cm = try makeKeychainManager()
        try cm.saveTokenForTenant("access", tenantId: "t1", tokenType: .accessToken)
        try cm.saveTokenForTenant("refresh", tenantId: "t1", tokenType: .refreshToken)
        cm.deleteAllTokensForTenant(tenantId: "t1")
        XCTAssertThrowsError(try cm.getTokenForTenant(tenantId: "t1", tokenType: .accessToken))
        XCTAssertThrowsError(try cm.getTokenForTenant(tenantId: "t1", tokenType: .refreshToken))
    }

    // MARK: - Last Active Tenant ID Tests

    func test_saveLastActiveTenantId_and_getLastActiveTenantId_roundtrip() throws {
        let cm = try makeKeychainManager()
        cm.saveLastActiveTenantId("tenant-abc")
        XCTAssertEqual(cm.getLastActiveTenantId(), "tenant-abc")
    }

    func test_getLastActiveTenantId_returnsNil_when_not_saved() throws {
        let cm = try makeKeychainManager()
        XCTAssertNil(cm.getLastActiveTenantId())
    }

    func test_deleteLastActiveTenantId_removes_value() throws {
        let cm = try makeKeychainManager()
        cm.saveLastActiveTenantId("tenant-xyz")
        cm.deleteLastActiveTenantId()
        XCTAssertNil(cm.getLastActiveTenantId())
    }
}
