//
//  SocialLoginCallbackFR26132Tests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

/// FR-26132: embedded Google login on iOS fails with
/// "Failed to get extract code from hostedLoginCallback url".
///
/// Reproduction uses the customer's exact values from their device log
/// (Flutter v1.0.48 / FronteggSwift 1.3.7).
final class SocialLoginCallbackFR26132Tests: XCTestCase {

    private let baseUrl = "https://auth.protect.oosto.dev"
    private let bundleId = "com.oosto.protect"

    /// The ASWebAuthenticationSession callback URL, verbatim from the log.
    private let callbackUrlString = "com.oosto.protect://auth.protect.oosto.dev/ios/oauth/callback?state=%7B%22appId%22%3A%2284ca46b8-f759-4a66-83a4-89cc0335257e%22%2C%22platform%22%3A%22ios%22%2C%22provider%22%3A%22google%22%2C%22bundleId%22%3A%22com.oosto.protect%22%2C%22action%22%3A%22login%22%7D&iss=https%3A%2F%2Faccounts.google.com&code=4%2F0AXEQxIAsWWCPT5x_F0fLrs658xcNMtLYWHy-uS3kn8d-BqoeWGct88Lm2Wt-5ZPuNIsylw&scope=email+profile&authuser=0&hd=lampalampa.net&prompt=none&social-login-callback=true"

    private var originalBundleIdentifier = ""

    // Required even though every call below passes `baseUrl` and `bundleIdentifier`
    // explicitly: `matchedGeneratedRedirectUri` and `supportedGeneratedRedirectUris`
    // default `useAssetLinks` to `isAssetLinksRedirectEnabled()`, which reads
    // `FronteggApp.shared`. Without a config override that access loads the plist
    // and traps (FR-26226), killing the test process before any assertion runs.
    override func setUp() {
        super.setUp()
        originalBundleIdentifier = FronteggApp.shared.bundleIdentifier
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: baseUrl, clientId: "test-oosto-client")),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: baseUrl, cliendId: "test-oosto-client")
    }

    override func tearDown() {
        // `manualInit` sets `bundleIdentifier` from `Bundle.main`, which in the test
        // host is "com.apple.dt.xctest.tool". `SocialLoginUrlGeneratorTests` asserts
        // on an unset identifier, so leaving it behind fails an unrelated suite.
        FronteggApp.shared.bundleIdentifier = originalBundleIdentifier
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    func test_supportedRedirectUris_containTheGeneratedCallback() {
        let uris = supportedGeneratedRedirectUris(baseUrl: baseUrl, bundleIdentifier: bundleId)
        XCTAssertTrue(
            uris.contains("com.oosto.protect://auth.protect.oosto.dev/ios/oauth/callback"),
            "generated redirect uris did not include the callback the SDK actually sent: \(uris)"
        )
    }

    /// `handleSocialLoginCallback` only proceeds when the path is
    /// `/oauth/account/redirect/ios/...` OR `matchedGeneratedRedirectUri` matches.
    /// The real callback path is `/ios/oauth/callback`, so this match is what
    /// decides between a successful exchange and `.failedToExtractCode`.
    func test_matchedGeneratedRedirectUri_matchesTheRealCallbackUrl() {
        let url = URL(string: callbackUrlString)!
        let matched = matchedGeneratedRedirectUri(url, baseUrl: baseUrl, bundleIdentifier: bundleId)
        XCTAssertNotNil(
            matched,
            "callback URL did not match any generated redirect uri -> handleSocialLoginCallback returns nil -> failedToExtractCode"
        )
    }

    /// Guard-by-guard walkthrough of `handleSocialLoginCallback`, so a failure
    /// points at the exact precondition that rejects the callback.
    func test_handleSocialLoginCallbackPreconditions() {
        let url = URL(string: callbackUrlString)!
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertNotNil(comps, "URLComponents failed to parse the custom-scheme callback")

        XCTAssertEqual(comps?.host, URL(string: baseUrl)?.host, "host guard would reject")

        let path = comps?.path ?? ""
        let hasRedirectPrefix = path.hasPrefix("/oauth/account/redirect/ios/")
        let matched = matchedGeneratedRedirectUri(url, baseUrl: baseUrl, bundleIdentifier: bundleId)
        XCTAssertTrue(
            hasRedirectPrefix || matched != nil,
            "path '\(path)' has no /oauth/account/redirect/ios/ prefix and no generated-uri match -> returns nil"
        )

        let items = comps?.queryItems ?? []
        XCTAssertNil(items.first { $0.name == "error" }?.value, "unexpected error param")
        let code = items.first { $0.name == "code" }?.value
        XCTAssertNotNil(code, "callback carried no code")
        XCTAssertFalse(code?.isEmpty ?? true, "callback code was empty")
    }
}

