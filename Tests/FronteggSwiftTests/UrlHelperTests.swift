//
//  UrlHelperTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class UrlHelperTests: XCTestCase {
    private let testBaseUrl = "https://auth.example.com"
    private let testClientId = "test-url-helper-client"

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

    // MARK: - getCallbackType

    func test_getCallbackType_returnsHostedLoginCallback_forOAuthCallback() {
        let url = URL(string: "https://app.example.com/oauth/callback")!
        XCTAssertEqual(getCallbackType(url), .HostedLoginCallback)
    }

    func test_getCallbackType_returnsMagicLink_forMagicLinkCallback() {
        let url = URL(string: "https://app.example.com/oauth/magic-link/callback")!
        XCTAssertEqual(getCallbackType(url), .MagicLink)
    }

    func test_getCallbackType_returnsUnknown_forOtherPath() {
        let url = URL(string: "https://app.example.com/other/path")!
        XCTAssertEqual(getCallbackType(url), .Unknown)
    }

    func test_getCallbackType_returnsUnknown_forNilURL() {
        XCTAssertEqual(getCallbackType(nil), .Unknown)
    }

    // MARK: - getQueryItems

    func test_getQueryItems_parsesQueryString() {
        let urlString = "https://example.com/callback?code=abc123&state=xyz"
        let items = getQueryItems(urlString)
        XCTAssertNotNil(items)
        XCTAssertEqual(items?["code"], "abc123")
        XCTAssertEqual(items?["state"], "xyz")
    }

    func test_getQueryItems_returnsNil_whenURLCannotBeParsed() {
        // Empty string makes URL(string:) return nil, so getQueryItems returns nil
        let items = getQueryItems("")
        XCTAssertNil(items)
    }

    func test_getQueryItems_emptyQuery() {
        let urlString = "https://example.com/path"
        let items = getQueryItems(urlString)
        XCTAssertNotNil(items)
        XCTAssertTrue(items?.isEmpty ?? true)
    }

    // MARK: - getURLComonents

    func test_getURLComonents_returnsComponents_forValidURL() {
        let urlString = "https://example.com/path?foo=bar"
        let components = getURLComonents(urlString)
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.host, "example.com")
        XCTAssertEqual(components?.path, "/path")
    }

    func test_getURLComonents_returnsNil_forNilString() {
        let components = getURLComonents(nil)
        XCTAssertNil(components)
    }

    // MARK: - Generated redirect aliases

    func test_supportedGeneratedRedirectUris_includeBasePathAndRootAlias_whenBaseUrlHasPath() {
        let uris = supportedGeneratedRedirectUris(
            baseUrl: "https://auth.example.com/fe-auth/",
            bundleIdentifier: "com.frontegg.demo"
        )

        XCTAssertEqual(
            uris,
            [
                "com.frontegg.demo://auth.example.com/fe-auth/ios/oauth/callback",
                "com.frontegg.demo://auth.example.com/ios/oauth/callback",
            ]
        )
    }

    func test_generateRedirectUri_normalizesTrailingSlashInBasePath() {
        let redirectUri = generateRedirectUri(
            baseUrl: "https://auth.example.com/fe-auth/",
            bundleIdentifier: "com.frontegg.demo"
        )

        XCTAssertEqual(
            redirectUri,
            "com.frontegg.demo://auth.example.com/fe-auth/ios/oauth/callback"
        )
    }

    func test_currentAppBundleIdentifier_prefersRuntimeOverrideWhenPresent() {
        let app = FronteggApp.shared
        let previousBundleIdentifier = app.bundleIdentifier
        defer { app.bundleIdentifier = previousBundleIdentifier }

        app.bundleIdentifier = "Com.Override.Bundle"

        XCTAssertEqual(currentAppBundleIdentifier(), "com.override.bundle")
    }

    func test_generateRedirectUri_usesRuntimeBundleIdentifierOverride() {
        let app = FronteggApp.shared
        let previousBaseUrl = app.baseUrl
        let previousBundleIdentifier = app.bundleIdentifier
        defer {
            app.baseUrl = previousBaseUrl
            app.bundleIdentifier = previousBundleIdentifier
        }

        app.baseUrl = "https://auth.example.com/fe-auth"
        app.bundleIdentifier = "Com.Override.Bundle"

        XCTAssertEqual(
            generateRedirectUri(),
            "com.override.bundle://auth.example.com/fe-auth/ios/oauth/callback"
        )
    }

    func test_generateRedirectUri_returnsInvalidSentinel_whenBaseUrlCannotBeParsed() {
        let redirectUri = generateRedirectUri(
            baseUrl: "not a valid url",
            bundleIdentifier: "com.frontegg.demo"
        )

        XCTAssertEqual(
            redirectUri,
            "com.frontegg.demo://invalid/ios/oauth/callback"
        )
    }

    func test_generateRedirectUri_returnsDefaultInvalidSentinel_whenBundleIdentifierIsEmpty() {
        let redirectUri = generateRedirectUri(
            baseUrl: "not a valid url",
            bundleIdentifier: ""
        )

        XCTAssertEqual(
            redirectUri,
            "frontegg-invalid://invalid/ios/oauth/callback"
        )
    }

    func test_supportedGeneratedRedirectUris_withoutBasePath_returnsOnlyCanonicalCallback() {
        let uris = supportedGeneratedRedirectUris(
            baseUrl: "https://auth.example.com",
            bundleIdentifier: "com.frontegg.demo"
        )

        XCTAssertEqual(
            uris,
            [
                "com.frontegg.demo://auth.example.com/ios/oauth/callback",
            ]
        )
    }

    func test_matchedGeneratedRedirectUri_acceptsRootAlias_whenBaseUrlHasPath() {
        let callbackUrl = URL(string: "com.frontegg.demo://auth.example.com/ios/oauth/callback?code=123")!

        let matched = matchedGeneratedRedirectUri(
            callbackUrl,
            baseUrl: "https://auth.example.com/fe-auth",
            bundleIdentifier: "com.frontegg.demo"
        )

        XCTAssertEqual(matched, "com.frontegg.demo://auth.example.com/ios/oauth/callback")
    }

    func test_matchedGeneratedRedirectUri_acceptsCanonicalBasePathCallback_whenBaseUrlHasPath() {
        let callbackUrl = URL(string: "com.frontegg.demo://auth.example.com/fe-auth/ios/oauth/callback?code=123")!

        let matched = matchedGeneratedRedirectUri(
            callbackUrl,
            baseUrl: "https://auth.example.com/fe-auth",
            bundleIdentifier: "com.frontegg.demo"
        )

        XCTAssertEqual(matched, "com.frontegg.demo://auth.example.com/fe-auth/ios/oauth/callback")
    }

    func test_routedAppPath_stripsBasePathPrefix_forBaseUrlRoutes() {
        let routedPath = routedAppPath(
            URL(string: "https://auth.example.com/fe-auth/oauth/account/social/success?code=123")!,
            baseUrl: "https://auth.example.com/fe-auth"
        )

        XCTAssertEqual(routedPath, "/oauth/account/social/success")
    }

    func test_getOverrideUrlType_treatsBasePathSocialSuccessAsLoginRoute() {
        let app = FronteggApp.shared
        let originalBaseUrl = app.baseUrl
        defer { app.baseUrl = originalBaseUrl }

        app.baseUrl = "https://auth.example.com/fe-auth"

        let url = URL(string: "https://auth.example.com/fe-auth/oauth/account/social/success?code=123")!
        XCTAssertEqual(getOverrideUrlType(url: url), .loginRoutes)
    }

    func test_getOverrideUrlType_treatsBasePathSocialPreloginAsSocialOauthPreLogin() {
        let app = FronteggApp.shared
        let originalBaseUrl = app.baseUrl
        defer { app.baseUrl = originalBaseUrl }

        app.baseUrl = "https://auth.example.com/fe-auth"

        let url = URL(
            string: "https://auth.example.com/fe-auth/frontegg/identity/resources/auth/v1/user/sso/default/google/prelogin"
        )!
        XCTAssertEqual(getOverrideUrlType(url: url), .SocialOauthPreLogin)
    }

    // MARK: - isSocialLoginPath

    func test_isSocialLoginPath_returnsTrue_forIdentityPrelogin() {
        let path = "/frontegg/identity/resources/auth/v1/user/sso/default/google/prelogin"
        XCTAssertTrue(isSocialLoginPath(path))
    }

    func test_isSocialLoginPath_returnsTrue_forShortIdentityPrelogin() {
        let path = "/identity/resources/auth/v1/user/sso/default/github/prelogin"
        XCTAssertTrue(isSocialLoginPath(path))
    }

    func test_isSocialLoginPath_returnsFalse_forOtherPath() {
        XCTAssertFalse(isSocialLoginPath("/oauth/callback"))
        XCTAssertFalse(isSocialLoginPath("/some/other/path"))
    }
}
