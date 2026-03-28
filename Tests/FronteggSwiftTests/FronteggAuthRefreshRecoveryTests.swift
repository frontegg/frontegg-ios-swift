import XCTest
@testable import FronteggSwift

private final class MockRefreshRecoveryApi: Api {
    private(set) var refreshCallCount = 0
    private(set) var meWithRefreshCallCount = 0
    private(set) var callCounts: [String: Int] = [:]

    var refreshResult: Result<AuthResponse, Error>?
    var meWithRefreshResult: Result<MeResult, Error>?
    var responseQueues: [String: [(statusCode: Int, data: Data, error: Error?)]] = [:]

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
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    override func me(accessToken: String, refreshToken: String) async throws -> MeResult {
        if let meWithRefreshResult {
            meWithRefreshCallCount += 1
            switch meWithRefreshResult {
            case .success(let result):
                return result
            case .failure(let error):
                throw error
            }
        }
        return try await super.me(accessToken: accessToken, refreshToken: refreshToken)
    }

    override func sleepBeforeRetry(attempt: Int) async {
        // Recovery tests should not wait on retry backoff timers.
    }

    override func getRequest(
        path: String,
        accessToken: String?,
        refreshToken: String? = nil,
        additionalHeaders: [String: String] = [:],
        followRedirect: Bool = true,
        timeout: Int = Api.DEFAULT_TIMEOUT,
        retries: Int = 0
    ) async throws -> (Data, URLResponse) {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        callCounts[normalizedPath, default: 0] += 1

        guard var queue = responseQueues[normalizedPath], !queue.isEmpty else {
            throw ApiError.invalidUrl("No mock response for path: \(normalizedPath)")
        }

        let entry = queue.removeFirst()
        responseQueues[normalizedPath] = queue

        if let error = entry.error {
            if retries > 0, let nextQueue = responseQueues[normalizedPath], !nextQueue.isEmpty {
                return try await getRequest(
                    path: path,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    additionalHeaders: additionalHeaders,
                    followRedirect: followRedirect,
                    timeout: timeout,
                    retries: retries - 1
                )
            }
            throw error
        }

        let url = URL(string: "https://test.example.com/\(normalizedPath)")!
        let httpResponse = HTTPURLResponse(url: url, statusCode: entry.statusCode, httpVersion: nil, headerFields: nil)!

        if entry.statusCode == 401 {
            throw ApiError.meEndpointFailed(statusCode: 401, path: path)
        }

        if Api.isTransientRefreshHTTPStatus(entry.statusCode) {
            if retries > 0, let nextQueue = responseQueues[normalizedPath], !nextQueue.isEmpty {
                return try await getRequest(
                    path: path,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    additionalHeaders: additionalHeaders,
                    followRedirect: followRedirect,
                    timeout: timeout,
                    retries: retries - 1
                )
            }
            throw ApiError.meEndpointFailed(statusCode: entry.statusCode, path: path)
        }

        return (entry.data, httpResponse)
    }

    func enqueueJSON(path: String, statusCode: Int, json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        responseQueues[path, default: []].append((statusCode: statusCode, data: data, error: nil))
    }

    func enqueueBody(path: String, statusCode: Int, body: String) {
        responseQueues[path, default: []].append((statusCode: statusCode, data: Data(body.utf8), error: nil))
    }

    func enqueueError(path: String, error: Error) {
        responseQueues[path, default: []].append((statusCode: 0, data: Data(), error: error))
    }
}

final class FronteggAuthRefreshRecoveryTests: XCTestCase {
    private let mePath = "identity/resources/users/v2/me"
    private let tenantsPath = "identity/resources/users/v3/me/tenants"

    private var auth: FronteggAuth!
    private var api: MockRefreshRecoveryApi!
    private var credentialManager: CredentialManager!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()

