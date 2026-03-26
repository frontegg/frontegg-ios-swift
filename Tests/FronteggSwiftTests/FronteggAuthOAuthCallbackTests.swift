//
//  FronteggAuthOAuthCallbackTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

private final class MockOAuthCallbackApi: Api {
    struct ExchangeInput {
        let code: String
        let redirectUrl: String
        let codeVerifier: String?
    }

    var exchangeTokenResponse: AuthResponse?
    var exchangeTokenError: FronteggError?
    var meResult: Result<User?, Error> = .success(nil)
    var meRefreshResult: Result<MeResult, Error>?
    var lastExchangeInput: ExchangeInput?
    var meCallCount = 0

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    override func exchangeToken(
        code: String,
        redirectUrl: String,
        codeVerifier: String?
    ) async -> (AuthResponse?, FronteggError?) {
        lastExchangeInput = ExchangeInput(code: code, redirectUrl: redirectUrl, codeVerifier: codeVerifier)
        return (exchangeTokenResponse, exchangeTokenError)
    }

    private func resolveMeResult() throws -> MeResult {
        if let meRefreshResult {
            switch meRefreshResult {
            case .success(let result):
                return result
            case .failure(let error):
                throw error
            }
        }

        switch meResult {
        case .success(let user):
            return MeResult(user: user, refreshedTokens: nil)
        case .failure(let error):
            throw error
        }
    }

    override func me(accessToken: String) async throws -> User? {
        meCallCount += 1
        return try resolveMeResult().user
    }

    override func me(accessToken: String, refreshToken: String) async throws -> MeResult {
        meCallCount += 1
        return try resolveMeResult()
    }
}

final class FronteggAuthOAuthCallbackTests: XCTestCase {

    private var auth: FronteggAuth!
    private var api: MockOAuthCallbackApi!
    private var credentialManager: CredentialManager!
    private var serviceKey: String!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()
        clearOAuthState()

