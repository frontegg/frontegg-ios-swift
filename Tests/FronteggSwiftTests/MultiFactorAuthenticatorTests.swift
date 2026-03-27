//
//  MultiFactorAuthenticatorTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class MultiFactorAuthenticatorTests: XCTestCase {

    private let testBaseUrl = "https://test.frontegg.com"
    private let testClientId = "test-mfa-client"
    private var api: Api!

    override func setUp() {
        super.setUp()
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: testBaseUrl, clientId: testClientId)),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: testBaseUrl, cliendId: testClientId)
        api = Api(baseUrl: testBaseUrl, clientId: testClientId, applicationId: nil)
        CredentialManager.clearPendingOAuthFlows()
    }

    override func tearDown() {
        CredentialManager.clearPendingOAuthFlows()
        PlistHelper.testConfigOverride = nil
        api = nil
        super.tearDown()
    }

    // MARK: - start(mfaRequestJson:)

    func test_start_mfaRequestJson_returns_url_and_codeVerifier() throws {
        let mfa = MultiFactorAuthenticator(api: api, baseUrl: testBaseUrl)
        let json = "{\"mfaToken\":\"abc123\"}"

        let (url, codeVerifier) = try mfa.start(mfaRequestJson: json)

        XCTAssertTrue(url.absoluteString.contains("/oauth/authorize"))
        XCTAssertFalse(codeVerifier.isEmpty)

        // Verify login_direct_action is present
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let actionParam = components.queryItems?.first(where: { $0.name == "login_direct_action" })
        XCTAssertNotNil(actionParam?.value)
    }

    func test_start_mfaRequestJson_encodes_state_as_base64() throws {
        let mfa = MultiFactorAuthenticator(api: api, baseUrl: testBaseUrl)
        let json = "{\"mfaToken\":\"test-token\"}"

        let (url, _) = try mfa.start(mfaRequestJson: json)

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let actionParam = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "login_direct_action" })?.value)

        // Decode the login_direct_action (base64 encoded JSON)
        let actionData = try XCTUnwrap(Data(base64Encoded: actionParam))
        let actionDict = try JSONSerialization.jsonObject(with: actionData) as! [String: Any]

        XCTAssertEqual(actionDict["type"] as? String, "direct")

        let dataUrl = try XCTUnwrap(actionDict["data"] as? String)
        XCTAssertTrue(dataUrl.contains("mfa-mobile-authenticator?state="))

        // Extract and decode the state parameter
        let stateBase64 = try XCTUnwrap(dataUrl.components(separatedBy: "state=").last)
        let stateData = try XCTUnwrap(Data(base64Encoded: stateBase64))
        let stateJson = try XCTUnwrap(String(data: stateData, encoding: .utf8))
        XCTAssertTrue(stateJson.contains("mfaToken"))
    }

    func test_start_mfaRequestJson_url_contains_mfa_authenticator_path() throws {
        let mfa = MultiFactorAuthenticator(api: api, baseUrl: testBaseUrl)
        let json = "{\"key\":\"val\"}"

        let (url, _) = try mfa.start(mfaRequestJson: json)

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let actionBase64 = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "login_direct_action" })?.value)
        let actionData = try XCTUnwrap(Data(base64Encoded: actionBase64))
        let actionDict = try JSONSerialization.jsonObject(with: actionData) as! [String: Any]
        let dataUrl = try XCTUnwrap(actionDict["data"] as? String)

        XCTAssertTrue(dataUrl.hasPrefix("\(testBaseUrl)/oauth/account/mfa-mobile-authenticator"))
    }

    // MARK: - start(mfaRequestData:)

    func test_start_mfaRequestData_uses_data_without_refreshToken() async throws {
        let mfa = MultiFactorAuthenticator(api: api, baseUrl: testBaseUrl)
        let data: [String: Any] = ["mfaToken": "direct-data-token"]

        let (url, codeVerifier) = try await mfa.start(mfaRequestData: data)

        XCTAssertTrue(url.absoluteString.contains("/oauth/authorize"))
        XCTAssertFalse(codeVerifier.isEmpty)
    }

    func test_start_mfaRequestData_throws_when_refreshTokenForMfa_returns_nil() async {
        let mockApi = MockMfaApi(baseUrl: testBaseUrl, clientId: testClientId, applicationId: nil)
        mockApi.refreshTokenForMfaResult = nil

        let mfa = MultiFactorAuthenticator(api: mockApi, baseUrl: testBaseUrl)

        do {
            _ = try await mfa.start(mfaRequestData: [:], refreshToken: "some-refresh-token")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is FronteggError)
        }
    }

    func test_start_mfaRequestData_calls_refreshTokenForMfa_when_refreshToken_provided() async throws {
        let mockApi = MockMfaApi(baseUrl: testBaseUrl, clientId: testClientId, applicationId: nil)
        mockApi.refreshTokenForMfaResult = ["mfaToken": "refreshed-token"]

        let mfa = MultiFactorAuthenticator(api: mockApi, baseUrl: testBaseUrl)
        let (url, _) = try await mfa.start(mfaRequestData: [:], refreshToken: "rt-123")

        XCTAssertTrue(url.absoluteString.contains("/oauth/authorize"))
        XCTAssertEqual(mockApi.refreshTokenForMfaCallCount, 1)
    }
}

// MARK: - Mock

private final class MockMfaApi: Api {
    var refreshTokenForMfaResult: [String: Any]?
    var refreshTokenForMfaCallCount = 0

    override func refreshTokenForMfa(refreshTokenCookie: String) async -> [String: Any]? {
        refreshTokenForMfaCallCount += 1
        return refreshTokenForMfaResult
    }
}