        let serviceKey = "frontegg-refresh-recovery-\(UUID().uuidString)"
        credentialManager = CredentialManager(serviceKey: serviceKey)
        PlistHelper.testConfigOverride = makeOfflineConfig(serviceKey: serviceKey)
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
        api = MockRefreshRecoveryApi()
        auth.api = api
        auth.setInitializing(false)
        auth.setIsLoading(false)
        auth.setShowLoader(false)
        auth.setWebLoading(false)
        auth.setRefreshToken("refresh-token-existing")
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
        super.tearDown()
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_flakyMeEndpoint_retriesAndAuthenticates() async throws {
        api.refreshResult = .success(try makeAuthResponse(email: "retry-me@example.com", refreshToken: "refresh-token-new"))
        api.enqueueJSON(path: mePath, statusCode: 502, json: [:])
        api.enqueueJSON(path: mePath, statusCode: 200, json: TestDataFactory.makeUser(email: "retry-me@example.com"))
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.callCounts[mePath], 2)
        XCTAssertEqual(api.callCounts[tenantsPath], 1)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertEqual(auth.user?.email, "retry-me@example.com")
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_flakyTenantsEndpoint_retriesAndAuthenticates() async throws {
        api.refreshResult = .success(try makeAuthResponse(email: "retry-tenants@example.com", refreshToken: "refresh-token-new"))
        api.enqueueJSON(path: mePath, statusCode: 200, json: TestDataFactory.makeUser(email: "retry-tenants@example.com"))
        api.enqueueJSON(path: tenantsPath, statusCode: 502, json: [:])
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertEqual(api.callCounts[tenantsPath], 2)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertEqual(auth.user?.email, "retry-tenants@example.com")
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_meExhaustsRetries_entersOfflineMode() async throws {
        api.refreshResult = .success(try makeAuthResponse(email: "offline-me@example.com", refreshToken: "refresh-token-new"))
        for _ in 0..<4 {
            api.enqueueError(path: mePath, error: URLError(.timedOut))
        }

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.callCounts[mePath], 4)
        XCTAssertNil(api.callCounts[tenantsPath])
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(auth.isOfflineMode)
        await assertOfflineModePersistsBriefly()
        XCTAssertEqual(auth.user?.email, "offline-me@example.com")
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_tenantsExhaustsRetries_entersOfflineMode() async throws {
        api.refreshResult = .success(try makeAuthResponse(email: "offline-tenants@example.com", refreshToken: "refresh-token-new"))
        api.enqueueJSON(path: mePath, statusCode: 200, json: TestDataFactory.makeUser(email: "offline-tenants@example.com"))
        for _ in 0..<4 {
            api.enqueueError(path: tenantsPath, error: URLError(.networkConnectionLost))
        }

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertEqual(api.callCounts[tenantsPath], 4)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(auth.isOfflineMode)
        await assertOfflineModePersistsBriefly()
        XCTAssertEqual(auth.user?.email, "offline-tenants@example.com")
    }

    func test_refreshTokenIfNeeded_networkPathUnavailable_entersOfflineModeWithoutRefreshAttempt() async throws {
        FronteggAuth.testNetworkPathAvailabilityOverride = false
        let cachedAccessToken = try seedAuthenticatedSession(
            email: "path-offline@example.com",
            expirationOffset: -60
        )

        let refreshed = await auth.refreshTokenIfNeeded()
        let snapshot = NetworkStatusMonitor._testSnapshot()

        XCTAssertFalse(refreshed)
        XCTAssertEqual(api.refreshCallCount, 0)
        XCTAssertEqual(auth.accessToken, cachedAccessToken)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(auth.isOfflineMode)
        XCTAssertEqual(auth.user?.email, "path-offline@example.com")
        XCTAssertTrue(snapshot.monitoringActive)
        XCTAssertFalse(snapshot.emitInitialState)
        await assertOfflineModePersistsBriefly()
    }

    func test_completeAuthenticatedStartupSessionRestore_forcedUnavailable_restoresOfflineStateWithoutRefreshAttempt() async throws {
        let cachedAccessToken = try seedStartupRestoreState(
            email: "startup-offline@example.com",
            expirationOffset: -60
        )

        await auth.completeAuthenticatedStartupSessionRestore(
            accessTokenSnapshot: cachedAccessToken,
            refreshTokenSnapshot: "refresh-token-existing",
            canRestoreOfflineAuthenticatedState: true,
            assessmentProvider: { _ in .forcedUnavailable },
            postConnectivityServices: {
                XCTFail("Forced-offline startup restore should not start post-connectivity services")
            }
        )

        let snapshot = NetworkStatusMonitor._testSnapshot()

        XCTAssertEqual(api.refreshCallCount, 0)
        XCTAssertEqual(auth.accessToken, cachedAccessToken)
        XCTAssertEqual(auth.refreshToken, "refresh-token-existing")
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(auth.isOfflineMode)
        XCTAssertEqual(auth.user?.email, "startup-offline@example.com")
        XCTAssertTrue(snapshot.monitoringActive)
        XCTAssertFalse(snapshot.emitInitialState)
    }

    func test_completeAuthenticatedStartupSessionRestore_advisoryUnavailable_attemptsRefreshAndStaysOnline() async throws {
        let cachedAccessToken = try seedStartupRestoreState(
            email: "startup-refresh@example.com",
            expirationOffset: -60
        )
        let refreshedResponse = try makeAuthResponse(
            email: "startup-refresh@example.com",
            refreshToken: "refresh-token-new"
        )
        api.refreshResult = .success(refreshedResponse)

        await auth.completeAuthenticatedStartupSessionRestore(
            accessTokenSnapshot: cachedAccessToken,
            refreshTokenSnapshot: "refresh-token-existing",
            canRestoreOfflineAuthenticatedState: true,
            assessmentProvider: { _ in .advisoryUnavailable },
            postConnectivityServices: {}
        )

        let snapshot = NetworkStatusMonitor._testSnapshot()

        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(auth.accessToken, refreshedResponse.access_token)
        XCTAssertEqual(auth.refreshToken, "refresh-token-new")
        XCTAssertNotEqual(auth.accessToken, cachedAccessToken)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertFalse(snapshot.monitoringActive)
        XCTAssertEqual(auth.user?.email, "startup-refresh@example.com")
    }

    func test_getOrRefreshAccessTokenAsync_networkPathUnavailableStillAttemptsManualRefresh() async throws {
        FronteggAuth.testNetworkPathAvailabilityOverride = false
        _ = try seedAuthenticatedSession(
            email: "manual-refresh@example.com",
            expirationOffset: -60
        )

        let refreshedAccessToken = try makeAccessToken(email: "manual-refresh@example.com")
        api.refreshResult = .success(
            try makeAuthResponse(
                accessToken: refreshedAccessToken,
                refreshToken: "refresh-token-new"
            )
        )

        let token = try await auth.getOrRefreshAccessTokenAsync()
        let snapshot = NetworkStatusMonitor._testSnapshot()

        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(token, refreshedAccessToken)
        XCTAssertEqual(auth.accessToken, refreshedAccessToken)
        XCTAssertEqual(auth.refreshToken, "refresh-token-new")
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertFalse(snapshot.monitoringActive)
    }

    func test_getOrRefreshAccessTokenAsync_destinationUnreachable_preservesCachedTokenAndStartsOfflineMonitoring() async throws {
        FronteggAuth.testNetworkPathAvailabilityOverride = true
        let cachedAccessToken = try seedAuthenticatedSession(
            email: "destination-unreachable@example.com",
            expirationOffset: -60
        )
        api.refreshResult = .failure(URLError(.timedOut))

        let token = try await auth.getOrRefreshAccessTokenAsync()
        let snapshot = NetworkStatusMonitor._testSnapshot()

        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(token, cachedAccessToken)
        XCTAssertEqual(auth.accessToken, cachedAccessToken)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(auth.isOfflineMode)
        XCTAssertEqual(auth.user?.email, "destination-unreachable@example.com")
        XCTAssertTrue(snapshot.monitoringActive)
        XCTAssertFalse(snapshot.emitInitialState)
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_me401_clearsSession() async throws {
        api.refreshResult = .success(try makeAuthResponse(email: "offline-401@example.com", refreshToken: "refresh-token-new"))
        api.enqueueJSON(path: mePath, statusCode: 401, json: [:])

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertFalse(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertNil(api.callCounts[tenantsPath])
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertNil(auth.user)
        XCTAssertNil(auth.accessToken)
        XCTAssertNil(auth.refreshToken)
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_meHtmlProxyResponse_clearsSession() async throws {
        api.refreshResult = .success(try makeAuthResponse(email: "offline-html@example.com", refreshToken: "refresh-token-new"))
        api.enqueueBody(path: mePath, statusCode: 403, body: "<html><body>Proxy blocked</body></html>")

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertFalse(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertNil(api.callCounts[tenantsPath])
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertNil(auth.user)
        XCTAssertNil(auth.accessToken)
        XCTAssertNil(auth.refreshToken)
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_tenants401_clearsSession() async throws {
        api.refreshResult = .success(try makeAuthResponse(email: "offline-tenants-401@example.com", refreshToken: "refresh-token-new"))
        api.enqueueJSON(path: mePath, statusCode: 200, json: TestDataFactory.makeUser(email: "offline-tenants-401@example.com"))
        api.enqueueJSON(path: tenantsPath, statusCode: 401, json: [:])

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertFalse(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertEqual(api.callCounts[tenantsPath], 1)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertNil(auth.user)
        XCTAssertNil(auth.accessToken)
        XCTAssertNil(auth.refreshToken)
    }

    func test_setCredentials_missingExpClaim_authenticatesWithoutCrashing() async throws {
        let accessToken = try makeAccessToken(email: "missing-exp@example.com", includeExp: false)
        let user = try makeUser(email: "missing-exp@example.com")

        await auth.setCredentials(
            accessToken: accessToken,
            refreshToken: "refresh-token-missing-exp",
            user: user
        )

        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertEqual(auth.accessToken, accessToken)
        XCTAssertEqual(auth.user?.email, "missing-exp@example.com")
    }

    func test_refreshTokenWhenNeeded_missingExpClaim_triggersImmediateRefresh() async throws {
        auth.setAccessToken(try makeAccessToken(email: "stale-missing-exp@example.com", includeExp: false))
        auth.setRefreshToken("refresh-token-existing")
        auth.setUser(nil)
        auth.setIsAuthenticated(false)

        api.refreshResult = .success(try makeAuthResponse(email: "refreshed-missing-exp@example.com", refreshToken: "refresh-token-new"))
        api.enqueueJSON(path: mePath, statusCode: 200, json: TestDataFactory.makeUser(email: "refreshed-missing-exp@example.com"))
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        auth.refreshTokenWhenNeeded()
        await waitForRefreshCall()

        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.user?.email, "refreshed-missing-exp@example.com")
    }

    func test_scheduleTokenRefresh_whileLoginInProgress_retriesAfterLoginCompletes() async throws {
        _ = try seedAuthenticatedSession(
            email: "scheduled-refresh@example.com",
            expirationOffset: -60
        )
        let refreshedAccessToken = try makeAccessToken(email: "scheduled-refresh@example.com")
        api.refreshResult = .success(
            try makeAuthResponse(
                accessToken: refreshedAccessToken,
                refreshToken: "refresh-token-new"
            )
        )

        await MainActor.run {
            auth.isLoginInProgress = true
        }

        auth.scheduleTokenRefresh(offset: 0.05)
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(api.refreshCallCount, 0)
        XCTAssertTrue(auth.hasScheduledTokenRefreshForTesting())

        await MainActor.run {
            auth.isLoginInProgress = false
        }
        await waitForRefreshTokenUpdate(expectedAccessToken: refreshedAccessToken)

        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(auth.accessToken, refreshedAccessToken)
        XCTAssertEqual(auth.refreshToken, "refresh-token-new")
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_jwtTenantChanged_fetchesFreshUser() async throws {
        auth.setUser(try makeUser(email: "cached@example.com", tenantId: "tenant-stale"))
        auth.setIsAuthenticated(true)

        api.refreshResult = .success(
            try makeAuthResponse(
                email: "fresh@example.com",
                refreshToken: "refresh-token-new",
                tenantId: "tenant-fresh"
            )
        )
        api.meWithRefreshResult = .success(
            MeResult(
                user: try makeUser(email: "fresh@example.com", tenantId: "tenant-fresh"),
                refreshedTokens: nil
            )
        )

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.meWithRefreshCallCount, 1)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.user?.email, "fresh@example.com")
        XCTAssertEqual(auth.user?.tenantId, "tenant-fresh")
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_jwtTenantUnchanged_usesCachedUser() async throws {
        let cachedAccessToken = try makeAccessToken(email: "cached@example.com", tenantId: "tenant-123")
        auth.setAccessToken(cachedAccessToken)
        auth.setRefreshToken("refresh-token-existing")
        auth.setUser(try makeUser(email: "cached@example.com", tenantId: "tenant-123"))
        auth.setIsAuthenticated(true)

        let refreshedAccessToken = try makeAccessToken(email: "new-token@example.com", tenantId: "tenant-123")
        api.refreshResult = .success(
            try makeAuthResponse(
                accessToken: refreshedAccessToken,
                refreshToken: "refresh-token-new"
            )
        )
        api.meWithRefreshResult = .failure(ApiError.invalidUrl("me() should not be called when tenant is unchanged"))

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.meWithRefreshCallCount, 0)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.user?.email, "cached@example.com")
        XCTAssertEqual(auth.accessToken, refreshedAccessToken)
        XCTAssertEqual(auth.refreshToken, "refresh-token-new")
    }

    func test_refreshTokenIfNeeded_refreshSucceeds_adoptsRerefreshedTokensFromMe() async throws {
        let initialRefresh = try makeAuthResponse(
            email: "initial@example.com",
            refreshToken: "refresh-token-initial",
            tenantId: "tenant-123"
        )
        let rerefreshedAccessToken = try makeAccessToken(email: "final@example.com", tenantId: "tenant-123")
        let rerefreshedTokens = try makeAuthResponse(
            accessToken: rerefreshedAccessToken,
            refreshToken: "refresh-token-rerefreshed"
        )

        api.refreshResult = .success(initialRefresh)
        api.meWithRefreshResult = .success(
            MeResult(
                user: try makeUser(email: "final@example.com", tenantId: "tenant-123"),
                refreshedTokens: rerefreshedTokens
            )
        )

        let refreshed = await auth.refreshTokenIfNeeded()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(api.refreshCallCount, 1)
        XCTAssertEqual(api.meWithRefreshCallCount, 1)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertEqual(auth.user?.email, "final@example.com")
        XCTAssertEqual(auth.accessToken, rerefreshedAccessToken)
        XCTAssertEqual(auth.refreshToken, "refresh-token-rerefreshed")
    }

    private func makeAuthResponse(
        email: String,
        refreshToken: String,
        tenantId: String = "tenant-123"
    ) throws -> AuthResponse {
        let json = TestDataFactory.makeAuthResponse(
            refreshToken: refreshToken,
            accessToken: try makeAccessToken(email: email, tenantId: tenantId)
        )
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
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
        includeExp: Bool = true,
        tenantId: String = "tenant-123",
        expirationOffset: TimeInterval = 3600
    ) throws -> String {
        var payload: [String: Any] = [
            "sub": UUID().uuidString,
            "email": email,
            "name": "Recovered User",
            "tenantId": tenantId,
            "tenantIds": [tenantId]
        ]
        if includeExp {
            payload["exp"] = Int(Date().timeIntervalSince1970 + expirationOffset)
        }
        return try TestDataFactory.makeJWT(payloadDict: payload)
    }

    @discardableResult
    private func seedAuthenticatedSession(
        email: String,
        tenantId: String = "tenant-123",
        expirationOffset: TimeInterval = -60
    ) throws -> String {
        let cachedAccessToken = try makeAccessToken(
            email: email,
            tenantId: tenantId,
            expirationOffset: expirationOffset
        )
        auth.setAccessToken(cachedAccessToken)
        auth.setRefreshToken("refresh-token-existing")
        auth.setUser(try makeUser(email: email, tenantId: tenantId))
        auth.setIsAuthenticated(true)
        return cachedAccessToken
    }

    @discardableResult
    private func seedStartupRestoreState(
        email: String,
        tenantId: String = "tenant-123",
        expirationOffset: TimeInterval = -60
    ) throws -> String {
        let cachedAccessToken = try makeAccessToken(
            email: email,
            tenantId: tenantId,
            expirationOffset: expirationOffset
        )
        let offlineUser = try makeUser(email: email, tenantId: tenantId)

        auth.setAccessToken(cachedAccessToken)
        auth.setRefreshToken("refresh-token-existing")
        auth.setUser(offlineUser)
        auth.setIsAuthenticated(false)
        auth.setIsOfflineMode(false)
        auth.setInitializing(true)
        auth.setIsLoading(true)

        return cachedAccessToken
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

    private func makeTenantsResponse() -> [String: Any] {
        let tenant = TestDataFactory.makeTenant()
        return [
            "tenants": [tenant],
            "activeTenant": tenant
        ]
    }

    private func waitForRefreshCall() async {
        for _ in 0..<50 {
            if api.refreshCallCount > 0, auth.isAuthenticated {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func waitForRefreshTokenUpdate(expectedAccessToken: String) async {
        for _ in 0..<60 {
            if api.refreshCallCount > 0, auth.accessToken == expectedAccessToken {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func assertOfflineModePersistsBriefly(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(
            auth.isOfflineMode,
            "Offline mode should remain true until a later connectivity update.",
            file: file,
            line: line
        )
    }

    private func makeOfflineConfig(serviceKey: String) -> FronteggPlist {
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
            enableOfflineMode: true,
            useLegacySocialLoginFlow: false,
            enableSessionPerTenant: false,
            networkMonitoringInterval: 1,
            enableSentryLogging: false,
            sentryMaxQueueSize: 10,
            entitlementsEnabled: false
        )
    }
}
