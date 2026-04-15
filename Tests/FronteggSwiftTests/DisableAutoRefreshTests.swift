//
//  DisableAutoRefreshTests.swift
//  FronteggSwiftTests
//
//  Tests for the disableAutoRefresh plist configuration flag.
//

import XCTest
@testable import FronteggSwift

private final class MockAutoRefreshApi: Api {
    private(set) var refreshCallCount = 0

    var refreshResult: Result<AuthResponse, Error>?

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    override func refreshToken(
        refreshToken: String,
        tenantId: String? = nil,
        accessToken: String? = nil
    ) async throws -> AuthResponse {
        refreshCallCount += 1
        guard let refreshResult else {
            throw ApiError.invalidUrl("Missing refresh result")
        }
        switch refreshResult {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    override func sleepBeforeRetry(attempt: Int) async {}
}

final class DisableAutoRefreshTests: XCTestCase {

    private var auth: FronteggAuth!
    private var api: MockAutoRefreshApi!
    private var credentialManager: CredentialManager!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()

        let serviceKey = "frontegg-disable-auto-refresh-\(UUID().uuidString)"
        credentialManager = CredentialManager(serviceKey: serviceKey)
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
        api = MockAutoRefreshApi()
        auth.api = api
        auth.setInitializing(false)
        auth.setIsLoading(false)
        auth.setShowLoader(false)
        auth.setWebLoading(false)
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
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeConfig(
        serviceKey: String = "frontegg",
        disableAutoRefresh: Bool = false,
        enableOfflineMode: Bool = false
    ) -> FronteggPlist {
        FronteggPlist(
            keychainService: serviceKey,
            payload: .singleRegion(
                .init(baseUrl: "https://test.example.com", clientId: "test-client-id")
            ),
            keepUserLoggedInAfterReinstall: true,
            enableOfflineMode: enableOfflineMode,
            disableAutoRefresh: disableAutoRefresh
        )
    }

    private func makeAccessToken(
        expirationOffset: TimeInterval = 3600
    ) throws -> String {
        let payload: [String: Any] = [
            "sub": UUID().uuidString,
            "email": "test@example.com",
            "name": "Test User",
            "tenantId": "tenant-123",
            "tenantIds": ["tenant-123"],
            "exp": Int(Date().timeIntervalSince1970 + expirationOffset)
        ]
        return try TestDataFactory.makeJWT(payloadDict: payload)
    }

    private func makeAuthResponse(refreshToken: String) throws -> AuthResponse {
        let json = TestDataFactory.makeAuthResponse(
            refreshToken: refreshToken,
            accessToken: try makeAccessToken()
        )
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    // MARK: - isAutoRefreshBlocked

    func test_isAutoRefreshBlocked_returnsFalse_whenDisableAutoRefreshIsFalse() {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: false)
        XCTAssertFalse(auth.isAutoRefreshBlocked(source: .internalAuto))
        XCTAssertFalse(auth.isAutoRefreshBlocked(source: .manualUser))
    }

    func test_isAutoRefreshBlocked_returnsTrue_onlyForInternalAuto_whenDisableAutoRefreshIsTrue() {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: true)
        XCTAssertTrue(auth.isAutoRefreshBlocked(source: .internalAuto))
        XCTAssertFalse(auth.isAutoRefreshBlocked(source: .manualUser))
    }

    func test_isAutoRefreshBlocked_defaultsFalse_whenNoPlistOverride() {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: false)
        XCTAssertFalse(auth.isAutoRefreshBlocked(source: .internalAuto))
    }

    // MARK: - refreshTokenIfNeededInternal blocked by disableAutoRefresh

    func test_refreshTokenIfNeededInternal_returnsEarly_whenAutoRefreshBlocked() async throws {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: true)
        auth.setRefreshToken("refresh-token")
        api.refreshResult = .success(try makeAuthResponse(refreshToken: "new-refresh"))

        let result = await auth.refreshTokenIfNeededInternal(source: .internalAuto)

