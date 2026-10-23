//
//  GoogleSignInTests.swift
//  FronteggSwiftTests
//
//  FR-25954: native Google sign-in exchanges a Google ID token at the social post-login.
//

import XCTest
import UIKit
import WebKit
@testable import FronteggSwift

private final class RecordingWebView: CustomWebView {
    var onLoad: ((URL?) -> Void)?

    override func load(_ request: URLRequest) -> WKNavigation? {
        onLoad?(request.url)
        return nil
    }
}

private final class FakeGoogleIdTokenProvider: FronteggGoogleIdTokenProvider {
    var result: Result<String, Error>
    private(set) var requestedServerClientIds: [String] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    @MainActor
    func idToken(serverClientId: String, presenting viewController: UIViewController) async throws -> String {
        requestedServerClientIds.append(serverClientId)
        return try result.get()
    }
}

@MainActor
private final class PendingGoogleIdTokenProvider: FronteggGoogleIdTokenProvider {
    private(set) var requestCount = 0
    private var pendingRequest: CheckedContinuation<String, Error>?
    var onRequest: (() -> Void)?

    func idToken(serverClientId: String, presenting viewController: UIViewController) async throws -> String {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequest = continuation
            onRequest?()
        }
    }

    func finish(with result: Result<String, Error>) {
        pendingRequest?.resume(with: result)
        pendingRequest = nil
    }
}

private final class MockGoogleSignInApi: Api {
    private let lock = NSLock()
    private var _googleActive = true
    private var _googleCustomised = true
    private var _postloginIdTokens: [String] = []
    private var _postloginResult: Result<AuthResponse, Error> = .failure(FronteggError.authError(.failedToAuthenticate))
    private var _meUser: User?
    private var _onPostlogin: (() -> Void)?
    private var _configRequestCount = 0

    var googleActive: Bool {
        get { lock.withLock { _googleActive } }
        set { lock.withLock { _googleActive = newValue } }
    }
    var googleCustomised: Bool {
        get { lock.withLock { _googleCustomised } }
        set { lock.withLock { _googleCustomised = newValue } }
    }
    var postloginResult: Result<AuthResponse, Error> {
        get { lock.withLock { _postloginResult } }
        set { lock.withLock { _postloginResult = newValue } }
    }
    var meUser: User? {
        get { lock.withLock { _meUser } }
        set { lock.withLock { _meUser = newValue } }
    }
    var onPostlogin: (() -> Void)? {
        get { lock.withLock { _onPostlogin } }
        set { lock.withLock { _onPostlogin = newValue } }
    }
    var postloginIdTokens: [String] { lock.withLock { _postloginIdTokens } }
    var configRequestCount: Int { lock.withLock { _configRequestCount } }

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    override func getSocialLoginConfig() async throws -> SocialLoginConfig {
        lock.withLock { _configRequestCount += 1 }
        let option = TestDataFactory.makeSocialLoginOption(
            type: "google",
            active: googleActive,
            customised: googleCustomised,
            clientId: "google-web-client"
        )
        let options = try JSONDecoder().decode([SocialLoginOption].self, from: TestDataFactory.jsonData(from: [option]))
        return SocialLoginConfig(options: options)
    }

    override func postloginGoogleNative(idToken: String) async throws -> AuthResponse {
        lock.withLock { _postloginIdTokens.append(idToken) }
        onPostlogin?()
        return try postloginResult.get()
    }

    override func me(accessToken: String, refreshToken: String) async throws -> MeResult {
        MeResult(user: meUser, refreshedTokens: nil)
    }
}

private final class RecordingPostApi: Api {
    private let lock = NSLock()
    private var _path: String?
    private var _body: [String: Any?] = [:]
    private var _silentAuthorizeRefreshTokens: [String] = []
    let responseBody: Data
    let responseHeaders: [String: String]
    let silentAuthorizeBody: Data

