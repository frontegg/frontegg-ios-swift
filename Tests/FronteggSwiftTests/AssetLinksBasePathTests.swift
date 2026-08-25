//
//  AssetLinksBasePathTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

/// Coverage for App-Link redirects on a base URL that carries a path (FR-26673).
///
/// A vendor can expose Frontegg under a path prefix on a shared domain -- an edge
/// worker translating `api.example.com/fe-auth/oauth/...` onto the real Frontegg
/// host, rewriting the association files it serves along the way, so the published
/// `apple-app-site-association` lists `/fe-auth/oauth/account/redirect/ios/...`.
///
/// The custom-scheme callback already carried that prefix. The App-Link one did
/// not, so with `useAssetLinks` on those vendors emitted a root-form URI that
/// matches neither their AASA nor the allow-list entry derived from it -- the OS
/// never hands the callback to the app, and the redirect dies in the browser on a
/// path the shared domain does not route to Frontegg.
final class AssetLinksBasePathTests: XCTestCase {

    private let prefixedBaseUrl = "https://api.example.com/fe-auth"
    private let bundleId = "com.example.App"
    private var lowerBundleId: String { bundleId.lowercased() }

    private func uris(baseUrl: String, useAssetLinks: Bool = true) -> [String] {
        supportedGeneratedRedirectUris(
            baseUrl: baseUrl,
            bundleIdentifier: lowerBundleId,
            useAssetLinks: useAssetLinks,
            rawBundleIdentifier: bundleId
        )
    }

    // MARK: - The prefix must reach the App-Link URI

    func test_appLinkRedirect_carriesTheBasePath_whenBaseUrlHasOne() {
        XCTAssertEqual(
            uris(baseUrl: prefixedBaseUrl).first,
            "https://api.example.com/fe-auth/oauth/account/redirect/ios/\(bundleId)",
            "the SDK must send the callback the vendor's association file actually publishes"
        )
    }

    /// The prefixed form is what a prefixed vendor publishes, but apps already in
    /// the field were issued the root form, and their allow-list entries still
    /// carry it. Dropping it would break those installs on upgrade.
    func test_appLinkRedirect_keepsRootFormAsAlias_whenBaseUrlHasBasePath() {
        XCTAssertTrue(
            uris(baseUrl: prefixedBaseUrl)
                .contains("https://api.example.com/oauth/account/redirect/ios/\(bundleId)"),
            "callbacks issued before this fix must keep matching"
        )
    }

    func test_appLinkRedirect_prefersThePrefixedFormOverTheRootAlias() throws {
        let uris = self.uris(baseUrl: prefixedBaseUrl)
        let prefixed = try XCTUnwrap(
            uris.firstIndex(of: "https://api.example.com/fe-auth/oauth/account/redirect/ios/\(bundleId)")
        )
        let root = try XCTUnwrap(
            uris.firstIndex(of: "https://api.example.com/oauth/account/redirect/ios/\(bundleId)")
        )

        XCTAssertLessThan(prefixed, root, "generateRedirectUri() takes .first, so the published form must lead")
    }

    // MARK: - Unprefixed vendors are unaffected

    func test_appLinkRedirect_emitsNoDuplicate_whenBaseUrlHasNoPath() {
        let uris = self.uris(baseUrl: "https://auth.example.com")
        let httpsUris = uris.filter { $0.hasPrefix("https://") }

        XCTAssertEqual(httpsUris, ["https://auth.example.com/oauth/account/redirect/ios/\(bundleId)"],
                       "a vendor without a base path must get exactly one https URI, as before")
    }

    func test_optionOff_emitsNoHttpsUri_evenWithBasePath() {
        XCTAssertFalse(
            uris(baseUrl: prefixedBaseUrl, useAssetLinks: false).contains { $0.hasPrefix("https://") },
            "the opt-in must stay inert when off"
        )
    }

    // MARK: - The callback matcher must accept what the SDK now sends

    func test_matchedGeneratedRedirectUri_acceptsThePrefixedAppLink() {
        let url = URL(string: "https://api.example.com/fe-auth/oauth/account/redirect/ios/\(bundleId)?code=abc")!

        XCTAssertNotNil(
            matchedGeneratedRedirectUri(url,
                                        baseUrl: prefixedBaseUrl,
                                        bundleIdentifier: lowerBundleId,
                                        useAssetLinks: true,
                                        rawBundleIdentifier: bundleId),
            "the SDK must recognise the callback it now generates"
        )
    }

    func test_matchedGeneratedRedirectUri_stillAcceptsTheRootAlias() {
        let url = URL(string: "https://api.example.com/oauth/account/redirect/ios/\(bundleId)?code=abc")!

        XCTAssertNotNil(
            matchedGeneratedRedirectUri(url,
                                        baseUrl: prefixedBaseUrl,
                                        bundleIdentifier: lowerBundleId,
                                        useAssetLinks: true,
                                        rawBundleIdentifier: bundleId)
        )
    }
}