        serviceKey = "frontegg-oauth-tests-\(UUID().uuidString)"
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
        api = MockOAuthCallbackApi()
        auth.api = api
        auth.setIsLoading(false)
        auth.setInitializing(false)
        auth.setShowLoader(false)
        auth.setWebLoading(false)
    }

    override func tearDown() {
        auth.cancelScheduledTokenRefresh()
        NetworkStatusMonitor._testReset()
        credentialManager.clear()
        clearOAuthState()
        PlistHelper.testConfigOverride = nil
        api = nil
        auth = nil
        credentialManager = nil
        serviceKey = nil
        super.tearDown()
    }

    func test_createOauthCallbackHandler_strictMismatchState_returnsInvalidOAuthState() async {
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")

        let result = await executeCallback(
            allowFallback: false,
            url: makeCallbackUrl(code: "code-123", state: "unexpected-state")
        )

        switch result {
        case .success:
            XCTFail("Expected invalid OAuth state failure")
        case .failure(let error):
            guard case .authError(let authError) = error else {
                return XCTFail("Expected auth error, got \(error)")
            }
            guard case .invalidOAuthState = authError else {
                return XCTFail("Expected invalidOAuthState, got \(authError)")
            }
        }

        XCTAssertTrue(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "expected-verifier")
        XCTAssertNil(api.lastExchangeInput)
    }

    func test_createOauthCallbackHandler_compatibilityFallback_usesLastGeneratedVerifierAndCompletesFlow() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(accessToken: accessToken, refreshToken: "refresh-token-1")
        api.meResult = .success(try makeUser())

        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "shared-verifier")

        let result = await executeCallback(
            allowFallback: true,
            url: makeCallbackUrl(code: "code-123", state: "unexpected-state")
        )

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }

        XCTAssertEqual(api.lastExchangeInput?.code, "code-123")
        XCTAssertEqual(api.lastExchangeInput?.codeVerifier, "shared-verifier")
        XCTAssertEqual(api.meCallCount, 1)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertNil(CredentialManager.getCodeVerifier())
    }

    func test_createOauthCallbackHandler_successWithMatchedState_preservesNewerFallbackVerifier() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(accessToken: accessToken, refreshToken: "refresh-token-2")
        api.meResult = .success(try makeUser())

        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "matched-verifier")
        CredentialManager.saveCodeVerifier("newer-verifier")

        let result = await executeCallback(
            allowFallback: false,
            url: makeCallbackUrl(code: "code-234", state: "expected-state")
        )

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }

        XCTAssertEqual(api.lastExchangeInput?.codeVerifier, "matched-verifier")
        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "newer-verifier")
    }

    func test_createOauthCallbackHandler_errorQuery_clearsMatchingPendingStateAndPreservesFallback() async {
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")

        let result = await executeCallback(
            allowFallback: true,
            url: makeCallbackUrl(state: "expected-state", errorMessage: "access_denied")
        )

        switch result {
        case .success:
            XCTFail("Expected oauth error")
        case .failure(let error):
            guard case .authError(let authError) = error else {
                return XCTFail("Expected auth error, got \(error)")
            }
            guard case .oauthError(let message) = authError else {
                return XCTFail("Expected oauthError, got \(authError)")
            }
            XCTAssertEqual(message, "access_denied")
        }

        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "expected-verifier")
        XCTAssertNil(api.lastExchangeInput)
    }

    func test_createOauthCallbackHandler_matchedStateTokenExchangeFailure_clearsOnlyMatchedStateAndPreservesNewerFallback() async {
        CredentialManager.registerPendingOAuth(state: "state-a", codeVerifier: "verifier-a")
        CredentialManager.registerPendingOAuth(state: "state-b", codeVerifier: "verifier-b")
        CredentialManager.saveCodeVerifier("newer-verifier")
        api.exchangeTokenError = FronteggError.authError(.couldNotExchangeToken("exchange failed"))

        let result = await executeCallback(
            allowFallback: false,
            url: makeCallbackUrl(code: "code-345", state: "state-a")
        )

        switch result {
        case .success:
            XCTFail("Expected token exchange failure")
        case .failure:
            break
        }

        XCTAssertNil(CredentialManager.getCodeVerifier(for: "state-a", allowFallback: false))
        XCTAssertEqual(CredentialManager.getCodeVerifier(for: "state-b", allowFallback: false), "verifier-b")
        XCTAssertTrue(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "newer-verifier")
    }

    func test_createOauthCallbackHandler_matchedStateMeFailure_clearsOnlyMatchedStateAndPreservesNewerFallback() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(accessToken: accessToken, refreshToken: "refresh-token-3")
        api.meResult = .failure(ApiError.meEndpointFailed(statusCode: 403, path: "identity/resources/users/v2/me"))

        CredentialManager.registerPendingOAuth(state: "state-a", codeVerifier: "verifier-a")
        CredentialManager.registerPendingOAuth(state: "state-b", codeVerifier: "verifier-b")
        CredentialManager.saveCodeVerifier("newer-verifier")

        let result = await executeCallback(
            allowFallback: false,
            url: makeCallbackUrl(code: "code-456", state: "state-a")
        )

        switch result {
        case .success:
            XCTFail("Expected /me failure")
        case .failure:
            break
        }

        XCTAssertNil(CredentialManager.getCodeVerifier(for: "state-a", allowFallback: false))
        XCTAssertEqual(CredentialManager.getCodeVerifier(for: "state-b", allowFallback: false), "verifier-b")
        XCTAssertTrue(CredentialManager.hasPendingOAuthStates())
        XCTAssertEqual(CredentialManager.getCodeVerifier(), "newer-verifier")
    }

    func test_handleHostedLoginCallback_offlineRecovery_ignoresStaleInMemoryUserWhenUsingJWTFallback() async throws {
        PlistHelper.testConfigOverride = makeOfflineConfig(serviceKey: serviceKey)

        auth.setUser(try makeUser(email: "stale@example.com"))
        let freshAccessToken = try makeAccessToken(email: "fresh@example.com")
        api.exchangeTokenResponse = try makeAuthResponse(accessToken: freshAccessToken, refreshToken: "refresh-token-offline")
        api.meResult = .failure(ApiError.meEndpointFailed(statusCode: 401, path: "identity/resources/users/v2/me"))

        let result = await executeHostedLoginCallback(code: "code-567", codeVerifier: "verifier-567")

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "fresh@example.com")
        case .failure(let error):
            XCTFail("Expected offline recovery success, got \(error)")
        }

        XCTAssertEqual(auth.user?.email, "fresh@example.com")
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertTrue(auth.isOfflineMode)
        await assertOfflineModePersistsBriefly()
        XCTAssertEqual(api.meCallCount, 1)
    }

    func test_handleHostedLoginCallback_completionRunsOnMainThread() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(accessToken: accessToken, refreshToken: "refresh-token-main-thread")
        api.meResult = .success(try makeUser())

        let (result, completionOnMainThread) = await withCheckedContinuation { continuation in
            auth.handleHostedLoginCallback(
                "code-main-thread",
                "verifier-main-thread",
                redirectUri: "test://callback"
            ) { result in
                continuation.resume(returning: (result, Thread.isMainThread))
            }
        }

        XCTAssertTrue(completionOnMainThread)
        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func test_handleHostedLoginCallback_adoptsRerefreshedTokensReturnedFromMe() async throws {
        let exchangedAccessToken = try makeAccessToken(email: "exchange@example.com")
        let rerefreshedAccessToken = try makeAccessToken(email: "corrected@example.com")
        let rerefreshedTokens = try makeAuthResponse(
            accessToken: rerefreshedAccessToken,
            refreshToken: "refresh-token-rerefreshed"
        )

        api.exchangeTokenResponse = try makeAuthResponse(
            accessToken: exchangedAccessToken,
            refreshToken: "refresh-token-exchanged"
        )
        api.meRefreshResult = .success(
            MeResult(
                user: try makeUser(email: "corrected@example.com"),
                refreshedTokens: rerefreshedTokens
            )
        )

        let result = await executeHostedLoginCallback(code: "code-rerefresh", codeVerifier: "verifier-rerefresh")

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "corrected@example.com")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }

        XCTAssertEqual(api.meCallCount, 1)
        XCTAssertEqual(auth.user?.email, "corrected@example.com")
        XCTAssertEqual(auth.accessToken, rerefreshedAccessToken)
        XCTAssertEqual(auth.refreshToken, "refresh-token-rerefreshed")
    }

    func test_reconnectedToInternet_cancelsPendingOfflineDebounceBeforeStateFlips() async {
        auth.setIsOfflineMode(false)

        auth.disconnectedFromInternet()
        auth.reconnectedToInternet()

        try? await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertFalse(auth.isOfflineMode)
    }

    func test_settleUnauthenticatedStartupConnectivity_transientInitialFalse_doesNotLeaveOfflineFlashBehind() async {
        auth.setIsOfflineMode(false)

        let settledOnline = await auth.settleUnauthenticatedStartupConnectivity(
            initialNetworkAvailable: false,
            debounceDelay: 0.01,
            connectivityProbe: { true }
        )

        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertTrue(settledOnline)
        XCTAssertFalse(auth.isOfflineMode)
    }

    func test_settleUnauthenticatedStartupConnectivity_twoTransientFailures_thenRecovery_doesNotFlipOffline() async {
        auth.setIsOfflineMode(false)

        var probeResults = [false, true]

        let settledOnline = await auth.settleUnauthenticatedStartupConnectivity(
            initialNetworkAvailable: false,
            debounceDelay: 0.01,
            recoveryProbeCount: 2,
            connectivityProbe: {
                probeResults.removeFirst()
            }
        )

        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertTrue(settledOnline)
        XCTAssertFalse(auth.isOfflineMode)
    }

    private func executeCallback(
        allowFallback: Bool,
        url: URL?,
        error: Error? = nil
    ) async -> Result<User, FronteggError> {
        await withCheckedContinuation { continuation in
            let handler = auth.createOauthCallbackHandler(
                { result in
                    continuation.resume(returning: result)
                },
                allowLastCodeVerifierFallback: allowFallback,
                redirectUriOverride: "test://callback"
            )
            handler(url, error)
        }
    }

    private func executeHostedLoginCallback(
        code: String,
        codeVerifier: String?
    ) async -> Result<User, FronteggError> {
        await withCheckedContinuation { continuation in
            auth.handleHostedLoginCallback(
                code,
                codeVerifier,
                redirectUri: "test://callback"
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func makeCallbackUrl(
        code: String? = nil,
        state: String? = nil,
        errorMessage: String? = nil
    ) -> URL {
        var components = URLComponents(string: "test://callback")!
        var items: [URLQueryItem] = []
        if let code {
            items.append(URLQueryItem(name: "code", value: code))
        }
        if let state {
            items.append(URLQueryItem(name: "state", value: state))
        }
        if let errorMessage {
            items.append(URLQueryItem(name: "error", value: errorMessage))
        }
        components.queryItems = items
        return components.url!
    }

    private func makeAccessToken(
        email: String = "test@example.com",
        expirationOffset: TimeInterval = 3600
    ) throws -> String {
        try TestDataFactory.makeJWT(payloadDict: [
            "sub": "user-123",
            "email": email,
            "name": "Test User",
            "tenantId": "tenant-123",
            "tenantIds": ["tenant-123"],
            "exp": Int(Date().timeIntervalSince1970 + expirationOffset)
        ])
    }

    private func makeAuthResponse(accessToken: String, refreshToken: String) throws -> AuthResponse {
        let json = TestDataFactory.makeAuthResponse(
            refreshToken: refreshToken,
            accessToken: accessToken
        )
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    private func makeUser(email: String = "test@example.com") throws -> User {
        let data = try JSONSerialization.data(withJSONObject: TestDataFactory.makeUser(email: email))
        return try JSONDecoder().decode(User.self, from: data)
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

    private func clearOAuthState() {
        UserDefaults.standard.removeObject(forKey: KeychainKeys.codeVerifier.rawValue)
        UserDefaults.standard.removeObject(forKey: KeychainKeys.oauthStateVerifiers.rawValue)
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
}