        XCTAssertFalse(result)
        XCTAssertEqual(api.refreshCallCount, 0, "API should not be called when auto refresh is blocked")
    }

    func test_refreshTokenIfNeededInternal_proceeds_whenSourceIsManualUser() async throws {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: true, enableOfflineMode: true)
        auth.setRefreshToken("refresh-token")
        api.refreshResult = .success(try makeAuthResponse(refreshToken: "new-refresh"))

        let result = await auth.refreshTokenIfNeededInternal(source: .manualUser)

        XCTAssertGreaterThan(api.refreshCallCount, 0, "API should be called for manual user refresh even when disableAutoRefresh=true")
    }

    func test_refreshTokenIfNeededInternal_proceeds_whenDisableAutoRefreshIsFalse() async throws {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: false, enableOfflineMode: true)
        auth.setRefreshToken("refresh-token")
        api.refreshResult = .success(try makeAuthResponse(refreshToken: "new-refresh"))

        let result = await auth.refreshTokenIfNeededInternal(source: .internalAuto)

        XCTAssertGreaterThan(api.refreshCallCount, 0, "API should be called when disableAutoRefresh=false")
    }

    // MARK: - Public refreshTokenIfNeeded always uses manualUser source

    func test_publicRefreshTokenIfNeeded_isNeverBlocked() async throws {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: true, enableOfflineMode: true)
        auth.setRefreshToken("refresh-token")
        api.refreshResult = .success(try makeAuthResponse(refreshToken: "new-refresh"))

        let result = await auth.refreshTokenIfNeeded()

        XCTAssertGreaterThan(api.refreshCallCount, 0, "Public refreshTokenIfNeeded should always proceed (manualUser source)")
    }

    // MARK: - scheduleTokenRefresh blocked by disableAutoRefresh

    func test_scheduleTokenRefresh_doesNotSchedule_whenAutoRefreshBlocked() {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: true)

        auth.scheduleTokenRefresh(offset: 0.1, source: .internalAuto)

        XCTAssertNil(auth.refreshTokenDispatch, "No dispatch should be scheduled when auto refresh is blocked")
    }

    func test_scheduleTokenRefresh_schedulesNormally_whenSourceIsManualUser() {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: true)

        auth.scheduleTokenRefresh(offset: 10, source: .manualUser)

        XCTAssertNotNil(auth.refreshTokenDispatch, "Dispatch should be scheduled for manual user source")
        auth.cancelScheduledTokenRefresh()
    }

    func test_scheduleTokenRefresh_schedulesNormally_whenDisableAutoRefreshIsFalse() {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: false)

        auth.scheduleTokenRefresh(offset: 10, source: .internalAuto)

        XCTAssertNotNil(auth.refreshTokenDispatch, "Dispatch should be scheduled when disableAutoRefresh=false")
        auth.cancelScheduledTokenRefresh()
    }

    // MARK: - refreshTokenWhenNeeded blocked by disableAutoRefresh

    func test_refreshTokenWhenNeeded_skips_whenAutoRefreshBlocked() throws {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: true)
        auth.setRefreshToken("refresh-token")
        auth.setAccessToken(try makeAccessToken(expirationOffset: 10))

        auth.refreshTokenWhenNeeded()

        XCTAssertNil(auth.refreshTokenDispatch, "No refresh should be scheduled when auto refresh is blocked")
        XCTAssertEqual(api.refreshCallCount, 0)
    }

    func test_refreshTokenWhenNeeded_proceeds_whenDisableAutoRefreshIsFalse() throws {
        PlistHelper.testConfigOverride = makeConfig(disableAutoRefresh: false)
        auth.setRefreshToken("refresh-token")
        auth.setAccessToken(try makeAccessToken(expirationOffset: 3600))

        auth.refreshTokenWhenNeeded()

        XCTAssertNotNil(auth.refreshTokenDispatch, "Refresh should be scheduled when disableAutoRefresh=false")
        auth.cancelScheduledTokenRefresh()
    }

    // MARK: - FronteggPlist disableAutoRefresh defaults to false

    func test_plistDisableAutoRefresh_defaultsToFalse() {
        let config = FronteggPlist(
            payload: .singleRegion(
                .init(baseUrl: "https://test.example.com", clientId: "test-client-id")
            ),
            keepUserLoggedInAfterReinstall: true
        )
        XCTAssertFalse(config.disableAutoRefresh)
    }

    func test_plistDisableAutoRefresh_decodesFromJSON() throws {
        let json: [String: Any] = [
            "baseUrl": "https://test.example.com",
            "clientId": "test-client-id",
            "disableAutoRefresh": true
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(FronteggPlist.self, from: data)
        XCTAssertTrue(config.disableAutoRefresh)
    }

    func test_plistDisableAutoRefresh_defaultsFalseWhenMissingFromJSON() throws {
        let json: [String: Any] = [
            "baseUrl": "https://test.example.com",
            "clientId": "test-client-id"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(FronteggPlist.self, from: data)
        XCTAssertFalse(config.disableAutoRefresh)
    }
}
