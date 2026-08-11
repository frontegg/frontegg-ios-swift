import XCTest
@testable import FronteggSwift

final class SessionRestoreLockedKeychainTests: XCTestCase {

    private var credentialManager: CredentialManager!
    private var auth: FronteggAuth!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()
        FronteggAuth.testNetworkPathAvailabilityOverride = true
        FronteggAuth.testProtectedDataAvailableOverride = nil
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
        auth.setInitializing(true)
    }

    override func tearDown() {
        auth = nil
        credentialManager = nil
        FronteggAuth.testNetworkPathAvailabilityOverride = nil
        FronteggAuth.testProtectedDataAvailableOverride = nil
        NetworkStatusMonitor._testReset()
        super.tearDown()
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func tokenReader(_ value: String) -> (CFDictionary, UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        return { _, result in
            result?.pointee = Data(value.utf8) as AnyObject
            return errSecSuccess
        }
    }

    func testDeferredRestoreRestoresSessionOnceKeychainBecomesReadable() {
        FronteggAuth.testProtectedDataAvailableOverride = false
        credentialManager.copyMatching = { _, _ in errSecInteractionNotAllowed }

        auth.initializeSubscriptions()
        XCTAssertNil(auth.refreshToken)

        FronteggAuth.testProtectedDataAvailableOverride = true
        credentialManager.copyMatching = tokenReader("stored-refresh-token")
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)

        XCTAssertTrue(waitUntil { self.auth.refreshToken == "stored-refresh-token" })
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
