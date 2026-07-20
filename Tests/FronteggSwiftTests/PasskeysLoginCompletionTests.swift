//
//  PasskeysLoginCompletionTests.swift
//  FronteggSwiftTests
//
//  Regression coverage for FR-25928 (login path): loginWithPasskeys must
//  (1) report success through the completion handler — previously the success
//  path ended at setCredentials and never called completion, hanging any caller
//  awaiting it — and (2) reset isLoading on failure — previously the
//  FronteggError branch called completion but never reset isLoading, leaving
//  the loader spinning forever.
//

import XCTest
@testable import FronteggSwift

private final class MockPasskeysApi: Api {
    enum Mode {
        case failPrelogin(FronteggError)
        case succeed
    }

    var mode: Mode = .failPrelogin(.authError(.invalidPasskeysRequest))
    var meUser: User?
    var postloginResponse: AuthResponse?

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    override func preloginWebauthn() async throws -> WebauthnPreloginResponse {
        if case .failPrelogin(let error) = mode { throw error }
        let json = #"{"options":{"timeout":60000,"rpId":"test.example.com","userVerification":"preferred","challenge":"AAAA"}}"#
            .data(using: .utf8)!
        return try JSONDecoder().decode(WebauthnPreloginResponse.self, from: json)
    }

    @available(iOS 15.0, *)
    override func postloginWebauthn(assertion: WebauthnAssertion) async throws -> AuthResponse {
        guard let postloginResponse else { throw FronteggError.authError(.invalidPasskeysRequest) }
        return postloginResponse
    }

    override func me(accessToken: String, refreshToken: String) async throws -> MeResult {
        MeResult(user: meUser, refreshedTokens: nil)
    }
}

final class PasskeysLoginCompletionTests: XCTestCase {

    private var auth: FronteggAuth!
    private var credentialManager: CredentialManager!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()
        credentialManager = CredentialManager(serviceKey: "frontegg-passkeys-tests-\(UUID().uuidString)")
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
    }

    override func tearDown() {
        auth?.cancelScheduledTokenRefresh()
        auth = nil
        Thread.sleep(forTimeInterval: 0.1)
        NetworkStatusMonitor._testReset()
        credentialManager?.clear()
        credentialManager = nil
        super.tearDown()
    }

    @available(iOS 15.0, *)
    func testLoginWithPasskeys_whenFlowFailsWithFronteggError_resetsIsLoadingAndReportsFailure() async {
        let api = MockPasskeysApi()
        api.mode = .failPrelogin(.authError(.invalidPasskeysRequest))
        auth.api = api

        await MainActor.run { auth.setIsLoading(true) }

        var received: FronteggError?
        await PasskeysAuthenticator.shared.loginWithPasskeys({ result in
            if case .failure(let error) = result {
                received = error
            }
        }, auth: auth)

        guard case .authError(.invalidPasskeysRequest)? = received else {
            return XCTFail("Expected .invalidPasskeysRequest failure, got \(String(describing: received))")
        }

        let stillLoading = await MainActor.run { auth.isLoading }
        XCTAssertFalse(stillLoading, "isLoading must be reset after a passkey login failure (stuck-loader bug)")
    }

    @available(iOS 15.0, *)
    func testLoginWithPasskeys_onSuccess_reportsSuccessThroughCompletionAndResetsIsLoading() async throws {
        let api = MockPasskeysApi()
        api.mode = .succeed
        let accessToken = try TestDataFactory.makeJWT(payloadDict: [
            "sub": "user-1",
            "tenantId": "tenant-1",
            "exp": Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        ])
        api.meUser = try JSONDecoder().decode(
            User.self,
            from: JSONSerialization.data(withJSONObject: TestDataFactory.makeUser(email: "passkey@example.com"))
        )
        api.postloginResponse = try JSONDecoder().decode(
            AuthResponse.self,
            from: JSONSerialization.data(withJSONObject: TestDataFactory.makeAuthResponse(
                refreshToken: "refresh-1",
                accessToken: accessToken
            ))
        )
        auth.api = api

        await MainActor.run { auth.setIsLoading(true) }

        let cannedAssertion = WebauthnAssertion(
            id: "credential-id",
            rawId: "credential-id",
            response: WebauthnAssertionResponse(
                clientDataJSON: "client-data",
                authenticatorData: "authenticator-data",
                signature: "signature",
                userHandle: "user-handle"
            )
        )

        var successEmail: String?
        await PasskeysAuthenticator.shared.loginWithPasskeys(
            { result in
                if case .success(let user) = result {
                    successEmail = user.email
                }
            },
            auth: auth,
            performAssertion: { _, _ in cannedAssertion }
        )

        XCTAssertEqual(successEmail, "passkey@example.com", "successful passkey login must be reported through completion")

        let stillLoading = await MainActor.run { auth.isLoading }
        XCTAssertFalse(stillLoading, "isLoading must be reset after a successful passkey login")
    }
}
