//
//  FronteggAuthEntitlementsTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

private final class BlockingAuthEntitlementsApi: Api {
    private let stateLock = NSLock()
    private var queuedResponses: [(Data, HTTPURLResponse)] = []
    private var blockedRequestIndexes = Set<Int>()
    private var blockedContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var getRequestCallCount = 0

    var onRequestStarted: ((Int) -> Void)?

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    func enqueueResponse(_ response: (Data, HTTPURLResponse)) {
        withStateLock {
            queuedResponses.append(response)
        }
    }

    func blockRequest(_ index: Int) {
        withStateLock {
            _ = blockedRequestIndexes.insert(index)
        }
    }

    func resumeRequest(_ index: Int) {
        let continuation = withStateLock {
            blockedContinuations.removeValue(forKey: index)
        }
        continuation?.resume()
    }

    func currentCallCount() -> Int {
        withStateLock { getRequestCallCount }
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
        let callIndex: Int
        let shouldBlock: Bool
        let requestStarted: ((Int) -> Void)?

        (callIndex, shouldBlock, requestStarted) = withStateLock {
            getRequestCallCount += 1
            return (
                getRequestCallCount,
                blockedRequestIndexes.contains(getRequestCallCount),
                onRequestStarted
            )
        }

        if shouldBlock {
            await withCheckedContinuation { continuation in
                withStateLock {
                    blockedContinuations[callIndex] = continuation
                }
                requestStarted?(callIndex)
            }
        } else {
            requestStarted?(callIndex)
        }

        let response = withStateLock {
            queuedResponses.removeFirst()
        }
        return (response.0, response.1)
    }
}

final class FronteggAuthEntitlementsTests: XCTestCase {

    private var auth: FronteggAuth!
    private var api: BlockingAuthEntitlementsApi!
    private var credentialManager: CredentialManager!
    private var serviceKey: String!

    override func setUp() {
        super.setUp()
        serviceKey = "frontegg-auth-entitlements-\(UUID().uuidString)"
        credentialManager = CredentialManager(serviceKey: serviceKey)
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
        api = BlockingAuthEntitlementsApi()
        auth.api = api
        auth.entitlements = Entitlements(.init(api: api, enabled: true))
        auth.setAccessToken("test-access-token")
        auth.setIsLoading(false)
        auth.setInitializing(false)
        auth.setShowLoader(false)
    }

    override func tearDown() {
        auth.cancelScheduledTokenRefresh()
        credentialManager.clear()
        api.onRequestStarted = nil
        api = nil
        auth = nil
        credentialManager = nil
        serviceKey = nil
        super.tearDown()
    }

