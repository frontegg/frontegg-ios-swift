import XCTest
@testable import FronteggSwift

private final class FailingApi: Api {
    private let lock = NSLock()
    private var _failure: Error = URLError(.notConnectedToInternet)
    private var _refreshCallCount = 0

    var failure: Error {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }
    var refreshCallCount: Int { lock.withLock { _refreshCallCount } }

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    override func refreshToken(
        refreshToken: String,
        tenantId: String? = nil,
        accessToken: String? = nil
    ) async throws -> AuthResponse {
        lock.withLock { _refreshCallCount += 1 }
        throw failure
    }

    override func switchTenant(tenantId: String, accessToken: String? = nil) async throws {
        throw failure
    }

    override func authroizeWithTokens(refreshToken: String, deviceTokenCookie: String? = nil) async throws -> AuthResponse {
        throw failure
    }

    override func getSocialLoginConfig() async throws -> SocialLoginConfig {
        throw failure
    }

    override func postRequest(
        path: String,
        body: [String: Any?],
        additionalHeaders: [String: String] = [:],
        followRedirect: Bool = true,
        timeout: Int = Api.DEFAULT_TIMEOUT
    ) async throws -> (Data, URLResponse) {
        throw failure
    }
}

final class FronteggErrorPropagationTests: XCTestCase {

    private var auth: FronteggAuth!
    private var api: FailingApi!
    private var credentialManager: CredentialManager!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()
        let serviceKey = "frontegg-error-propagation-\(UUID().uuidString)"
        credentialManager = CredentialManager(serviceKey: serviceKey)
        PlistHelper.testConfigOverride = makeConfig(serviceKey: serviceKey)
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
        api = FailingApi()
        auth.api = api
        auth.setInitializing(false)
        auth.setIsLoading(false)
        auth.setShowLoader(false)
        auth.setWebLoading(false)
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

    func test_getOrRefreshAccessTokenAsync_exhaustedNetworkRetries_throwsNetworkCategory() async {
        auth.setRefreshToken("refresh-token")
        auth.setAccessToken(nil)
        api.failure = URLError(.notConnectedToInternet)

        do {
            _ = try await auth.getOrRefreshAccessTokenAsync()
            XCTFail("expected a thrown error")
        } catch let error as FronteggError {
            XCTAssertEqual(error.category, .network)
            XCTAssertEqual((error.underlyingError as? URLError)?.code, .notConnectedToInternet)
        } catch {
            XCTFail("expected FronteggError, got \(error)")
        }
        XCTAssertEqual(api.refreshCallCount, 5)
    }

    func test_switchTenant_failure_completesOnMainThread() {
        auth.setAccessToken("access-token")
        auth.setRefreshToken("refresh-token")
        api.failure = URLError(.timedOut)

        let done = expectation(description: "switchTenant completion")
        var onMain = false
        var received: FronteggError?
        auth.switchTenant(tenantId: "tenant-2") { result in
            onMain = Thread.isMainThread
            if case .failure(let error) = result { received = error }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertTrue(onMain, "switchTenant completion must be delivered on the main thread")
        XCTAssertEqual(received?.category, .tenantSwitchFailed)
    }

    func test_switchTenantAsync_failure_throwsTenantSwitchFailed() async {
        auth.setAccessToken("access-token")
        auth.setRefreshToken("refresh-token")
        api.failure = URLError(.timedOut)

        do {
            _ = try await auth.switchTenantAsync(tenantId: "tenant-2")
            XCTFail("expected a thrown error")
        } catch let error as FronteggError {
            XCTAssertEqual(error.category, .tenantSwitchFailed)
        } catch {
            XCTFail("expected FronteggError, got \(error)")
        }
    }

    func test_requestAuthorize_networkFailure_keepsNetworkCause() {
        api.failure = URLError(.notConnectedToInternet)

        let done = expectation(description: "requestAuthorize completion")
        var received: FronteggError?
        auth.requestAuthorize(refreshToken: "refresh-token") { result in
            if case .failure(let error) = result { received = error }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(received?.category, .network)
    }

    func test_loginWithApple_configFetchNetworkFailure_keepsCauseAndCompletesOnMain() {
        api.failure = URLError(.cannotFindHost)

        let done = expectation(description: "apple login completion")
        var onMain = false
        var received: FronteggError?
        auth.handleSocialLogin(providerString: "apple", custom: false) { result in
            onMain = Thread.isMainThread
            if case .failure(let error) = result { received = error }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertTrue(onMain, "social login completion must be delivered on the main thread")
        XCTAssertEqual(received?.category, .network)
    }

    func test_exchangeToken_transportFailure_keepsNetworkCause() async {
        api.failure = URLError(.networkConnectionLost)

        let (response, error) = await api.exchangeToken(code: "code", redirectUrl: "app://cb", codeVerifier: "verifier")

        XCTAssertNil(response)
        XCTAssertEqual(error?.category, .network)
        XCTAssertEqual(error?.errorDescription, URLError(.networkConnectionLost).localizedDescription)
    }

    @available(iOS 15.0, *)
    func test_passkeyRegistrationVerify_transportFailure_keepsNetworkCauseOnMain() async {
        let authenticator = PasskeysAuthenticator()
        let done = expectation(description: "registration completion")
        var received: FronteggError?
        var onMain = false
        authenticator.registrationCompletion = { error in
            onMain = Thread.isMainThread
            received = error
            done.fulfill()
        }

        await authenticator.verifyNewDeviceSession(
            publicKey: WebauthnRegistration(
                id: "credential-id",
                response: WebauthnRegistrationResponse(clientDataJSON: "c", attestationObject: "a")
            ),
            baseUrl: "https://example.frontegg.com",
            accessToken: "access-token",
            verifyTransport: { _ in (nil, nil, URLError(.notConnectedToInternet)) }
        )

        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(received?.category, .network)
        XCTAssertTrue(onMain, "passkey registration completion must be delivered on the main thread")
    }

    private func makeConfig(serviceKey: String) -> FronteggPlist {
        FronteggPlist(
            keychainService: serviceKey,
            embeddedMode: false,
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
            enableOfflineMode: false,
            useLegacySocialLoginFlow: false,
            enableSessionPerTenant: false,
            networkMonitoringInterval: 1,
            enableSentryLogging: false,
            sentryMaxQueueSize: 10,
            entitlementsEnabled: false
        )
    }
}