/// FR-26132, second reproduction — captured on FronteggSwift 1.3.15, which carries
/// the instrumentation added for this ticket.
///
/// The device log settles the question the tests above could not: every
/// precondition passes, and the failure is logged as
/// "Social login callback could not be parsed" — i.e. `handleSocialLoginCallback`
/// returned nil *after* the guards, from its final statement:
///
///     URL(string: "\(baseUrl)/oauth/account/social/success?\(compsOut.query ?? "")")
///
/// The identity provider returns `state` as raw JSON. `comps.queryItems`
/// percent-decodes it, so `state` becomes `{"appId":"",...}`. Assigning that back
/// through `URLComponents.queryItems` does **not** re-encode `{`, `"` or `}` —
/// `URLComponents.query` hands them back verbatim — and those characters are
/// illegal in a query component under RFC 3986. On iOS 17+ `URL(string:)` parses
/// strictly and returns nil rather than repairing them, so the success URL is
/// never built and the flow surfaces the misleading "Failed to get extract code".
final class SocialLoginSuccessUrlConstructionTests: XCTestCase {

    private let baseUrl = "https://app-bv4uq4gr7esi.frontegg.com"
    private let bundleId = "com.frontegg.demo"

    /// Verbatim from the 1.3.15 device log, line 23541.
    private let callbackUrlString = "com.frontegg.demo://app-bv4uq4gr7esi.frontegg.com/ios/oauth/callback?state=%7B%22appId%22%3A%22%22%2C%22platform%22%3A%22ios%22%2C%22provider%22%3A%22google%22%2C%22bundleId%22%3A%22com.frontegg.demo%22%2C%22action%22%3A%22login%22%7D&iss=https%3A%2F%2Faccounts.google.com&code=4%2F0AXEQxICyox6tGpgZA34logmeXNZL5AgSv5lkZTShyfs_fulpLki17ERtzeKbmiVXgipukw&scope=email+profile&authuser=0&hd=frontegg.com&prompt=none&social-login-callback=true"

    private var originalBundleIdentifier = ""

    override func setUp() {
        super.setUp()
        originalBundleIdentifier = FronteggApp.shared.bundleIdentifier
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(.init(baseUrl: baseUrl, clientId: "test-fr-26132-client")),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(baseUrl: baseUrl, cliendId: "test-fr-26132-client")
        FronteggApp.shared.bundleIdentifier = bundleId
    }