    var path: String? { lock.withLock { _path } }
    var body: [String: Any?] { lock.withLock { _body } }
    var silentAuthorizeRefreshTokens: [String] { lock.withLock { _silentAuthorizeRefreshTokens } }

    init(responseBody: Data, responseHeaders: [String: String] = [:], silentAuthorizeBody: Data = Data()) {
        self.responseBody = responseBody
        self.responseHeaders = responseHeaders
        self.silentAuthorizeBody = silentAuthorizeBody
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    override func silentAuthorize(refreshToken: String, timeout: Int = 10) async throws -> (Data, URLResponse) {
        lock.withLock { _silentAuthorizeRefreshTokens.append(refreshToken) }
        let url = URL(string: "https://test.example.com/frontegg/oauth/authorize/silent")!
        return (silentAuthorizeBody, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    override func postRequest(
        path: String,
        body: [String: Any?],
        additionalHeaders: [String: String] = [:],
        followRedirect: Bool = true,
        timeout: Int = Api.DEFAULT_TIMEOUT
    ) async throws -> (Data, URLResponse) {
        lock.withLock {
            _path = path
            _body = body
        }
        let url = URL(string: path.hasPrefix("http") ? path : "https://test.example.com\(path)")!
        return (responseBody, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: responseHeaders)!)
    }
}

@MainActor
final class GoogleSignInTests: XCTestCase {

    private var auth: FronteggAuth!
    private var api: MockGoogleSignInApi!
    private var credentialManager: CredentialManager!

    override func setUp() async throws {
        try await super.setUp()
        NetworkStatusMonitor._testReset()
        let serviceKey = "frontegg-google-sign-in-\(UUID().uuidString)"
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
            embeddedMode: true,
            isLateInit: true,
            entitlementsEnabled: false
        )
        api = MockGoogleSignInApi()
        auth.api = api
        auth.testRootViewControllerOverride = UIViewController()
        auth.setIsLoading(false)
    }

    override func tearDown() async throws {
        FronteggGoogleSignInRuntimeSettings.providerBox.value = nil
        auth.cancelScheduledTokenRefresh()
        auth.testRootViewControllerOverride = nil
        NetworkStatusMonitor._testReset()
        credentialManager.clear()
        PlistHelper.testConfigOverride = nil
        FronteggAuth.testNetworkPathAvailabilityOverride = nil
        auth = nil
        api = nil
        credentialManager = nil
        try await super.tearDown()
    }

    func test_loginWithGoogle_withoutProvider_failsWithConfigurationError() async {
        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.failure?.category, .configuration)
        XCTAssertTrue(api.postloginIdTokens.isEmpty)
    }

