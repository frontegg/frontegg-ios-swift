//
//  FronteggAuthRefreshRotationTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

/// In-memory `CredentialManager` — the iOS simulator rejects real keychain
/// writes with errSecMissingEntitlement in SPM test bundles.
private final class InMemoryCredentialManager: CredentialManager {
    private let lock = NSLock()
    private var store: [String: String] = [:]

    override func save(key: String, value: String) throws {
        lock.withLock { store[key] = value }
    }

    override func get(key: String) throws -> String? {
        lock.withLock { store[key] }
    }

    override func delete(key: String) {
        _ = lock.withLock { store.removeValue(forKey: key) }
    }

    override func clear() {
        lock.withLock { store.removeAll() }
    }

    override func clear(excludingKeys: [String]) {
        lock.withLock {
            store = store.filter { excludingKeys.contains($0.key) }
        }
    }
}

private final class MockRotationApi: Api {
    private(set) var refreshCallCount = 0
    private(set) var sentRefreshTokens: [String] = []
    private(set) var meCallCount = 0

    /// What `refreshToken(...)` returns once `refreshGate` (if set) is released.
    var refreshResult: Result<AuthResponse, Error>?

    /// Artificial delay inside `refreshToken(...)` before returning. Used to
    /// simulate a slow network for the serialization test. Ignored when
    /// `refreshGate` is configured.
    var refreshDelayNanos: UInt64 = 0

    /// When set, `refreshToken(...)` awaits this continuation before returning.
    /// Tests can use this to hold the refresh mid-flight, mutate auth state
    /// (e.g. simulate another path rotating the token), and then resume.
    private var heldGate: CheckedContinuation<Void, Never>?
    private var gateEntered: XCTestExpectation?

    var meFailure: Error?
    var meResult: MeResult?

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    func installRefreshGate(entered expectation: XCTestExpectation) {
        self.gateEntered = expectation
    }

    /// Releases the refresh call that is currently waiting on the gate.
    /// Must be called exactly once after `installRefreshGate`.
    func releaseRefreshGate() {
        let continuation = heldGate
        heldGate = nil
        continuation?.resume()
    }

    override func refreshToken(
        refreshToken: String,
        tenantId: String? = nil,
        accessToken: String? = nil
    ) async throws -> AuthResponse {
        refreshCallCount += 1
        sentRefreshTokens.append(refreshToken)

        if let gateEntered = gateEntered {
            self.gateEntered = nil
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.heldGate = cont
                gateEntered.fulfill()
            }
        } else if refreshDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: refreshDelayNanos)
        }

        guard let refreshResult else {
            throw ApiError.invalidUrl("no refresh result configured")
        }
        switch refreshResult {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    override func me(accessToken: String, refreshToken: String) async throws -> MeResult {
        meCallCount += 1
        if let meFailure {
            throw meFailure
        }
        if let meResult {
            return meResult
        }
        return try await super.me(accessToken: accessToken, refreshToken: refreshToken)
    }
}

final class FronteggAuthRefreshRotationTests: XCTestCase {
    private var auth: FronteggAuth!
    private var api: MockRotationApi!
    private var credentialManager: InMemoryCredentialManager!
    private var serviceKey: String!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()