    func test_loadEntitlements_coalescesConcurrentCallersIntoSingleRequest() async throws {
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: ["alpha"]))
        api.blockRequest(1)

        let firstRequestStarted = expectation(description: "first request started")
        let firstCompletion = expectation(description: "first completion")
        let secondCompletion = expectation(description: "second completion")

        api.onRequestStarted = { index in
            if index == 1 {
                firstRequestStarted.fulfill()
            }
        }

        var completionResults: [Bool] = []
        auth.loadEntitlements { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            firstCompletion.fulfill()
        }

        await fulfillment(of: [firstRequestStarted], timeout: 1.0)

        auth.loadEntitlements { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            secondCompletion.fulfill()
        }

        XCTAssertEqual(api.currentCallCount(), 1)

        api.resumeRequest(1)

        await fulfillment(of: [firstCompletion, secondCompletion], timeout: 1.0)

        XCTAssertEqual(api.currentCallCount(), 1)
        XCTAssertEqual(completionResults, [true, true])
        XCTAssertEqual(auth.entitlements.state.featureKeys, Set(["alpha"]))
    }

    func test_loadEntitlements_forceRefreshQueuesSecondPassUntilFirstCompletes() async throws {
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: ["alpha"]))
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: ["beta"]))
        api.blockRequest(1)
        api.blockRequest(2)

        let firstRequestStarted = expectation(description: "first request started")
        let secondRequestStarted = expectation(description: "second request started")
        let firstCompletion = expectation(description: "first completion")
        let secondCompletion = expectation(description: "second completion")

        api.onRequestStarted = { index in
            if index == 1 {
                firstRequestStarted.fulfill()
            } else if index == 2 {
                secondRequestStarted.fulfill()
            }
        }

        var completionResults: [Bool] = []
        auth.loadEntitlements { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            firstCompletion.fulfill()
        }

        await fulfillment(of: [firstRequestStarted], timeout: 1.0)

        auth.loadEntitlements(forceRefresh: true) { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            secondCompletion.fulfill()
        }

        XCTAssertEqual(api.currentCallCount(), 1)

        api.resumeRequest(1)

        await fulfillment(of: [secondRequestStarted], timeout: 1.0)

        XCTAssertTrue(completionResults.isEmpty)
        XCTAssertEqual(api.currentCallCount(), 2)

        api.resumeRequest(2)

        await fulfillment(of: [firstCompletion, secondCompletion], timeout: 1.0)

        XCTAssertEqual(completionResults, [true, true])
        XCTAssertEqual(auth.entitlements.state.featureKeys, Set(["beta"]))
    }

    // MARK: - setCredentials entitlements cache invalidation (FR-24821)

    // The customer-reported bug (FR-24821): after switching tenants on Android, the
    // entitlements cache kept reporting the PREVIOUS tenant's verdict because
    // setCredentialsInternal (which switchTenant routes through) called
    // loadEntitlements(forceRefresh: true) but never invalidated the cache first. The
    // same bug exists on the Swift SDK — see
    // Sources/FronteggSwift/auth/FronteggAuth+CredentialHydration.swift around line
    // 255. The fix adds entitlements.clear() immediately before loadEntitlements.
    //
    // The three tests below mirror the Android coverage in
    // android/src/test/java/com/frontegg/android/services/FronteggAuthServiceTest.kt:
    //   1. Happy path — pre-load tenant A's cache, setCredentials with tenant B,
    //      assert getFeatureEntitlements reflects tenant B. Passes on master too —
    //      loadEntitlements was already wired — kept as a top-level FR-24821 guard.
    //   2. In-flight window (differential) — blocks the reload response so the load
    //      Task stays suspended; asserts hasLoaded == false WHILE the reload is in
    //      flight. Pre-fix: hasLoaded stays true (no clear) until load completes.
    //   3. Failed reload (differential) — reload responds 500. Entitlements.load
    //      returns false on HTTP error without touching _state. Pre-fix: cache keeps
    //      tenant A's {sso} forever. Post-fix: clear() ran first, cache is empty.

    func test_setCredentials_reloadsEntitlementsWithNewTenantView_FR_24821_happyPath() async throws {
        try await seedTenantAEntitlementsCacheWithSSO()

        // Tenant B has no entitlements — the customer's reproduction scenario.
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: []))

        let reloadStarted = expectation(description: "tenant-B entitlements reload started")
        api.onRequestStarted = { index in
            if index == 2 { reloadStarted.fulfill() }
        }

        await auth.setCredentials(
            accessToken: try makeTenantBJWT(),
            refreshToken: "tenant-B-refresh-token",
            user: try makeTenantBUser()
        )

        await fulfillment(of: [reloadStarted], timeout: 2.0)

        // The reload Task is firing; wait for it to settle (the test API responds
        // immediately, so a brief yield is enough — no blocking involved).
        try await waitUntilEntitlementsSettleAfterReload(
            expectingHasLoaded: true,
            expectedFeatureKeys: []
        )

        XCTAssertTrue(auth.entitlements.hasLoaded)
        XCTAssertEqual(auth.entitlements.state.featureKeys, Set<String>())

        // FR-24821 customer assertion: getFeatureEntitlements("sso") must reflect
        // tenant B's reality, not tenant A's pre-switch view.
        let entitlement = auth.getFeatureEntitlements(featureKey: "sso")
        XCTAssertFalse(entitlement.isEntitled, "must not leak tenant A's sso verdict after switching to tenant B")
        XCTAssertEqual(entitlement.justification, "MISSING_FEATURE", "expected MISSING_FEATURE after a successful reload on tenant B (which lacks sso)")
    }

    func test_setCredentials_clearsEntitlementsCacheBeforeReloadStarts_inFlightWindow() async throws {
        // Differential test for the specific behavior this PR adds: entitlements.clear()
        // runs synchronously inside MainActor.run BEFORE loadEntitlements is called.
        // Without that ordering, getFeatureEntitlements() called during the in-flight
        // load window would return the PREVIOUS tenant's verdict — state and hasLoaded
        // are unchanged until performEntitlementsLoad's Task assigns _state.
        try await seedTenantAEntitlementsCacheWithSSO()

        // Block the tenant-B reload so the load Task stays suspended in
        // api.getRequest — this lets us observe the in-flight window directly.
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: []))
        api.blockRequest(2)

        let reloadStarted = expectation(description: "tenant-B reload request started")
        api.onRequestStarted = { index in
            if index == 2 { reloadStarted.fulfill() }
        }

        await auth.setCredentials(
            accessToken: try makeTenantBJWT(),
            refreshToken: "tenant-B-refresh-token",
            user: try makeTenantBUser()
        )

        // Wait for the HTTP request to actually fire — proves loadEntitlements was
        // called by setCredentialsInternal.
        await fulfillment(of: [reloadStarted], timeout: 2.0)

        // CRITICAL: the reload is now in flight (blocked). With the fix, clear() ran
        // synchronously inside MainActor.run before loadEntitlements, so the cache is
        // already empty. Pre-fix: hasLoaded stays true (tenant A's {sso}) until the
        // load completes — a window during which getFeatureEntitlements() leaks the
        // previous tenant's verdict.
        XCTAssertFalse(auth.entitlements.hasLoaded, "cache must be cleared before the reload is triggered (in-flight window)")
        XCTAssertEqual(auth.entitlements.state.featureKeys, Set<String>(), "state must be empty before the reload completes; was \(auth.entitlements.state.featureKeys)")

        // The user-facing surface: getFeatureEntitlements must not leak tenant A's
        // verdict during the in-flight window.
        let entitlement = auth.getFeatureEntitlements(featureKey: "sso")
        XCTAssertFalse(entitlement.isEntitled, "getFeatureEntitlements must not return tenant A's sso verdict while tenant B's reload is in flight")

        // Unblock the request so the background Task can finish and the test tears
        // down cleanly.
        api.resumeRequest(2)
    }

    func test_setCredentials_failedReloadDoesNotLeakPreviousTenantView() async throws {
        try await seedTenantAEntitlementsCacheWithSSO()

        // Tenant B's reload fails — 5xx, network flake, whatever. Entitlements.load
        // returns false on HTTP error WITHOUT touching _state, so any pre-existing
        // cache would survive. Differential check: with the fix, clear() ran first.
        api.enqueueResponse(makeFailedEntitlementsResponse(statusCode: 500))

        let reloadStarted = expectation(description: "tenant-B reload request started")
        api.onRequestStarted = { index in
            if index == 2 { reloadStarted.fulfill() }
        }

        await auth.setCredentials(
            accessToken: try makeTenantBJWT(),
            refreshToken: "tenant-B-refresh-token",
            user: try makeTenantBUser()
        )

        await fulfillment(of: [reloadStarted], timeout: 2.0)

        // Wait for the failed reload to finish so the load Task has fully cycled.
        try await waitUntilEntitlementsSettleAfterReload(
            expectingHasLoaded: false,
            expectedFeatureKeys: []
        )

        // Pre-fix: the cache still holds tenant A's {sso} forever (load failed without
        // touching _state). Post-fix: clear() ran before loadEntitlements.
        XCTAssertFalse(auth.entitlements.hasLoaded, "cache must be cleared on tenant switch even when the reload fails")
        XCTAssertEqual(auth.entitlements.state.featureKeys, Set<String>(), "state must be empty after a failed reload; was \(auth.entitlements.state.featureKeys)")

        // getFeatureEntitlements must not leak tenant A's verdict. Note that the Swift
        // SDK's Entitlements.checkFeature does NOT gate on hasLoaded (unlike Android,
        // which returns ENTITLEMENTS_NOT_LOADED when the cache hasn't been populated).
        // The Swift surface returns MISSING_FEATURE based on the empty state — still a
        // correct, non-leaking verdict for the customer-visible boolean, but the
        // justification is platform-specific. The isEntitled assertion below is the
        // load-bearing differential; the justification assertion documents Swift's
        // actual contract (and would be the place to update if checkFeature is ever
        // changed to mirror Android's "not loaded" reporting).
        let entitlement = auth.getFeatureEntitlements(featureKey: "sso")
        XCTAssertFalse(entitlement.isEntitled, "getFeatureEntitlements must not leak tenant A's sso verdict after a failed reload")
        XCTAssertEqual(entitlement.justification, "MISSING_FEATURE", "Swift's checkFeature returns MISSING_FEATURE on empty state; was \(entitlement.justification ?? "<nil>")")
    }

    // MARK: - Helpers for the FR-24821 tests

    /// Pre-populates the entitlements cache with tenant A's `{sso}` set by enqueuing a
    /// success response and calling `entitlements.load` directly. Asserts the cache
    /// is populated as expected before the test proceeds.
    private func seedTenantAEntitlementsCacheWithSSO() async throws {
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: ["sso"]))
        let loaded = await auth.entitlements.load(accessToken: "tenant-A-access-token")
        XCTAssertTrue(loaded, "Sanity check: tenant A's entitlements must pre-load successfully")
        XCTAssertTrue(auth.entitlements.hasLoaded, "Sanity check: hasLoaded must be true after pre-load")
        XCTAssertTrue(auth.entitlements.state.featureKeys.contains("sso"), "Sanity check: tenant A's cache must hold sso before setCredentials runs")
    }

    /// Builds a syntactically-valid JWT for tenant B with an `exp` claim 1 hour in the
    /// future. setCredentialsInternal decodes the JWT for the refresh-timer offset, so
    /// the token format has to be parseable — see `TestDataFactory.makeJWT`.
    private func makeTenantBJWT() throws -> String {
        let payload: [String: Any] = [
            "sub": "user-1",
            "tenantId": "tenant-B",
            "tenantIds": ["tenant-A", "tenant-B"],
            "email": "test@example.com",
            "exp": Int(Date().timeIntervalSince1970 + 3600)
        ]
        return try TestDataFactory.makeJWT(payloadDict: payload)
    }

    /// Builds a `User` for tenant B via `User.fromJWT` so setCredentialsInternal skips
    /// the `api.me()` path entirely (the `BlockingAuthEntitlementsApi` doesn't
    /// implement `me`, so going through it would explode).
    private func makeTenantBUser() throws -> User {
        let claims: [String: Any] = [
            "sub": "user-1",
            "name": "Test User",
            "email": "test@example.com",
            "tenantId": "tenant-B",
            "tenantIds": ["tenant-A", "tenant-B"]
        ]
        guard let user = User.fromJWT(claims) else {
            throw NSError(domain: "FronteggAuthEntitlementsTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to build tenant-B user via User.fromJWT"])
        }
        return user
    }

    /// 500 response — exercises the path where `api.getRequest` returns an unsuccessful
    /// HTTP response, causing `Entitlements.load` to return `false` without touching
    /// `_state`. This is the exact gap that pinned the cache to the previous tenant
    /// pre-fix.
    private func makeFailedEntitlementsResponse(statusCode: Int) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://test.example.com/frontegg/entitlements/api/v2/user-entitlements")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }

    /// Polls until the entitlements cache reaches the expected state, with a 2-second
    /// safety timeout. The actual settle time is bounded by the test API's
    /// synchronous response, so this typically loops once or twice.
    private func waitUntilEntitlementsSettleAfterReload(
        expectingHasLoaded expectedHasLoaded: Bool,
        expectedFeatureKeys: Set<String>,
        timeout: TimeInterval = 2.0,
        pollInterval: TimeInterval = 0.01
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if auth.entitlements.hasLoaded == expectedHasLoaded
                && auth.entitlements.state.featureKeys == expectedFeatureKeys {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private func makeEntitlementsResponse(featureKeys: [String]) -> (Data, HTTPURLResponse) {
        let features = Dictionary(uniqueKeysWithValues: featureKeys.map { ($0, [String: String]()) })
        let json: [String: Any] = [
            "features": features,
            "permissions": [String: Bool]()
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: URL(string: "https://test.example.com/frontegg/entitlements/api/v2/user-entitlements")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
