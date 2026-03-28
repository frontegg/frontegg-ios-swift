//
//  SocialLoginUrlGeneratorTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

private final class MockCustomSocialLoginApi: Api {
    let customProvidersResponse: CustomSocialLoginProvidersResponse
    var standardConfig = SocialLoginConfig(options: [])
    var featureFlagsResponse = "{\"identity-sso-force-pkce\":\"on\"}"

    init(
        baseUrl: String,
        clientId: String,
        customProvidersResponse: CustomSocialLoginProvidersResponse
    ) {
        self.customProvidersResponse = customProvidersResponse
        super.init(baseUrl: baseUrl, clientId: clientId, applicationId: nil)
    }

    override func getSocialLoginConfig() async throws -> SocialLoginConfig {
        standardConfig
    }

    override func getCustomSocialLoginConfig() async throws -> CustomSocialLoginProvidersResponse {
        customProvidersResponse
    }

    override func getFeatureFlags() async throws -> String {
        featureFlagsResponse
    }
}

final class SocialLoginUrlGeneratorTests: XCTestCase {

    private let testBaseUrl = "https://test.frontegg.com"
    private let testClientId = "test-social-client"

    override func setUp() {
        super.setUp()
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: testBaseUrl, clientId: testClientId)),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: testBaseUrl, cliendId: testClientId)
    }

    override func tearDown() {
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    private func queryItems(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }

        return queryItems.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        }
    }

    // MARK: - ProviderDetails Unit Tests

    func test_ProviderDetails_for_all_standard_providers_returns_details() {
        for provider in SocialLoginProvider.allCases {
            XCTAssertNoThrow(try ProviderDetails.for(provider: provider), "ProviderDetails missing for \(provider.rawValue)")
        }
    }

    func test_ProviderDetails_google_has_correct_endpoint() throws {
        let details = try ProviderDetails.for(provider: .google)
        XCTAssertEqual(details.authorizeEndpoint, "https://accounts.google.com/o/oauth2/v2/auth")
    }

    func test_ProviderDetails_google_requires_pkce() throws {
        let details = try ProviderDetails.for(provider: .google)
        XCTAssertTrue(details.requiresPKCE)
    }

    func test_ProviderDetails_microsoft_has_query_response_mode() throws {
        let details = try ProviderDetails.for(provider: .microsoft)
        XCTAssertEqual(details.responseMode, "query")
    }

    func test_ProviderDetails_microsoft_requires_pkce() throws {
        let details = try ProviderDetails.for(provider: .microsoft)
        XCTAssertTrue(details.requiresPKCE)
    }

    func test_ProviderDetails_facebook_has_reauthenticate_prompt() throws {
        let details = try ProviderDetails.for(provider: .facebook)
        XCTAssertEqual(details.promptValueForConsent, "reauthenticate")
    }

    func test_ProviderDetails_apple_has_form_post_response_mode() throws {
        let details = try ProviderDetails.for(provider: .apple)
        XCTAssertEqual(details.responseMode, "form_post")
    }

    func test_ProviderDetails_apple_does_not_require_pkce() throws {
        let details = try ProviderDetails.for(provider: .apple)
        XCTAssertFalse(details.requiresPKCE)
    }

    func test_ProviderDetails_github_has_correct_endpoint() throws {
        let details = try ProviderDetails.for(provider: .github)
        XCTAssertEqual(details.authorizeEndpoint, "https://github.com/login/oauth/authorize")
    }

    func test_ProviderDetails_slack_has_correct_endpoint() throws {
        let details = try ProviderDetails.for(provider: .slack)
        XCTAssertEqual(details.authorizeEndpoint, "https://slack.com/openid/connect/authorize")
    }

    func test_ProviderDetails_linkedin_has_correct_endpoint() throws {
        let details = try ProviderDetails.for(provider: .linkedin)
        XCTAssertEqual(details.authorizeEndpoint, "https://www.linkedin.com/oauth/v2/authorization")
    }

    // MARK: - ProviderDetails.find(by:)

    func test_ProviderDetails_find_by_google_url() {
        let result = ProviderDetails.find(by: "https://accounts.google.com/o/oauth2/v2/auth")
        XCTAssertEqual(result?.provider, .google)
    }

    func test_ProviderDetails_find_by_microsoft_url() {
        let result = ProviderDetails.find(by: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")
        XCTAssertEqual(result?.provider, .microsoft)
    }

    func test_ProviderDetails_find_by_unknown_url_returns_nil() {
        let result = ProviderDetails.find(by: "https://unknown-provider.com/auth")
        XCTAssertNil(result)
    }

    // MARK: - createState

    func test_createState_produces_valid_json() throws {
        let state = try SocialLoginUrlGenerator.createState(
            provider: .google,
            appId: "test-app-id",
            action: .login
        )
        XCTAssertFalse(state.isEmpty)

        let data = state.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SocialLoginUrlGenerator.OAuthState.self, from: data)

        XCTAssertEqual(decoded.provider, "google")
        XCTAssertEqual(decoded.appId, "test-app-id")
        XCTAssertEqual(decoded.action, "login")
        XCTAssertEqual(decoded.platform, "ios")
        XCTAssertFalse(decoded.bundleId.isEmpty)
    }

    func test_createState_signUp_action() throws {
        let state = try SocialLoginUrlGenerator.createState(
            provider: .facebook,
            appId: nil,
            action: .signUp
        )

        let data = state.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SocialLoginUrlGenerator.OAuthState.self, from: data)

        XCTAssertEqual(decoded.provider, "facebook")
        XCTAssertEqual(decoded.action, "signUp")
        XCTAssertEqual(decoded.appId, "") // nil becomes empty string
    }

    func test_createState_custom_provider_string() throws {
        let state = try SocialLoginUrlGenerator.createState(
            provider: "custom-oauth",
            appId: "app-1",
            action: .login
        )

        let data = state.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SocialLoginUrlGenerator.OAuthState.self, from: data)

        XCTAssertEqual(decoded.provider, "custom-oauth")
    }

    func test_authorizeURL_customProvider_matchesHostedStateAndGracefullySkipsPkceWithoutWebview() async throws {
        let provider = CustomSocialLoginProviderConfig(
            id: "e9a221f3-3d2a-413d-8183-dc9904fc70af",
            type: "custom",
            clientId: "561527650079-45kt8nvlrh5sghoqdtkq2g7cpau6used.apps.googleusercontent.com",
            authorizationUrl: "https://accounts.google.com/o/oauth2/v2/auth?prompt=select_account",
            scopes: "https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email",
            displayName: "custom",
            active: true,
            redirectUrl: "\(testBaseUrl)/oauth/account/social/success"
        )
        let mockApi = MockCustomSocialLoginApi(
            baseUrl: testBaseUrl,
            clientId: testClientId,
            customProvidersResponse: CustomSocialLoginProvidersResponse(providers: [provider])
        )
        let featureFlagSuiteName = "SocialLoginUrlGeneratorTests.\(UUID().uuidString)"
        let featureFlagStorage = try XCTUnwrap(UserDefaults(suiteName: featureFlagSuiteName))
        let auth = FronteggAuth.shared
        let originalApi = auth.api
        let originalFeatureFlags = auth.featureFlags

        auth.api = mockApi
        auth.featureFlags = FeatureFlags(
            .init(clientId: testClientId, api: mockApi, storage: featureFlagStorage)
        )

        defer {
            auth.api = originalApi
            auth.featureFlags = originalFeatureFlags
            featureFlagStorage.removePersistentDomain(forName: featureFlagSuiteName)
        }

        await auth.featureFlags.start()
        await SocialLoginUrlGenerator.shared.reloadConfigs()

        guard let url = try await SocialLoginUrlGenerator.shared.authorizeURL(
            forCustomProvider: provider.id,
            action: .login
        ) else {
            return XCTFail("Expected custom provider authorize URL")
        }

        let params = queryItems(from: url)
        XCTAssertEqual(params["client_id"], provider.clientId)
        XCTAssertEqual(params["redirect_uri"], provider.redirectUrl)
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["prompt"], "select_account")
        // PKCE params are absent because there is no webview in the test environment.
        // In production, getCodeVerifierFromWebview() would succeed and PKCE params would be present.
        XCTAssertNil(params["code_challenge"])
        XCTAssertNil(params["code_challenge_method"])

        let state = try XCTUnwrap(params["state"])
        let stateData = try XCTUnwrap(state.data(using: .utf8))
        let stateObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: stateData, options: []) as? [String: String]
        )

        XCTAssertEqual(stateObject["provider"], "custom")
        XCTAssertEqual(stateObject["action"], "login")
        XCTAssertEqual(stateObject["bundleId"], FronteggApp.shared.bundleIdentifier)
        XCTAssertEqual(stateObject["platform"], "ios")
        XCTAssertNil(stateObject["oauthState"])
        XCTAssertEqual(stateObject["appId"], "")
    }

    // MARK: - defaultRedirectUri / defaultSocialLoginRedirectUri

    func test_defaultSocialLoginRedirectUri_format() {
        let uri = SocialLoginUrlGenerator.shared.defaultSocialLoginRedirectUri()
        XCTAssertTrue(uri.contains(testBaseUrl), "Should contain base URL")
        XCTAssertTrue(uri.contains("/oauth/account/social/success"), "Should contain social success path")
    }

    func test_defaultRedirectUri_format() {
        let uri = SocialLoginUrlGenerator.shared.defaultRedirectUri()
        XCTAssertTrue(uri.contains(testBaseUrl), "Should contain base URL")
        XCTAssertTrue(uri.contains("/oauth/account/redirect/ios/"), "Should contain iOS redirect path")
    }

    // MARK: - SocialLoginProvider.details accessor

    func test_provider_details_accessor_works_for_all() {
        for provider in SocialLoginProvider.allCases {
            let details = provider.details
            XCTAssertFalse(details.authorizeEndpoint.isEmpty, "\(provider.rawValue) should have non-empty endpoint")
            XCTAssertFalse(details.defaultScopes.isEmpty, "\(provider.rawValue) should have default scopes")
            XCTAssertEqual(details.responseType, "code", "\(provider.rawValue) should use code response type")
        }
    }
}
