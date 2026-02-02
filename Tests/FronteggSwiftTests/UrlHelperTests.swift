//
//  UrlHelperTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class UrlHelperTests: XCTestCase {

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
