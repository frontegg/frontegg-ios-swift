//
//  FronteggAuthOAuthCallbackTests.swift
//  FronteggSwiftTests
//

import XCTest
import AuthenticationServices
@testable import FronteggSwift

private final class MockOAuthCallbackApi: Api {
    struct ExchangeInput {
        let code: String
        let redirectUrl: String
        let codeVerifier: String?
    }

    private let stateLock = NSLock()
    private var blockExchangeToken = false
    private var blockedExchangeTokenContinuation: CheckedContinuation<Void, Never>?

    var exchangeTokenResponse: AuthResponse?
    var exchangeTokenError: FronteggError?
    var meResult: Result<User?, Error> = .success(nil)
    var meRefreshResult: Result<MeResult, Error>?
    var lastExchangeInput: ExchangeInput?
    var meCallCount = 0
    var onExchangeTokenStarted: (() -> Void)?

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    func setExchangeTokenBlocked(_ blocked: Bool) {
        withStateLock {
            blockExchangeToken = blocked
        }
    }

    func resumeExchangeToken() {
        let continuation = withStateLock {
            blockExchangeToken = false
            let continuation = blockedExchangeTokenContinuation
            blockedExchangeTokenContinuation = nil
            return continuation
        }
        continuation?.resume()
    }

    override func exchangeToken(
        code: String,
        redirectUrl: String,
        codeVerifier: String?
    ) async -> (AuthResponse?, FronteggError?) {
        lastExchangeInput = ExchangeInput(code: code, redirectUrl: redirectUrl, codeVerifier: codeVerifier)

        let shouldBlock = withStateLock { blockExchangeToken }
        if shouldBlock {
            await withCheckedContinuation { continuation in
                withStateLock {
                    blockedExchangeTokenContinuation = continuation
                }
                onExchangeTokenStarted?()
            }
        } else {
            onExchangeTokenStarted?()
        }

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

private final class SpyOAuthErrorDelegate: FronteggOAuthErrorDelegate {
    private(set) var contexts: [FronteggOAuthErrorContext] = []

    func fronteggSDK(didReceiveOAuthError context: FronteggOAuthErrorContext) {
        contexts.append(context)
    }
}

private final class StartupProbeSequence {
    private var results: [Bool]
    private(set) var callCount = 0

    init(_ results: [Bool]) {
        self.results = results
    }

    func next() -> Bool {
        callCount += 1
        return results.removeFirst()
    }
}

private final class BooleanBox {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
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
        FronteggOAuthErrorRuntimeSettings.presentation = .toast
        FronteggOAuthErrorRuntimeSettings.delegateBox.value = nil
    }

    override func tearDown() {
        auth.cancelScheduledTokenRefresh()
        NetworkStatusMonitor._testReset()
        credentialManager.clear()
        clearOAuthState()
        PlistHelper.testConfigOverride = nil
        FronteggOAuthErrorRuntimeSettings.presentation = .toast
        FronteggOAuthErrorRuntimeSettings.delegateBox.value = nil
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

    func test_createOauthCallbackHandler_errorQuery_reportsDecodedErrorDescriptionToDelegate() async {
        let delegate = SpyOAuthErrorDelegate()
        FronteggOAuthErrorRuntimeSettings.presentation = .delegate
        FronteggOAuthErrorRuntimeSettings.delegateBox.value = delegate
        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")

        let result = await executeCallback(
            allowFallback: true,
            url: makeCallbackUrl(
                state: "expected-state",
                errorMessage: "ER-05001",
                errorDescription: "JWT+token+size+exceeded"
            )
        )

        await waitForOAuthErrorDispatch()

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
            XCTAssertEqual(message, "ER-05001: JWT token size exceeded")
        }

        XCTAssertEqual(delegate.contexts.count, 1)
        XCTAssertEqual(delegate.contexts.first?.displayMessage, "ER-05001: JWT token size exceeded")
        XCTAssertEqual(delegate.contexts.first?.errorCode, "ER-05001")
        XCTAssertEqual(delegate.contexts.first?.errorDescription, "JWT token size exceeded")
        XCTAssertEqual(delegate.contexts.first?.flow, .login)
        XCTAssertEqual(delegate.contexts.first?.embeddedMode, false)
    }

    func test_handleSocialLoginCallback_errorCallback_returnsNil() {
        let previousBaseUrl = auth.baseUrl
        auth.baseUrl = "https://test.example.com"
        defer {
            auth.baseUrl = previousBaseUrl
        }

        let callbackUrl = makeGeneratedRedirectCallbackUrl(
            state: "expected-state",
            errorMessage: "ER-05001",
            errorDescription: "JWT+token+size+exceeded"
        )

        XCTAssertNil(auth.handleSocialLoginCallback(callbackUrl))
    }

    func test_handleSocialLoginCallback_generatedRedirectAliasWithBasePath_preservesActualCallbackAlias() throws {
        let bundleIdentifier = currentTestBundleIdentifier()
        let previousBaseUrl = auth.baseUrl
        auth.baseUrl = "https://test.example.com/fe-auth"
        defer {
            auth.baseUrl = previousBaseUrl
        }

        let rawSocialState = try makeRawSocialState(
            provider: "google",
            appId: "app-1",
            action: "login"
        )
        let callbackUrl = makeGeneratedRedirectCallbackUrl(
            bundleIdentifier: bundleIdentifier,
            path: "/ios/oauth/callback",
            code: "code-123",
            state: rawSocialState
        )

        let finalUrl = auth.handleSocialLoginCallback(callbackUrl)
        let queryItems = finalUrl.flatMap { getQueryItems($0.absoluteString) }

        XCTAssertEqual(finalUrl?.path, "/fe-auth/oauth/account/social/success")
        XCTAssertEqual(
            queryItems?["redirectUri"],
            "\(bundleIdentifier)://test.example.com/ios/oauth/callback"
        )
        let returnedState = queryItems?["state"]?.data(using: .utf8)
        let returnedStateObject = returnedState.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: String]
        }
        XCTAssertEqual(returnedStateObject?["provider"], "google")
        XCTAssertEqual(returnedStateObject?["appId"], "app-1")
        XCTAssertEqual(returnedStateObject?["action"], "login")
    }

    func test_handleSocialLoginCallback_runtimeBundleIdentifierOverride_preservesActualCallbackAlias() throws {
        let app = FronteggApp.shared
        let previousBundleIdentifier = app.bundleIdentifier
        let previousBaseUrl = auth.baseUrl
        app.bundleIdentifier = "com.override.bundle"
        auth.baseUrl = "https://test.example.com/fe-auth"
        defer {
            app.bundleIdentifier = previousBundleIdentifier
            auth.baseUrl = previousBaseUrl
        }

        let rawSocialState = try makeRawSocialState(
            provider: "google",
            appId: "app-override",
            action: "login"
        )
        let callbackUrl = makeGeneratedRedirectCallbackUrl(
            bundleIdentifier: "com.override.bundle",
            path: "/ios/oauth/callback",
            code: "code-override",
            state: rawSocialState
        )

        let finalUrl = auth.handleSocialLoginCallback(callbackUrl)
        let queryItems = finalUrl.flatMap { getQueryItems($0.absoluteString) }

        XCTAssertEqual(finalUrl?.path, "/fe-auth/oauth/account/social/success")
        XCTAssertEqual(
            queryItems?["redirectUri"],
            "com.override.bundle://test.example.com/ios/oauth/callback"
        )
    }

    func test_handleSocialLoginOAuthCallback_errorCompletesFailure() async {
        let result = await executeSocialLoginOAuthCallback(
            url: nil,
            error: URLError(.cannotConnectToHost)
        )

        switch result {
        case .success:
            XCTFail("Expected social login callback failure")
        case .failure(let error):
            guard case .authError(let authError) = error else {
                return XCTFail("Expected auth error, got \(error)")
            }
            guard case .other(let underlyingError) = authError else {
                return XCTFail("Expected wrapped underlying error, got \(authError)")
            }
            XCTAssertEqual((underlyingError as NSError).domain, NSURLErrorDomain)
            XCTAssertEqual((underlyingError as NSError).code, URLError.cannotConnectToHost.rawValue)
        }
    }

    func test_handleSocialLoginOAuthCallback_queryErrorCompletesFailure() async {
        let result = await executeSocialLoginOAuthCallback(
            url: makeCallbackUrl(
                state: "social-state",
                errorMessage: "access_denied",
                errorDescription: "User+canceled"
            )
        )

        switch result {
        case .success:
            XCTFail("Expected social login callback failure")
        case .failure(let error):
            guard case .authError(let authError) = error else {
                return XCTFail("Expected auth error, got \(error)")
            }
            guard case .oauthError(let message) = authError else {
                return XCTFail("Expected oauthError, got \(authError)")
            }
            XCTAssertEqual(message, "access_denied: User canceled")
        }
    }

    func test_handleSocialLogin_invalidProviderCompletesFailureOnMainThreadAndResetsFlow() async {
        await MainActor.run {
            auth.activeEmbeddedOAuthFlow = .socialLogin
        }

        let (result, completionOnMainThread) = await withCheckedContinuation { continuation in
            auth.handleSocialLogin(providerString: "not-a-provider", custom: false) { result in
                continuation.resume(returning: (result, Thread.isMainThread))
            }
        }

        XCTAssertTrue(completionOnMainThread)
        let finalFlowIsLogin = await MainActor.run { auth.activeEmbeddedOAuthFlow == .login }
        XCTAssertTrue(finalFlowIsLogin)

        switch result {
        case .success:
            XCTFail("Expected social login to fail for an unknown provider")
        case .failure(let error):
            guard case .authError(let authError) = error else {
                return XCTFail("Expected auth error, got \(error)")
            }
            guard case .unknown = authError else {
                return XCTFail("Expected unknown auth error, got \(authError)")
            }
        }
    }

    func test_handleSocialLogin_newAttemptClearsPendingSocialVerifierState() async throws {
        let rawSocialState = try makeRawSocialState(
            provider: "google",
            appId: "app-pending-cleanup",
            action: "login"
        )
        SocialLoginUrlGenerator.shared.storePendingSocialCodeVerifier(
            "stale-social-verifier",
            for: rawSocialState
        )

        let result = await withCheckedContinuation { continuation in
            auth.handleSocialLogin(providerString: "not-a-provider", custom: false) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            XCTFail("Expected social login to fail for an unknown provider")
        case .failure:
            break
        }

        XCTAssertNil(SocialLoginUrlGenerator.shared.pendingSocialCodeVerifier(for: rawSocialState))
    }

    func test_handleOpenUrl_generatedRedirectError_reportsDecodedErrorDescriptionToDelegate() async {
        let delegate = SpyOAuthErrorDelegate()
        FronteggOAuthErrorRuntimeSettings.presentation = .delegate
        FronteggOAuthErrorRuntimeSettings.delegateBox.value = delegate

#if DEBUG
        PlistHelper.testConfigOverride = makeSharedAppConfig()
#endif
        let app = FronteggApp.shared
        let previousBaseUrl = app.baseUrl
        let previousBundleIdentifier = app.bundleIdentifier
        let previousEmbeddedMode = app.embeddedMode
        app.baseUrl = "https://test.example.com"
        app.bundleIdentifier = "com.frontegg.demo"
        app.embeddedMode = auth.embeddedMode
        defer {
            app.baseUrl = previousBaseUrl
            app.bundleIdentifier = previousBundleIdentifier
            app.embeddedMode = previousEmbeddedMode
        }

        auth.activeEmbeddedOAuthFlow = .socialLogin
        let callbackUrl = makeGeneratedRedirectCallbackUrl(
            state: "expected-state",
            errorMessage: "ER-05001",
            errorDescription: "JWT+token+size+exceeded"
        )

        XCTAssertTrue(auth.handleOpenUrl(callbackUrl))
        await waitForOAuthErrorDispatch()

        XCTAssertEqual(delegate.contexts.count, 1)
        XCTAssertEqual(delegate.contexts.first?.displayMessage, "ER-05001: JWT token size exceeded")
        XCTAssertEqual(delegate.contexts.first?.errorCode, "ER-05001")
        XCTAssertEqual(delegate.contexts.first?.errorDescription, "JWT token size exceeded")
        XCTAssertEqual(delegate.contexts.first?.flow, .socialLogin)
        XCTAssertEqual(delegate.contexts.first?.embeddedMode, false)
    }

    func test_createOauthCallbackHandler_generatedRedirectAliasWithBasePath_usesActualCallbackAliasForExchange() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(
            accessToken: accessToken,
            refreshToken: "refresh-token-base-path"
        )
        api.meResult = .success(try makeUser())

        let bundleIdentifier = currentTestBundleIdentifier()
        let previousAuthBaseUrl = auth.baseUrl
        auth.baseUrl = "https://test.example.com/fe-auth"
        defer {
            auth.baseUrl = previousAuthBaseUrl
        }

        CredentialManager.registerPendingOAuth(state: "expected-state", codeVerifier: "expected-verifier")

        let result = await executeCallback(
            allowFallback: false,
            url: makeGeneratedRedirectCallbackUrl(
                bundleIdentifier: bundleIdentifier,
                path: "/ios/oauth/callback",
                code: "code-123",
                state: "expected-state"
            )
        )

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }

        XCTAssertEqual(
            api.lastExchangeInput?.redirectUrl,
            "\(bundleIdentifier)://test.example.com/ios/oauth/callback"
        )
    }

    func test_createOauthCallbackHandler_runtimeBundleIdentifierOverride_usesOverrideForExchange() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(
            accessToken: accessToken,
            refreshToken: "refresh-token-runtime-override"
        )
        api.meResult = .success(try makeUser())

        let app = FronteggApp.shared
        let previousBundleIdentifier = app.bundleIdentifier
        let previousAuthBaseUrl = auth.baseUrl
        app.bundleIdentifier = "com.override.bundle"
        auth.baseUrl = "https://test.example.com/fe-auth"
        defer {
            app.bundleIdentifier = previousBundleIdentifier
            auth.baseUrl = previousAuthBaseUrl
        }

        CredentialManager.registerPendingOAuth(state: "override-state", codeVerifier: "override-verifier")

        let result = await executeCallback(
            allowFallback: false,
            url: makeGeneratedRedirectCallbackUrl(
                bundleIdentifier: "com.override.bundle",
                path: "/ios/oauth/callback",
                code: "code-override",
                state: "override-state"
            )
        )

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }

        XCTAssertEqual(
            api.lastExchangeInput?.redirectUrl,
            "com.override.bundle://test.example.com/ios/oauth/callback"
        )
    }

    func test_getQueryItems_plusOnlyOAuthErrorValues_doNotProduceFailureDetails() {
        let callbackUrl = makeGeneratedRedirectCallbackUrl(
            errorMessage: "+++",
            errorDescription: "+++"
        )

        let queryItems = getQueryItems(callbackUrl.absoluteString)

        XCTAssertEqual(queryItems?["error"], "+++")
        XCTAssertEqual(queryItems?["error_description"], "+++")
        XCTAssertNil(auth.oauthFailureDetails(from: queryItems ?? [:]))
    }

    func test_createOauthCallbackHandler_transportError_clearsOnlyProvidedPendingState() async {
        CredentialManager.registerPendingOAuth(state: "embedded-state", codeVerifier: "embedded-verifier")
        CredentialManager.registerPendingOAuth(state: "popup-state", codeVerifier: "popup-verifier")

        let result = await executeCallback(
            allowFallback: true,
            url: nil,
            error: NSError(domain: "WebAuthenticator", code: 1),
            pendingOAuthState: "popup-state"
        )

        switch result {
        case .success:
            XCTFail("Expected transport error failure")
        case .failure:
            break
        }

        XCTAssertEqual(
            CredentialManager.getCodeVerifier(for: "embedded-state", allowFallback: false),
            "embedded-verifier"
        )
        XCTAssertNil(CredentialManager.getCodeVerifier(for: "popup-state", allowFallback: false))
        XCTAssertTrue(CredentialManager.hasPendingOAuthStates())
        XCTAssertNil(api.lastExchangeInput)
    }

    func test_createOauthCallbackHandler_cancelledTransportError_doesNotReportOAuthFailure() async {
        let delegate = SpyOAuthErrorDelegate()
        FronteggOAuthErrorRuntimeSettings.presentation = .delegate
        FronteggOAuthErrorRuntimeSettings.delegateBox.value = delegate
        CredentialManager.registerPendingOAuth(state: "popup-state", codeVerifier: "popup-verifier")

        let result = await executeCallback(
            allowFallback: true,
            url: nil,
            error: NSError(
                domain: ASWebAuthenticationSessionError.errorDomain,
                code: ASWebAuthenticationSessionError.canceledLogin.rawValue
            ),
            pendingOAuthState: "popup-state"
        )

        await waitForOAuthErrorDispatch()

        switch result {
        case .success:
            XCTFail("Expected cancel failure")
        case .failure:
            break
        }

        XCTAssertTrue(delegate.contexts.isEmpty)
    }

    func test_createOauthCallbackHandler_transportError_preservesHostedStateForFollowupSuccess() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(accessToken: accessToken, refreshToken: "refresh-token-cancel")
        api.meResult = .success(try makeUser())

        CredentialManager.registerPendingOAuth(state: "embedded-state", codeVerifier: "embedded-verifier")
        CredentialManager.registerPendingOAuth(state: "popup-state", codeVerifier: "popup-verifier")

        _ = await executeCallback(
            allowFallback: true,
            url: nil,
            error: NSError(domain: "WebAuthenticator", code: 1),
            pendingOAuthState: "popup-state"
        )

        let result = await executeCallback(
            allowFallback: false,
            url: makeCallbackUrl(code: "code-embedded", state: "embedded-state"),
            pendingOAuthState: "embedded-state"
        )

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected hosted callback success after popup cancel, got \(error)")
        }

        XCTAssertEqual(api.lastExchangeInput?.code, "code-embedded")
        XCTAssertEqual(api.lastExchangeInput?.codeVerifier, "embedded-verifier")
        XCTAssertEqual(api.meCallCount, 1)
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(CredentialManager.hasPendingOAuthStates())
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

    func test_createOauthCallbackHandler_tokenExchangeFailure_reportsSingleDelegateEvent() async {
        let delegate = SpyOAuthErrorDelegate()
        FronteggOAuthErrorRuntimeSettings.presentation = .delegate
        FronteggOAuthErrorRuntimeSettings.delegateBox.value = delegate
        CredentialManager.registerPendingOAuth(state: "state-a", codeVerifier: "verifier-a")
        api.exchangeTokenError = FronteggError.authError(.couldNotExchangeToken("exchange failed"))

        let result = await executeCallback(
            allowFallback: false,
            url: makeCallbackUrl(code: "code-345", state: "state-a")
        )

        await waitForOAuthErrorDispatch()

        switch result {
        case .success:
            XCTFail("Expected token exchange failure")
        case .failure:
            break
        }

        XCTAssertEqual(delegate.contexts.count, 1)
        XCTAssertEqual(delegate.contexts.first?.displayMessage, "exchange failed")
        XCTAssertEqual(delegate.contexts.first?.flow, .login)
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

    func test_handleHostedLoginCallback_connectivityRecovery_ignoresStaleInMemoryUserWhenUsingJWTFallback() async throws {
        PlistHelper.testConfigOverride = makeOfflineConfig(serviceKey: serviceKey)

        auth.setUser(try makeUser(email: "stale@example.com"))
        let freshAccessToken = try makeAccessToken(email: "fresh@example.com")
        api.exchangeTokenResponse = try makeAuthResponse(accessToken: freshAccessToken, refreshToken: "refresh-token-offline")
        api.meResult = .failure(URLError(.timedOut))

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
        XCTAssertFalse(auth.hasScheduledTokenRefreshForTesting())
        await assertOfflineModePersistsBriefly()
        XCTAssertEqual(api.meCallCount, 1)
    }

    func test_handleHostedLoginCallback_nonConnectivityUserLoadFailure_doesNotEnterOfflineRecovery() async throws {
        PlistHelper.testConfigOverride = makeOfflineConfig(serviceKey: serviceKey)

        let accessToken = try makeAccessToken(email: "fresh@example.com")
        api.exchangeTokenResponse = try makeAuthResponse(
            accessToken: accessToken,
            refreshToken: "refresh-token-non-connectivity"
        )
        api.meResult = .failure(
            ApiError.meEndpointFailed(statusCode: 401, path: "identity/resources/users/v2/me")
        )

        let result = await executeHostedLoginCallback(
            code: "code-non-connectivity",
            codeVerifier: "verifier-non-connectivity"
        )

        switch result {
        case .success:
            XCTFail("Expected hosted login callback to fail for non-connectivity /me error")
        case .failure:
            break
        }

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertNil(auth.user)
        XCTAssertFalse(auth.hasScheduledTokenRefreshForTesting())
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

    func test_handleHostedLoginCallback_socialLoginSuccess_clearsPendingSocialVerifierState() async throws {
        let rawSocialState = try makeRawSocialState(
            provider: "google",
            appId: "app-1",
            action: "login"
        )
        let canonicalSocialState = SocialLoginUrlGenerator.canonicalizeSocialState(rawSocialState)
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(
            accessToken: accessToken,
            refreshToken: "refresh-token-social-success"
        )
        api.meResult = .success(try makeUser())
        SocialLoginUrlGenerator.shared.storePendingSocialCodeVerifier(
            "pending-social-verifier",
            for: rawSocialState
        )

        let result = await withCheckedContinuation { continuation in
            auth.handleHostedLoginCallback(
                "code-social-success",
                "verifier-social-success",
                oauthState: canonicalSocialState,
                redirectUri: "test://callback",
                flow: .socialLogin,
                completePendingFlowOnSuccess: false
            ) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected social login success, got \(error)")
        }

        XCTAssertNil(SocialLoginUrlGenerator.shared.pendingSocialCodeVerifier(for: rawSocialState))
        XCTAssertNil(SocialLoginUrlGenerator.shared.pendingSocialCodeVerifier(for: canonicalSocialState))
    }

    func test_handleSocialLoginOAuthCallback_failure_clearsPendingSocialVerifierState() async throws {
        let rawSocialState = try SocialLoginUrlGenerator.createState(
            provider: .google,
            appId: "app-2",
            action: .login
        )
        SocialLoginUrlGenerator.shared.storePendingSocialCodeVerifier(
            "pending-social-verifier",
            for: rawSocialState
        )

        let result = await executeSocialLoginOAuthCallback(
            url: nil,
            error: URLError(.cannotConnectToHost)
        )

        switch result {
        case .success:
            XCTFail("Expected social login callback failure")
        case .failure:
            break
        }

        XCTAssertNil(SocialLoginUrlGenerator.shared.pendingSocialCodeVerifier(for: rawSocialState))
    }

    func test_logout_clearsLoginInProgressWhileHostedLoginCallbackIsInFlight() async {
        api.exchangeTokenError = FronteggError.authError(.failedToAuthenticate)
        api.setExchangeTokenBlocked(true)

        let exchangeStarted = expectation(description: "hosted login exchange started")
        api.onExchangeTokenStarted = {
            exchangeStarted.fulfill()
        }

        let callbackTask = Task {
            await self.executeHostedLoginCallback(code: "code-logout", codeVerifier: "verifier-logout")
        }

        await fulfillment(of: [exchangeStarted], timeout: 1.0)

        let loginInProgressBeforeLogout = await auth.isLoginInProgressForTesting()
        XCTAssertTrue(loginInProgressBeforeLogout)

        let logoutResult = await withCheckedContinuation { continuation in
            auth.logout(clearCookie: false) { result in
                continuation.resume(returning: result)
            }
        }

        switch logoutResult {
        case .success(let didLogout):
            XCTAssertTrue(didLogout)
        case .failure(let error):
            XCTFail("Expected logout to succeed, got \(error)")
        }

        let loginInProgressAfterLogout = await auth.isLoginInProgressForTesting()
        XCTAssertFalse(loginInProgressAfterLogout)

        api.resumeExchangeToken()

        switch await callbackTask.value {
        case .success:
            XCTFail("Expected hosted login callback to fail after the blocked exchange resumes")
        case .failure:
            break
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

    func test_handleHostedLoginCallback_onlineSuccess_cancelsPendingOfflineDebounce() async throws {
        let accessToken = try makeAccessToken()
        api.exchangeTokenResponse = try makeAuthResponse(
            accessToken: accessToken,
            refreshToken: "refresh-token-online-success"
        )
        api.meResult = .success(try makeUser())

        auth.setIsOfflineMode(false)
        auth.disconnectedFromInternet()

        let result = await executeHostedLoginCallback(
            code: "code-online-success",
            codeVerifier: "verifier-online-success"
        )

        switch result {
        case .success(let user):
            XCTAssertEqual(user.email, "test@example.com")
        case .failure(let error):
            XCTFail("Expected hosted login callback success, got \(error)")
        }

        try? await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
    }

    func test_logout_whileOffline_keepsUnauthenticatedOfflineModeEnabled() async throws {
        PlistHelper.testConfigOverride = makeOfflineConfig(serviceKey: serviceKey)
        NetworkStatusMonitor._testSetReachabilityOverride(false)

        auth.setAccessToken("access-token")
        auth.setRefreshToken("refresh-token")
        auth.setUser(try makeUser())
        auth.setIsAuthenticated(true)
        auth.setIsOfflineMode(true)

        let result = await withCheckedContinuation { continuation in
            auth.logout(clearCookie: false) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let didLogout):
            XCTAssertTrue(didLogout)
        case .failure(let error):
            XCTFail("Expected logout success, got \(error)")
        }

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.accessToken)
        XCTAssertNil(auth.refreshToken)
        XCTAssertTrue(auth.isOfflineMode)
        XCTAssertTrue(NetworkStatusMonitor._testSnapshot().monitoringActive)
    }

    func test_logout_online_ignoresPendingOfflineDebounceFromPreviousMonitoring() async throws {
        PlistHelper.testConfigOverride = makeOfflineConfig(serviceKey: serviceKey)
        NetworkStatusMonitor._testSetReachabilityOverride(true)

        auth.setAccessToken("access-token")
        auth.setRefreshToken("refresh-token")
        auth.setUser(try makeUser())
        auth.setIsAuthenticated(true)
        auth.setIsOfflineMode(false)
        auth.disconnectedFromInternet()

        let result = await withCheckedContinuation { continuation in
            auth.logout(clearCookie: false) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let didLogout):
            XCTAssertTrue(didLogout)
        case .failure(let error):
            XCTFail("Expected logout success, got \(error)")
        }

        try? await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertTrue(NetworkStatusMonitor._testSnapshot().monitoringActive)
    }

    func test_recheckConnection_unauthenticatedOffline_returnsToLoginStateWhenNetworkIsBack() async {
        NetworkStatusMonitor._testSetReachabilityOverride(true)

        auth.setIsAuthenticated(false)
        auth.setUser(nil)
        auth.setAccessToken(nil)
        auth.setRefreshToken(nil)
        auth.setIsOfflineMode(true)
        auth.setIsLoading(false)
        auth.setInitializing(false)
        auth.ensureOfflineMonitoringActive()

        auth.recheckConnection()
        for _ in 0..<20 where auth.isOfflineMode {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let snapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.user)
        XCTAssertFalse(snapshot.monitoringActive)
        XCTAssertEqual(snapshot.handlerCount, 0)
    }

    func test_recheckConnection_unauthenticatedOffline_ignoresStaleOfflineMonitorCacheWhenProbeSucceeds() async {
        NetworkStatusMonitor._testSetReachabilityOverride(true)

        auth.setIsAuthenticated(false)
        auth.setUser(nil)
        auth.setAccessToken(nil)
        auth.setRefreshToken(nil)
        auth.setIsOfflineMode(true)
        auth.setIsLoading(false)
        auth.setInitializing(false)
        auth.ensureOfflineMonitoringActive()

        // Simulate a stale cached offline result from background monitoring without
        // letting a live path monitor race the manual Retry flow.
        NetworkStatusMonitor.stopBackgroundMonitoring()
        NetworkStatusMonitor._testSetState(
            cachedReachable: false,
            hasCachedReachable: true,
            monitoringActive: true,
            hasInitialCheckFired: true
        )

        let initialSnapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertTrue(initialSnapshot.monitoringActive)
        XCTAssertEqual(initialSnapshot.handlerCount, 1)
        XCTAssertFalse(initialSnapshot.cachedReachable)
        XCTAssertTrue(initialSnapshot.hasCachedReachable)

        auth.recheckConnection()
        for _ in 0..<40 where auth.isOfflineMode {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let snapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.user)
        XCTAssertFalse(snapshot.monitoringActive)
        XCTAssertEqual(snapshot.handlerCount, 0)
    }

    func test_ensureOfflineMonitoringActive_defaultsToSuppressingInitialEmission() {
        auth.ensureOfflineMonitoringActive()

        let snapshot = NetworkStatusMonitor._testSnapshot()

        XCTAssertTrue(snapshot.monitoringActive)
        XCTAssertFalse(snapshot.emitInitialState)
        XCTAssertEqual(snapshot.handlerCount, 1)
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

    func test_completeUnauthenticatedStartupInitialization_transientFailures_keepLoaderUntilRecovery() async {
        auth.setIsLoading(true)
        auth.setInitializing(true)
        auth.setIsOfflineMode(false)

        let probeSequence = StartupProbeSequence([false, false, true])

        let task = Task {
            await auth.completeUnauthenticatedStartupInitialization(
                monitoringInterval: 1,
                startupProbeTimeout: 0.01,
                offlineCommitWindow: 1.0,
                probeDelay: 0.1,
                connectivityProbe: { _ in
                    probeSequence.next()
                },
                postConnectivityServices: {}
            )
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        let midRaceSnapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertFalse(midRaceSnapshot.monitoringActive)
        XCTAssertTrue(auth.isLoading)
        XCTAssertTrue(auth.initializing)
        XCTAssertFalse(auth.isOfflineMode)

        let settledOnline = await task.value

        let finalSnapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertTrue(settledOnline)
        XCTAssertEqual(probeSequence.callCount, 3)
        XCTAssertFalse(auth.isLoading)
        XCTAssertFalse(auth.initializing)
        XCTAssertFalse(auth.isOfflineMode)
        XCTAssertTrue(finalSnapshot.monitoringActive)
        XCTAssertEqual(finalSnapshot.handlerCount, 1)
    }

    func test_completeUnauthenticatedStartupInitialization_sustainedFailure_commitsOfflineAfterRaceWindow() async {
        auth.setIsLoading(true)
        auth.setInitializing(true)
        auth.setIsOfflineMode(false)

        let postConnectivityServicesCalled = BooleanBox(false)
        let probeSequence = StartupProbeSequence(Array(repeating: false, count: 20))

        let task = Task {
            await auth.completeUnauthenticatedStartupInitialization(
                monitoringInterval: 1,
                startupProbeTimeout: 0.01,
                offlineCommitWindow: 1.0,
                probeDelay: 0.1,
                connectivityProbe: { _ in
                    probeSequence.next()
                },
                postConnectivityServices: {
                    postConnectivityServicesCalled.value = true
                }
            )
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        let midRaceSnapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertFalse(midRaceSnapshot.monitoringActive)
        XCTAssertTrue(auth.isLoading)
        XCTAssertTrue(auth.initializing)
        XCTAssertFalse(auth.isOfflineMode)

        let settledOnline = await task.value

        let finalSnapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertFalse(settledOnline)
        XCTAssertGreaterThanOrEqual(probeSequence.callCount, 2)
        XCTAssertFalse(postConnectivityServicesCalled.value)
        XCTAssertFalse(auth.isLoading)
        XCTAssertFalse(auth.initializing)
        XCTAssertTrue(auth.isOfflineMode)
        XCTAssertTrue(finalSnapshot.monitoringActive)
        XCTAssertEqual(finalSnapshot.handlerCount, 1)
    }

    private func executeCallback(
        allowFallback: Bool,
        url: URL?,
        error: Error? = nil,
        pendingOAuthState: String? = nil
    ) async -> Result<User, FronteggError> {
        await withCheckedContinuation { continuation in
            let handler = auth.createOauthCallbackHandler(
                { result in
                    continuation.resume(returning: result)
                },
                allowLastCodeVerifierFallback: allowFallback,
                redirectUriOverride: "test://callback",
                pendingOAuthState: pendingOAuthState
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

    private func executeSocialLoginOAuthCallback(
        providerString: String = "google",
        url: URL?,
        error: Error? = nil
    ) async -> Result<User, FronteggError> {
        await withCheckedContinuation { continuation in
            auth.handleSocialLoginOAuthCallback(
                providerString: providerString,
                callbackURL: url,
                error: error
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func makeCallbackUrl(
        code: String? = nil,
        state: String? = nil,
        errorMessage: String? = nil,
        errorDescription: String? = nil
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
        if let errorDescription {
            items.append(URLQueryItem(name: "error_description", value: errorDescription))
        }
        components.queryItems = items
        return components.url!
    }

    private func makeGeneratedRedirectCallbackUrl(
        bundleIdentifier: String = currentAppBundleIdentifier(),
        host: String = "test.example.com",
        path: String = "/ios/oauth/callback",
        code: String? = nil,
        state: String? = nil,
        errorMessage: String? = nil,
        errorDescription: String? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = bundleIdentifier.lowercased()
        components.host = host
        components.path = path

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
        if let errorDescription {
            items.append(URLQueryItem(name: "error_description", value: errorDescription))
        }
        components.queryItems = items
        return components.url!
    }

    private func currentTestBundleIdentifier() -> String {
        currentAppBundleIdentifier()
    }

    private func waitForOAuthErrorDispatch() async {
        for _ in 0..<4 {
            await Task.yield()
            await MainActor.run {}
        }
    }

    private func makeSharedAppConfig() -> FronteggPlist {
        FronteggPlist(
            lateInit: true,
            payload: .singleRegion(
                .init(
                    baseUrl: "https://test.example.com",
                    clientId: "test-client-id"
                )
            ),
            keepUserLoggedInAfterReinstall: true,
            useAsWebAuthenticationForAppleLogin: false
        )
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
        SocialLoginUrlGenerator.shared.clearPendingSocialCodeVerifiers()
    }

    private func makeRawSocialState(
        provider: String,
        appId: String,
        action: String,
        oauthState: String? = nil
    ) throws -> String {
        var payload: [String: String] = [
            "provider": provider,
            "appId": appId,
            "action": action,
            "bundleId": "com.frontegg.tests",
            "platform": "ios"
        ]

        if let oauthState {
            payload["oauthState"] = oauthState
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
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