        serviceKey = "frontegg-refresh-rotation-\(UUID().uuidString)"
        credentialManager = InMemoryCredentialManager(serviceKey: serviceKey)
        PlistHelper.testConfigOverride = makeConfig(serviceKey: serviceKey, enableOfflineMode: true)
        FronteggAuth.testNetworkPathAvailabilityOverride = true

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
        api = MockRotationApi()
        auth.api = api
        auth.setInitializing(false)
        auth.setIsLoading(false)
        auth.setShowLoader(false)
        auth.setWebLoading(false)
        auth.setAccessToken(nil)
        auth.setUser(nil)
        auth.setIsAuthenticated(false)
        credentialManager.clear()
    }

    override func tearDown() {
        auth.cancelScheduledTokenRefresh()
        NetworkStatusMonitor._testReset()
        credentialManager.clear()
        PlistHelper.testConfigOverride = nil
        FronteggAuth.testNetworkPathAvailabilityOverride = nil
        api = nil
        auth = nil
        credentialManager = nil
        serviceKey = nil
        super.tearDown()
    }

    // MARK: - Rotation-orphan persistence

    func test_refreshTokenIfNeeded_persistsRotatedTokensToKeychainBeforePostRefreshWork() async throws {
        try credentialManager.save(key: KeychainKeys.refreshToken.rawValue, value: "RT_OLD")
        try credentialManager.save(key: KeychainKeys.accessToken.rawValue, value: "AT_OLD")
        auth.setRefreshToken("RT_OLD")

        let rotatedAccess = try makeAccessToken(email: "rotation@example.com", tenantId: "tenant-123")
        api.refreshResult = .success(try makeAuthResponse(accessToken: rotatedAccess, refreshToken: "RT_NEW"))
        // /me must fail non-connectivity so setCredentialsInternal hits
        // clearAuthStateAfterHydrationFailure (wipes memory but not keychain).
        api.meFailure = ApiError.meEndpointFailed(statusCode: 500, path: "identity/resources/users/v2/me")

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertFalse(refreshed, "hydration must fail so we can observe the post-fail keychain state")

        let persistedRefresh = try credentialManager.get(key: KeychainKeys.refreshToken.rawValue)
        let persistedAccess = try credentialManager.get(key: KeychainKeys.accessToken.rawValue)
        XCTAssertEqual(persistedRefresh, "RT_NEW", "rotated refresh token must be persisted before post-refresh work")
        XCTAssertEqual(persistedAccess, rotatedAccess)
        XCTAssertEqual(api.sentRefreshTokens, ["RT_OLD"])
    }

    // MARK: - Serialization of concurrent refresh callers

    func test_refreshTokenIfNeeded_concurrentCallers_performOnlyOneNetworkRefresh() async throws {
        seedInMemorySessionWithCachedUser(email: "serial@example.com")

        let rotatedAccess = try makeAccessToken(email: "serial@example.com", tenantId: "tenant-123")
        api.refreshResult = .success(try makeAuthResponse(accessToken: rotatedAccess, refreshToken: "RT_NEW"))
        api.refreshDelayNanos = 200_000_000

        async let r1 = auth.refreshTokenIfNeeded()
        async let r2 = auth.refreshTokenIfNeeded()
        async let r3 = auth.refreshTokenIfNeeded()
        let results = await (r1, r2, r3)

        XCTAssertEqual(api.refreshCallCount, 1, "concurrent refresh callers must collapse to one network request")
        XCTAssertEqual(api.sentRefreshTokens, ["RT_OLD"])
        XCTAssertEqual(results.0, results.1)
        XCTAssertEqual(results.1, results.2)
        XCTAssertTrue(results.0)
    }

    func test_refreshTokenIfNeeded_serialRefreshAfterConcurrentGroup_startsNewRequest() async throws {
        seedInMemorySessionWithCachedUser(email: "serial-after@example.com")

        let firstAccess = try makeAccessToken(email: "serial-after@example.com", tenantId: "tenant-123")
        api.refreshResult = .success(try makeAuthResponse(accessToken: firstAccess, refreshToken: "RT_INTERMEDIATE"))
        let firstResult = await auth.refreshTokenIfNeeded()
        XCTAssertTrue(firstResult)

        let secondAccess = try makeAccessToken(email: "serial-after@example.com", tenantId: "tenant-123")
        api.refreshResult = .success(try makeAuthResponse(accessToken: secondAccess, refreshToken: "RT_FINAL"))
        let secondResult = await auth.refreshTokenIfNeeded()
        XCTAssertTrue(secondResult)

        XCTAssertEqual(api.refreshCallCount, 2, "sequential callers must each trigger their own network request")
        XCTAssertEqual(api.sentRefreshTokens, ["RT_OLD", "RT_INTERMEDIATE"])
        XCTAssertEqual(auth.refreshToken, "RT_FINAL")
    }

    // MARK: - RT-change guard

    func test_refreshTokenIfNeeded_failedToRefreshToken_preservesCredentials_whenInMemoryRefreshTokenWasRotated() async throws {
        auth.setRefreshToken("RT_OLD")
        auth.setAccessToken("AT_OLD")
        auth.setIsAuthenticated(true)

        let gateEntered = expectation(description: "refresh entered")
        api.installRefreshGate(entered: gateEntered)
        api.refreshResult = .failure(
            FronteggError.authError(.failedToRefreshToken("Refresh token could not be found"))
        )

        let refreshTask = Task { await auth.refreshTokenIfNeeded() }

        await fulfillment(of: [gateEntered], timeout: 2.0)

        await MainActor.run {
            self.auth.setRefreshToken("RT_NEWER_FROM_SIDE_CHANNEL")
        }

        api.releaseRefreshGate()
        let refreshed = await refreshTask.value

        XCTAssertFalse(refreshed)
        XCTAssertEqual(auth.refreshToken, "RT_NEWER_FROM_SIDE_CHANNEL")
        XCTAssertEqual(auth.accessToken, "AT_OLD")
        XCTAssertTrue(auth.isAuthenticated)
    }

    func test_refreshTokenIfNeeded_failedToRefreshToken_clearsCredentials_whenInMemoryRefreshTokenUnchanged() async throws {
        auth.setRefreshToken("RT_OLD")
        auth.setAccessToken("AT_OLD")
        auth.setIsAuthenticated(true)

        api.refreshResult = .failure(
            FronteggError.authError(.failedToRefreshToken("Refresh token could not be found"))
        )

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertFalse(refreshed)
        XCTAssertNil(auth.refreshToken)
        XCTAssertNil(auth.accessToken)
        XCTAssertFalse(auth.isAuthenticated)
    }

    // MARK: - Proactive refresh offset

    func test_calculateOffset_usesFiftyPercentOfRemainingTtl_whenAboveMinWindow() {
        // 600 s remaining → expect ~300 s offset (50%), not the old 480 s (80%).
        let now = Date().timeIntervalSince1970
        let offset = auth.calculateOffset(expirationTime: Int(now) + 600)
        XCTAssertEqual(offset, 300, accuracy: 2.0, "offset must refresh at 50% of remaining TTL")
    }

    func test_calculateOffset_clampsToMinRefreshWindow_whenNearExpiry() {
        // 10 s remaining — below 20 s minRefreshWindow — offset clamps to 0.
        let now = Date().timeIntervalSince1970
        let offset = auth.calculateOffset(expirationTime: Int(now) + 10)
        XCTAssertEqual(offset, 0, accuracy: 0.5)
    }

    // MARK: - Refresh-in-flight tombstone

    func test_refreshTokenIfNeeded_successfulRefresh_clearsRefreshInFlightTombstone() async throws {
        seedInMemorySessionWithCachedUser(email: "tombstone-success@example.com")

        let rotatedAccess = try makeAccessToken(email: "tombstone-success@example.com", tenantId: "tenant-123")
        api.refreshResult = .success(try makeAuthResponse(accessToken: rotatedAccess, refreshToken: "RT_NEW"))

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertNil(
            try credentialManager.get(key: KeychainKeys.refreshInFlight.rawValue),
            "tombstone must be cleared after a refresh that completed + persisted"
        )
    }

    func test_refreshTokenIfNeeded_interruptedRefresh_leavesTombstoneForNextLaunch() async throws {
        auth.setRefreshToken("RT_OLD")
        auth.setAccessToken("AT_OLD")
        auth.setIsAuthenticated(true)

        // Connectivity failure mid-request — we cannot know whether the server
        // processed the rotation, so the tombstone must survive for the next
        // launch to observe the orphan.
        api.refreshResult = .failure(URLError(.timedOut))

        _ = await auth.refreshTokenIfNeeded()

        let tombstone = try credentialManager.get(key: KeychainKeys.refreshInFlight.rawValue)
        XCTAssertNotNil(tombstone, "tombstone must survive a connectivity failure")
        XCTAssertEqual(tombstone, auth.refreshTokenFingerprint("RT_OLD"))
    }

    func test_refreshTokenIfNeeded_failedToRefreshToken_clearsTombstone_onDefinitiveRejection() async throws {
        auth.setRefreshToken("RT_OLD")
        auth.setAccessToken("AT_OLD")
        auth.setIsAuthenticated(true)

        api.refreshResult = .failure(
            FronteggError.authError(.failedToRefreshToken("Refresh token could not be found"))
        )

        _ = await auth.refreshTokenIfNeeded()

        XCTAssertNil(
            try credentialManager.get(key: KeychainKeys.refreshInFlight.rawValue),
            "tombstone must be cleared after definitive server rejection — there is no unresolved in-flight request anymore"
        )
    }

    func test_hasOrphanedRefreshTombstone_matchesByFingerprint() {
        auth.writeRefreshInFlightTombstone(for: "RT_FROM_PREVIOUS_PROCESS")
        XCTAssertTrue(auth.hasOrphanedRefreshTombstone(matching: "RT_FROM_PREVIOUS_PROCESS"))
        XCTAssertFalse(auth.hasOrphanedRefreshTombstone(matching: "DIFFERENT_TOKEN"))
        XCTAssertFalse(auth.hasOrphanedRefreshTombstone(matching: nil))
    }

    // MARK: - Refresh-token timeout plist

    func test_api_resolveRefreshTokenTimeout_returnsPlistValue_whenAboveFloor() {
        PlistHelper.testConfigOverride = makeConfig(serviceKey: serviceKey, enableOfflineMode: false, refreshTokenTimeout: 25)
        let api = Api(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
        XCTAssertEqual(api.resolveRefreshTokenTimeout(), 25)
    }

    func test_api_resolveRefreshTokenTimeout_clampsToTenSeconds_whenPlistUnderfloors() {
        PlistHelper.testConfigOverride = makeConfig(serviceKey: serviceKey, enableOfflineMode: false, refreshTokenTimeout: 3)
        let api = Api(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
        XCTAssertGreaterThanOrEqual(api.resolveRefreshTokenTimeout(), 10)
    }

    func test_api_resolveRefreshTokenTimeout_usesTwentySecondDefault_whenPlistAbsent() {
        PlistHelper.testConfigOverride = nil
        let api = Api(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
        XCTAssertEqual(api.resolveRefreshTokenTimeout(), 20)
    }

    // MARK: - Helpers

    /// Seeds tokens + a cached user so `setCredentialsInternal` takes the
    /// "existingUser, tenant unchanged" fast path and skips /me.
    private func seedInMemorySessionWithCachedUser(email: String, tenantId: String = "tenant-123") {
        auth.setRefreshToken("RT_OLD")
        auth.setAccessToken("AT_OLD")
        do {
            auth.setUser(try makeUser(email: email, tenantId: tenantId))
        } catch {
            XCTFail("Failed to build cached user: \(error)")
        }
        auth.setIsAuthenticated(true)
    }

    private func makeConfig(
        serviceKey: String,
        enableOfflineMode: Bool,
        refreshTokenTimeout: TimeInterval = 20
    ) -> FronteggPlist {
        FronteggPlist(
            keychainService: serviceKey,
            embeddedMode: true,
            loginWithSocialLogin: true,
            handleLoginWithCustomSocialLoginProvider: true,
            handleLoginWithSocialProvider: true,
            loginWithSSO: true,
            loginWithCustomSSO: true,
            lateInit: false,
            logLevel: .warn,
            payload: .singleRegion(
                .init(baseUrl: "https://test.example.com", clientId: "test-client-id")
            ),
            keepUserLoggedInAfterReinstall: true,
            useAsWebAuthenticationForAppleLogin: true,
            shouldSuggestSavePassword: false,
            deleteCookieForHostOnly: true,
            enableOfflineMode: enableOfflineMode,
            useLegacySocialLoginFlow: false,
            enableSessionPerTenant: false,
            networkMonitoringInterval: 1,
            enableSentryLogging: false,
            sentryMaxQueueSize: 10,
            entitlementsEnabled: false,
            refreshTokenTimeout: refreshTokenTimeout
        )
    }

    private func makeAuthResponse(accessToken: String, refreshToken: String) throws -> AuthResponse {
        let json = TestDataFactory.makeAuthResponse(
            refreshToken: refreshToken,
            accessToken: accessToken
        )
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    private func makeAccessToken(
        email: String,
        tenantId: String = "tenant-123",
        expirationOffset: TimeInterval = 3600
    ) throws -> String {
        let payload: [String: Any] = [
            "sub": UUID().uuidString,
            "email": email,
            "name": "Rotation User",
            "tenantId": tenantId,
            "tenantIds": [tenantId],
            "exp": Int(Date().timeIntervalSince1970 + expirationOffset)
        ]
        return try TestDataFactory.makeJWT(payloadDict: payload)
    }

    private func makeUser(email: String, tenantId: String = "tenant-123") throws -> User {
        let tenant = TestDataFactory.makeTenant(id: tenantId, name: "Tenant \(tenantId)", tenantId: tenantId)
        let data = try JSONSerialization.data(withJSONObject: TestDataFactory.makeUser(
            email: email,
            tenantId: tenantId,
            tenantIds: [tenantId],
            tenants: [tenant],
            activeTenant: tenant
        ))
        return try JSONDecoder().decode(User.self, from: data)
    }
}
