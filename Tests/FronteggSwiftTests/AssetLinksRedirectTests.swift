//
//  AssetLinksRedirectTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

/// Coverage for the opt-in App-Link (https) OAuth redirect (#293 / FR-26224).
///
/// The redirect URI is what every OAuth callback is matched against, so the two
/// properties that matter are: (1) with the option OFF the generated URIs are
/// byte-identical to the custom-scheme behaviour that shipped before, and
/// (2) with it ON the https URI is preferred *without* dropping the
/// custom-scheme URIs, so callbacks issued before the flip still match.
final class AssetLinksRedirectTests: XCTestCase {

    private let baseUrl = "https://auth.example.com"
    private let bundleId = "com.example.App"          // mixed case on purpose
    private var lowerBundleId: String { bundleId.lowercased() }

    private func uris(useAssetLinks: Bool) -> [String] {
        supportedGeneratedRedirectUris(
            baseUrl: baseUrl,
            bundleIdentifier: lowerBundleId,
            useAssetLinks: useAssetLinks,
            rawBundleIdentifier: bundleId
        )
    }

    // MARK: - Option OFF: no behaviour change

    func test_optionOff_returnsOnlyCustomSchemeUri() {
        XCTAssertEqual(uris(useAssetLinks: false), ["\(lowerBundleId)://auth.example.com/ios/oauth/callback"])
    }

    func test_optionOff_emitsNoHttpsUri() {
        XCTAssertFalse(
            uris(useAssetLinks: false).contains { $0.hasPrefix("https://") },
            "the opt-in must be inert when off — no https redirect may be generated"
        )
    }

    // MARK: - Option ON

    func test_optionOn_prefersHttpsUriFirst() {
        // generateRedirectUri() takes `.first`, so ordering is the behaviour.
        XCTAssertEqual(uris(useAssetLinks: true).first,
                       "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)")
    }

    /// Regression guard: flipping the option must not invalidate callbacks that
    /// were already issued against the custom scheme.
    func test_optionOn_stillIncludesCustomSchemeUri() {
        XCTAssertTrue(
            uris(useAssetLinks: true).contains("\(lowerBundleId)://auth.example.com/ios/oauth/callback"),
            "custom-scheme URI must survive so previously issued callbacks keep matching"
        )
    }

    /// https paths are case-sensitive, unlike custom URL schemes. The AASA routes
    /// publish the bundle id as-is, so the raw casing must be preserved here even
    /// though the scheme is lowercased.
    func test_optionOn_preservesRawBundleIdCasing() {
        let https = uris(useAssetLinks: true).first { $0.hasPrefix("https://") }
        XCTAssertNotNil(https)
        XCTAssertTrue(https!.hasSuffix("/oauth/account/redirect/ios/\(bundleId)"),
                      "expected raw-cased bundle id, got: \(https!)")
    }

    // MARK: - Path + availability gate

    func test_assetLinksRedirectPath_matchesHostedAASARoute() {
        XCTAssertEqual(assetLinksRedirectPath(bundleIdentifier: bundleId),
                       "/oauth/account/redirect/ios/\(bundleId)")
    }

    func test_isAssetLinksRedirectEnabled_isFalse_whenFlagOff() {
        XCTAssertFalse(isAssetLinksRedirectEnabled(useAssetLinks: false))
    }

    /// `ASWebAuthenticationSession.Callback.https` requires iOS 17.4, so the flag
    /// alone is not sufficient — below 17.4 the SDK must fall back.
    func test_isAssetLinksRedirectEnabled_honoursOSAvailability_whenFlagOn() {
        let enabled = isAssetLinksRedirectEnabled(useAssetLinks: true)
        if #available(iOS 17.4, *) {
            XCTAssertTrue(enabled, "should be enabled on iOS 17.4+ when the flag is on")
        } else {
            XCTAssertFalse(enabled, "must fall back to custom scheme below iOS 17.4")
        }
    }

    // MARK: - Callback matching
    //
    // `matchedGeneratedRedirectUri` now takes an explicit `useAssetLinks`
    // parameter (threaded through to `supportedGeneratedRedirectUris`), so these
    // cases no longer evaluate the `FronteggApp.shared.useAssetLinks` default
    // argument and no longer depend on another test having initialized the
    // singleton first.

    private func matched(_ url: String, useAssetLinks: Bool) -> String? {
        // Every argument is passed explicitly, including `rawBundleIdentifier` —
        // its default (`currentAppRawBundleIdentifier()`) reads
        // `FronteggApp.shared`, which traps on a missing Frontegg.plist if this
        // class is the first to touch the singleton.
        matchedGeneratedRedirectUri(
            URL(string: url)!,
            baseUrl: baseUrl,
            bundleIdentifier: lowerBundleId,
            useAssetLinks: useAssetLinks,
            rawBundleIdentifier: bundleId
        )
    }

    func test_matchedGeneratedRedirectUri_matchesAppLinkCallback_whenFlagOn() {
        XCTAssertEqual(
            matched(
                "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)?code=123",
                useAssetLinks: true
            ),
            "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)"
        )
    }

    /// The App-Link URI is only a candidate when the option is on — otherwise an
    /// https URL on that path is an intermediate redirect (magic link, invite,
    /// forgot password), not this app's OAuth callback.
    func test_matchedGeneratedRedirectUri_ignoresAppLinkCallback_whenFlagOff() {
        XCTAssertNil(
            matched(
                "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)?code=123",
                useAssetLinks: false
            )
        )
    }

    /// Custom-scheme callbacks keep matching after the flip, so callbacks issued
    /// before the option was enabled are not orphaned.
    func test_matchedGeneratedRedirectUri_stillMatchesCustomScheme_whenFlagOn() {
        XCTAssertEqual(
            matched(
                "\(lowerBundleId)://auth.example.com/ios/oauth/callback?code=123",
                useAssetLinks: true
            ),
            "\(lowerBundleId)://auth.example.com/ios/oauth/callback"
        )
    }

    /// A genuine intermediate redirect carries a trailing segment, so it must not
    /// be mistaken for the generated App-Link callback even with the flag on.
    func test_matchedGeneratedRedirectUri_ignoresIntermediateRedirect_whenFlagOn() {
        XCTAssertNil(
            matched(
                "https://auth.example.com/oauth/account/redirect/ios/\(bundleId)/google?code=123",
                useAssetLinks: true
            )
        )
    }
}