    override func tearDown() {
        // Must be restored: `currentAppBundleIdentifier()` prefers this over
        // `Bundle.main`, so leaving it set would redirect every other suite's
        // redirect-uri generation at com.frontegg.demo.
        FronteggApp.shared.bundleIdentifier = originalBundleIdentifier
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    /// The regression, end to end: a callback that satisfies every guard must
    /// still yield a success URL.
    func test_handleSocialLoginCallback_buildsSuccessUrl_whenStateIsRawJson() {
        let url = URL(string: callbackUrlString)!

        let successUrl = FronteggAuth.shared.handleSocialLoginCallback(url)

        XCTAssertNotNil(
            successUrl,
            "every precondition passes, so a nil result can only come from the final URL(string:) — the raw-JSON state leaves illegal characters in the query"
        )
    }

    /// The success URL must carry the code through, otherwise the exchange fails
    /// with the same user-visible error even when a URL is produced.
    func test_successUrl_carriesTheAuthorizationCode() {
        let url = URL(string: callbackUrlString)!

        guard let successUrl = FronteggAuth.shared.handleSocialLoginCallback(url) else {
            return XCTFail("no success URL was produced")
        }

        let items = URLComponents(url: successUrl, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(
            items.first { $0.name == "code" }?.value,
            "4/0AXEQxICyox6tGpgZA34logmeXNZL5AgSv5lkZTShyfs_fulpLki17ERtzeKbmiVXgipukw",
            "the authorization code did not survive the round-trip through the success URL"
        )
    }

    /// The state must survive intact — the backend matches it against the pending
    /// OAuth request, so a mangled or dropped value fails the exchange.
    func test_successUrl_preservesTheStatePayload() throws {
        let url = URL(string: callbackUrlString)!

        guard let successUrl = FronteggAuth.shared.handleSocialLoginCallback(url) else {
            return XCTFail("no success URL was produced")
        }

        let items = URLComponents(url: successUrl, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let state = items.first { $0.name == "state" }?.value

        // Building through URLComponents percent-encodes more of the raw-JSON state
        // than the old string interpolation did (`:` and `,` are escaped too). That is
        // a wire-level difference only, so this asserts on the decoded payload rather
        // than the serialized string — JSON key order carries no meaning, and pinning
        // it makes the test fail for reasons that cannot affect the sign-in.
        let data = try XCTUnwrap(state?.data(using: .utf8), "state was dropped from the success URL")
        let decoded = try JSONDecoder().decode(SocialLoginUrlGenerator.CanonicalOAuthState.self, from: data)

        XCTAssertEqual(decoded.provider, "google")
        XCTAssertEqual(decoded.appId, "")
        XCTAssertEqual(decoded.action, "login")
    }

    /// The authorization code contains `/` and may contain other characters that
    /// encode differently depending on how the query is assembled. It must decode
    /// back to exactly what the provider sent.
    func test_successUrl_decodesToTheExactValuesTheProviderSent() {
        let url = URL(string: callbackUrlString)!
        let sent = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        guard let successUrl = FronteggAuth.shared.handleSocialLoginCallback(url) else {
            return XCTFail("no success URL was produced")
        }

        let received = URLComponents(url: successUrl, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(
            received.first { $0.name == "code" }?.value,
            sent.first { $0.name == "code" }?.value,
            "the authorization code was altered by the query encoding"
        )
        XCTAssertEqual(
            received.first { $0.name == "redirectUri" }?.value,
            "com.frontegg.demo://app-bv4uq4gr7esi.frontegg.com/ios/oauth/callback",
            "the redirect uri was altered by the query encoding"
        )
    }

    /// The device that produced the log has the App-Link redirect enabled — the log
    /// shows it fetching `.well-known/apple-app-site-association`. The callback still
    /// arrives on the custom scheme, so enabling the option must not stop the SDK
    /// recognising it.
    func test_handleSocialLoginCallback_buildsSuccessUrl_whenAssetLinksEnabled() {
        FronteggApp.shared.useAssetLinks = true
        defer { FronteggApp.shared.useAssetLinks = false }

        let url = URL(string: callbackUrlString)!

        XCTAssertNotNil(
            FronteggAuth.shared.handleSocialLoginCallback(url),
            "with useAssetLinks enabled the custom-scheme callback is no longer recognised"
        )
    }

    /// Guards the reason the string-interpolation approach was replaced:
    /// `URLComponents.query` hands back characters that are illegal in a query,
    /// so anything that re-parses that string is one Foundation change away from
    /// returning nil. Building through `URLComponents.url` must not depend on it.
    func test_urlComponentsQuery_leavesRawJsonCharactersUnencoded() {
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "state", value: #"{"appId":"","provider":"google"}"#)]

        let query = comps.query ?? ""
        XCTAssertTrue(
            query.contains("{") || query.contains("\""),
            "if Foundation ever starts encoding these, the compatibility risk this guards is gone: \(query)"
        )
        XCTAssertNotNil(comps.url, "URLComponents.url must build a URL regardless")
    }

    /// The success URL must be reachable by a strict parser, not only by Apple's
    /// lenient repair path — a server or proxy re-parsing it must see a valid URL.
    func test_successUrl_survivesStrictReparsing() {
        let url = URL(string: callbackUrlString)!

        guard let successUrl = FronteggAuth.shared.handleSocialLoginCallback(url) else {
            return XCTFail("no success URL was produced")
        }

        XCTAssertNotNil(
            URL(string: successUrl.absoluteString),
            "success URL cannot be re-parsed from its own string form: \(successUrl.absoluteString)"
        )
    }

    // MARK: - Rejection reasons
    //
    // FR-26132 was reproduced twice without the cause being identifiable, because
    // every precondition failure returned a bare nil and logged the same message.
    // These pin each branch to a distinct reason so the next field log names it.

    func test_rejects_whenHostIsNotTheConfiguredFronteggHost() {
        let url = URL(string: "com.frontegg.demo://evil.example.com/ios/oauth/callback?code=abc")!

        XCTAssertEqual(
            FronteggAuth.shared.resolveSocialLoginCallback(url).rejection,
            .hostMismatch
        )
    }

    func test_rejects_whenPathIsNeitherHostedRedirectNorGeneratedUri() {
        let url = URL(string: "com.frontegg.demo://app-bv4uq4gr7esi.frontegg.com/some/other/path?code=abc")!

        XCTAssertEqual(
            FronteggAuth.shared.resolveSocialLoginCallback(url).rejection,
            .unrecognisedCallbackPath
        )
    }

    func test_rejects_whenProviderReportsAnError() {
        let url = URL(string: "com.frontegg.demo://app-bv4uq4gr7esi.frontegg.com/ios/oauth/callback?error=access_denied")!

        XCTAssertEqual(
            FronteggAuth.shared.resolveSocialLoginCallback(url).rejection,
            .providerReportedError
        )
    }

    /// The real callback must not trip any rejection — this is the case the field
    /// logs claim is failing, so it is asserted as a reason, not just as non-nil.
    func test_realCallbackIsNotRejected() {
        let url = URL(string: callbackUrlString)!

        XCTAssertNil(
            FronteggAuth.shared.resolveSocialLoginCallback(url).rejection,
            "the device's own callback was rejected"
        )
    }
}

private extension Result where Failure == SocialLoginCallbackRejection {
    var rejection: SocialLoginCallbackRejection? {
        guard case .failure(let reason) = self else { return nil }
        return reason
    }
}
