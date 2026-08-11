import XCTest
@testable import FronteggSwift

final class SessionRestoreLockedKeychainTests: XCTestCase {

    private var credentialManager: CredentialManager!
    private var auth: FronteggAuth!

    override func setUp() {
        super.setUp()
        credentialManager = CredentialManager(serviceKey: "frontegg-locked-keychain-\(UUID().uuidString)")
        auth = FronteggAuth(
            baseUrl: "https://test.example.com",
            clientId: "test-client-id",
            applicationId: nil,
            credentialManager: credentialManager,
            isRegional: false,
            regionData: [],
            embeddedMode: false,
            isLateInit: true,
            entitlementsEnabled: false
        )
    }

    override func tearDown() {
        auth = nil
        credentialManager = nil
        super.tearDown()
    }

    func testLockedKeychainIsFlaggedSoRestoreCanBeDeferred() {
        credentialManager.copyMatching = { _, _ in errSecInteractionNotAllowed }

        let stored = auth.loadStoredTokens(enableSessionPerTenant: false)

        XCTAssertNil(stored.refreshToken)
        XCTAssertNil(stored.accessToken)
        XCTAssertTrue(stored.keychainUnavailable)
    }

    func testMissingTokensAreNotFlaggedAsUnavailable() {
        credentialManager.copyMatching = { _, _ in errSecItemNotFound }

        let stored = auth.loadStoredTokens(enableSessionPerTenant: false)

        XCTAssertNil(stored.refreshToken)
        XCTAssertNil(stored.accessToken)
        XCTAssertFalse(stored.keychainUnavailable)
    }

    func testLockedKeychainIsFlaggedForSessionPerTenantReads() {
        credentialManager.saveLastActiveTenantId("tenant-1")
        credentialManager.copyMatching = { _, _ in errSecInteractionNotAllowed }

        let stored = auth.loadStoredTokens(enableSessionPerTenant: true)

        XCTAssertNil(stored.refreshToken)
        XCTAssertTrue(stored.keychainUnavailable)
    }

    func testDeferredRestoreResumesOnceWhenProtectedDataBecomesAvailable() {
        let resumed = expectation(description: "restore resumed")
        resumed.assertForOverFulfill = true

        auth.awaitProtectedDataAvailability {
            resumed.fulfill()
        }

        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        wait(for: [resumed], timeout: 2)
    }
}