    func test_loginWithGoogle_whenGoogleLoginIsInactive_failsWithoutAskingGoogle() async {
        let provider = register(.success("google-id-token"))
        api.googleActive = false

        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.failure?.category, .configuration)
        XCTAssertTrue(provider.requestedServerClientIds.isEmpty)
    }

    func test_loginBoxGoogleSignIn_withFronteggsSharedGoogleApp_usesTheBrowserWithoutAskingGoogle() async {
        let provider = register(.success("google-id-token"))
        api.googleCustomised = false

        await withCheckedContinuation { continuation in
            auth.loginWithGoogle(fallingBackTo: { continuation.resume() }, completion: { _ in })
        }

        XCTAssertTrue(provider.requestedServerClientIds.isEmpty)
        XCTAssertTrue(api.postloginIdTokens.isEmpty)
    }

    func test_loginWithGoogle_onSuccess_exchangesTheIdTokenAndSignsIn() async throws {
        let provider = register(.success("google-id-token"))
        try prepareSuccessfulExchange(email: "google@example.com")

        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.user?.email, "google@example.com")
        XCTAssertEqual(provider.requestedServerClientIds, ["google-web-client"])
        XCTAssertEqual(api.postloginIdTokens, ["google-id-token"])
        XCTAssertFalse(auth.isLoading)
    }

    func test_loginWithGoogle_withTheLoginBoxOpen_completesTheLoginBoxToo() async throws {
        register(.success("google-id-token"))
        try prepareSuccessfulExchange(email: "google@example.com")
        let loginBox = RecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        auth.webview = loginBox
        var loginBoxResult: Result<User, FronteggError>?
        auth.loginCompletion = { loginBoxResult = $0 }
        defer {
            auth.webview = nil
            auth.loginCompletion = nil
        }

        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.user?.email, "google@example.com")
        XCTAssertEqual(loginBoxResult?.user?.email, "google@example.com")
        // FronteggAuth.webview is weak, so the test keeps the login box alive.
        withExtendedLifetime(loginBox) {}
    }

    func test_loginWithGoogle_whenUserCancels_reportsOperationCanceled() async {
        register(.failure(FronteggError.authError(.operationCanceled)))

        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.failure?.category, .cancelled)
        XCTAssertTrue(api.postloginIdTokens.isEmpty)
    }

    func test_loginWithGoogle_aSecondAttempt_reusesTheGoogleConfig() async {
        let provider = register(.failure(FronteggError.authError(.operationCanceled)))

        _ = await complete { self.auth.loginWithGoogle($0) }
        _ = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(provider.requestedServerClientIds, ["google-web-client", "google-web-client"])
        XCTAssertEqual(api.configRequestCount, 1)
    }

    func test_loginWithGoogle_afterGoogleIsTurnedOn_readsTheConfigAgain() async {
        let provider = register(.failure(FronteggError.authError(.operationCanceled)))
        api.googleActive = false
        _ = await complete { self.auth.loginWithGoogle($0) }

        api.googleActive = true
        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.failure?.category, .cancelled)
        XCTAssertEqual(provider.requestedServerClientIds, ["google-web-client"])
        XCTAssertEqual(api.configRequestCount, 2)
    }

    func test_loginWithGoogle_afterTheCachedConfigExpires_readsTheConfigAgain() async {
        register(.failure(FronteggError.authError(.operationCanceled)))
        _ = await complete { self.auth.loginWithGoogle($0) }
        guard let cache = auth.nativeGoogleConfigCache else {
            return XCTFail("A usable Google config should be cached")
        }
        auth.nativeGoogleConfigCache = NativeGoogleConfigCache(option: cache.option, api: api, expiresAt: .distantPast)

        _ = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(api.configRequestCount, 2)
    }

    func test_handleSocialLogin_google_usesTheNativeProvider() async {
        let provider = register(.failure(FronteggError.authError(.operationCanceled)))
        auth.activeEmbeddedOAuthFlow = .socialLogin

        let result = await complete { self.auth.handleSocialLogin(providerString: "google", custom: false, completion: $0) }

        XCTAssertEqual(result.failure?.category, .cancelled)
        XCTAssertEqual(provider.requestedServerClientIds, ["google-web-client"])
        XCTAssertEqual(auth.activeEmbeddedOAuthFlow, .login, "a cancel leaves the login box ready for another flow")
    }

    func test_googleSignUp_usesTheBrowser() {
        register(.success("google-id-token"))

        XCTAssertTrue(auth.shouldSignInWithGoogleNatively(provider: "google", action: .login))
        XCTAssertFalse(auth.shouldSignInWithGoogleNatively(provider: "google", action: .signUp))
    }

    func test_loginWithGoogle_duringStepUp_isCanceledWithoutAskingGoogle() async {
        let provider = register(.success("google-id-token"))
        auth.setIsStepUpAuthorization(true)
        defer { auth.setIsStepUpAuthorization(false) }

        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.failure?.category, .cancelled)
        XCTAssertTrue(provider.requestedServerClientIds.isEmpty)
        XCTAssertTrue(api.postloginIdTokens.isEmpty)
    }

    func test_loginWithGoogle_withALoginOrganization_isCanceledWithoutAskingGoogle() async {
        let provider = register(.success("google-id-token"))
        FronteggApp.shared.loginOrganizationAlias = "acme"
        defer { FronteggApp.shared.loginOrganizationAlias = nil }

        let result = await complete { self.auth.loginWithGoogle($0) }

        XCTAssertEqual(result.failure?.category, .cancelled)
        XCTAssertTrue(provider.requestedServerClientIds.isEmpty)
        XCTAssertTrue(api.postloginIdTokens.isEmpty)
    }

    func test_googleSignInWithALoginOrganization_usesTheBrowser() {
        register(.success("google-id-token"))
        FronteggApp.shared.loginOrganizationAlias = "acme"
        defer { FronteggApp.shared.loginOrganizationAlias = nil }

        XCTAssertFalse(auth.shouldSignInWithGoogleNatively(provider: "google", action: .login))
    }

    func test_googleSignInDuringStepUp_usesTheBrowser() {
        register(.success("google-id-token"))
        auth.setIsStepUpAuthorization(true)
        defer { auth.setIsStepUpAuthorization(false) }

        XCTAssertFalse(auth.shouldSignInWithGoogleNatively(provider: "google", action: .login))
    }

    func test_legacySocialLoginFlow_google_usesTheNativeProvider() async {
        let provider = register(.failure(FronteggError.authError(.operationCanceled)))

        let result = await complete {
            self.auth.directLoginAction(window: nil, type: "social-login", data: "google", _completion: $0)
        }

        XCTAssertEqual(result.failure?.category, .cancelled)
        XCTAssertEqual(provider.requestedServerClientIds, ["google-web-client"])
    }

    func test_nativeGoogleFailure_fallsBackToTheBrowser() async {
        register(.failure(URLError(.notConnectedToInternet)))
        var completed = false

        await withCheckedContinuation { continuation in
            auth.loginWithGoogle(fallingBackTo: { continuation.resume() }, completion: { _ in completed = true })
        }

        XCTAssertFalse(completed, "the browser flow owns the completion after a fallback")
        XCTAssertFalse(auth.isLoading)
        XCTAssertFalse(auth.isNativeGoogleSignInInProgress)
    }

    func test_loginBoxGoogleSignIn_whileOneIsRunning_cancelsASecondTap() async {
        let provider = PendingGoogleIdTokenProvider()
        FronteggGoogleSignInRuntimeSettings.providerBox.value = provider
        var onFirstSignInCompleted: (() -> Void)?
        await withCheckedContinuation { continuation in
            provider.onRequest = { continuation.resume() }
            auth.loginWithGoogle(fallingBackTo: {}, completion: { _ in onFirstSignInCompleted?() })
        }
        provider.onRequest = nil

        let second = await complete { completion in
            self.auth.loginWithGoogle(fallingBackTo: { XCTFail("the second tap must not use the browser") }, completion: completion)
        }
        await withCheckedContinuation { continuation in
            onFirstSignInCompleted = { continuation.resume() }
            provider.finish(with: .failure(FronteggError.authError(.operationCanceled)))
        }

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertFalse(auth.isNativeGoogleSignInInProgress)
        XCTAssertEqual(second.failure?.category, .cancelled)
    }

    func test_loginWithGoogle_whileOneIsRunning_cancelsTheSecondCall() async {
        let provider = PendingGoogleIdTokenProvider()
        FronteggGoogleSignInRuntimeSettings.providerBox.value = provider
        var onFirstSignInCompleted: (() -> Void)?
        await withCheckedContinuation { continuation in
            provider.onRequest = { continuation.resume() }
            auth.loginWithGoogle { _ in onFirstSignInCompleted?() }
        }
        provider.onRequest = nil

        let second = await complete { self.auth.loginWithGoogle($0) }
        await withCheckedContinuation { continuation in
            onFirstSignInCompleted = { continuation.resume() }
            provider.finish(with: .failure(FronteggError.authError(.operationCanceled)))
        }

        XCTAssertEqual(second.failure?.category, .cancelled)
        XCTAssertEqual(provider.requestCount, 1)
    }

    func test_loginBoxGoogleSignIn_whenMfaIsRequired_continuesMfaInTheOpenLoginBox() async {
        register(.success("google-id-token"))
        api.postloginResult = .failure(FronteggError.authError(.mfaRequired(["mfaRequired": true, "mfaToken": "mfa-token"])))
        let webView = RecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        auth.webview = webView
        auth.setWebLoading(false)
        var fellBack = false
        var loadingDuringExchange: (isLoading: Bool, webLoading: Bool)?
        api.onPostlogin = { [auth] in loadingDuringExchange = (auth!.isLoading, auth!.webLoading) }

        let loadedUrl: URL? = await withCheckedContinuation { continuation in
            webView.onLoad = { continuation.resume(returning: $0) }
            auth.loginWithGoogle(fallingBackTo: { fellBack = true }, completion: { _ in })
        }

        XCTAssertNotNil(loadedUrl)
        XCTAssertEqual(auth.activeEmbeddedOAuthFlow, .mfa)
        XCTAssertFalse(fellBack)
        XCTAssertEqual(loadingDuringExchange?.isLoading, false, "isLoading would swap the open login box for a loader")
        XCTAssertEqual(loadingDuringExchange?.webLoading, true)
        auth.webview = nil
    }

    func test_loginWithGoogle_whenMfaIsRequiredWithTheLoginBoxOpen_continuesMfaInIt() async {
        register(.success("google-id-token"))
        api.postloginResult = .failure(FronteggError.authError(.mfaRequired(["mfaRequired": true, "mfaToken": "mfa-token"])))
        let webView = RecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        auth.webview = webView

        let loadedUrl: URL? = await withCheckedContinuation { continuation in
            webView.onLoad = { continuation.resume(returning: $0) }
            auth.loginWithGoogle { _ in }
        }

        XCTAssertNotNil(loadedUrl)
        XCTAssertEqual(auth.activeEmbeddedOAuthFlow, .mfa)
        auth.webview = nil
    }

    func test_loginWithGoogle_whenMfaContinuesInTheLoginBox_completesOnceWhenTheLoginBoxCompletes() async {
        register(.success("google-id-token"))
        api.postloginResult = .failure(FronteggError.authError(.mfaRequired(["mfaRequired": true, "mfaToken": "mfa-token"])))
        let webView = RecordingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        auth.webview = webView
        var loginBoxResults: [Result<User, FronteggError>] = []
        auth.loginCompletion = { loginBoxResults.append($0) }
        var callerResults: [Result<User, FronteggError>] = []
        defer {
            auth.loginCompletion = nil
            auth.webview = nil
        }

        await withCheckedContinuation { continuation in
            webView.onLoad = { _ in continuation.resume() }
            auth.loginWithGoogle { callerResults.append($0) }
        }
        XCTAssertTrue(callerResults.isEmpty, "The caller waits for MFA to end in the login box")

        auth.loginCompletion?(.failure(.authError(.operationCanceled)))
        auth.loginCompletion?(.failure(.authError(.operationCanceled)))

        XCTAssertEqual(loginBoxResults.count, 1)
        XCTAssertEqual(callerResults.count, 1)
        XCTAssertEqual(callerResults.first?.failure?.category, .cancelled)
        withExtendedLifetime(webView) {}
    }

    func test_postloginGoogleNative_sendsTheIdTokenToTheGoogleSsoPostlogin() async throws {
        let recordingApi = RecordingPostApi(
            responseBody: Data("{}".utf8),
            responseHeaders: ["Set-Cookie": "fe_refresh_test-client-id=refresh-cookie; Path=/; HttpOnly"],
            silentAuthorizeBody: try JSONSerialization.data(withJSONObject: TestDataFactory.makeAuthResponse(
                refreshToken: "refresh-1",
                accessToken: "access-1"
            ))
        )

        _ = try await recordingApi.postloginGoogleNative(idToken: "google-id-token")

        let components = try XCTUnwrap(URLComponents(string: try XCTUnwrap(recordingApi.path)))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(components.host, "test.example.com")
        XCTAssertEqual(components.path, "/frontegg/identity/resources/auth/v1/user/sso/google/postlogin")
        XCTAssertEqual(query["id_token"], "google-id-token")
        XCTAssertEqual(query["redirectUri"], "https://test.example.com/oauth/account/social/success")
        XCTAssertTrue(recordingApi.body.isEmpty)
    }

    func test_postloginGoogleNative_exchangesTheRefreshCookieThroughSilentAuthorize() async throws {
        let recordingApi = RecordingPostApi(
            responseBody: Data("{}".utf8),
            responseHeaders: ["Set-Cookie": "fe_refresh_test-client-id=refresh-cookie; Path=/; HttpOnly"],
            silentAuthorizeBody: try JSONSerialization.data(withJSONObject: TestDataFactory.makeAuthResponse(
                refreshToken: "refresh-1",
                accessToken: "access-1"
            ))
        )

        let response = try await recordingApi.postloginGoogleNative(idToken: "google-id-token")

        XCTAssertEqual(recordingApi.silentAuthorizeRefreshTokens, ["refresh-cookie"])
        XCTAssertEqual(response.refresh_token, "refresh-1")
        XCTAssertEqual(response.access_token, "access-1")
    }

    func test_postloginGoogleNative_withoutARefreshCookie_throwsCouldNotExchangeToken() async throws {
        let recordingApi = RecordingPostApi(responseBody: Data("{}".utf8))

        do {
            _ = try await recordingApi.postloginGoogleNative(idToken: "google-id-token")
            XCTFail("expected couldNotExchangeToken")
        } catch FronteggError.authError(.couldNotExchangeToken) {
            XCTAssertTrue(recordingApi.silentAuthorizeRefreshTokens.isEmpty)
        }
    }

    func test_postloginGoogleNative_whenMfaIsRequired_throwsMfaRequiredWithTheRefreshCookie() async throws {
        let recordingApi = RecordingPostApi(
            responseBody: Data(#"{"mfaRequired":true,"mfaToken":"mfa-token"}"#.utf8),
            responseHeaders: ["Set-Cookie": "fe_refresh_test-client-id=mfa-refresh-token; Path=/; HttpOnly"]
        )

        do {
            _ = try await recordingApi.postloginGoogleNative(idToken: "google-id-token")
            XCTFail("expected mfaRequired")
        } catch FronteggError.authError(.mfaRequired(_, let refreshToken)) {
            XCTAssertEqual(refreshToken, "fe_refresh_test-client-id=mfa-refresh-token")
        }
    }

    @discardableResult
    private func register(_ result: Result<String, Error>) -> FakeGoogleIdTokenProvider {
        let provider = FakeGoogleIdTokenProvider(result: result)
        FronteggGoogleSignInRuntimeSettings.providerBox.value = provider
        return provider
    }

    private func prepareSuccessfulExchange(email: String) throws {
        let accessToken = try TestDataFactory.makeJWT(payloadDict: [
            "sub": "user-1",
            "tenantId": "tenant-1",
            "exp": Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        ])
        api.meUser = try JSONDecoder().decode(
            User.self,
            from: JSONSerialization.data(withJSONObject: TestDataFactory.makeUser(email: email))
        )
        api.postloginResult = .success(try JSONDecoder().decode(
            AuthResponse.self,
            from: JSONSerialization.data(withJSONObject: TestDataFactory.makeAuthResponse(
                refreshToken: "refresh-1",
                accessToken: accessToken
            ))
        ))
    }

    private func complete(
        _ start: @escaping (@escaping FronteggAuth.CompletionHandler) -> Void
    ) async -> Result<User, FronteggError> {
        await withCheckedContinuation { continuation in
            start { continuation.resume(returning: $0) }
        }
    }

    private func makeConfig(serviceKey: String) -> FronteggPlist {
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

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }

    var user: Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}
