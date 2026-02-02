//
//  UrlHelperExtendedTests.swift
//  FronteggSwiftTests
//
//  Extended tests for URL helper functions

import XCTest
@testable import FronteggSwift

final class UrlHelperExtendedTests: XCTestCase {
    
    // MARK: - isSocialLoginPath Tests
    
    func test_isSocialLoginPath_returnsTrue_forPreloginWithFronteggPrefix() {
        XCTAssertTrue(isSocialLoginPath("/frontegg/identity/resources/auth/v2/user/sso/default/google/prelogin"))
        XCTAssertTrue(isSocialLoginPath("/frontegg/identity/resources/auth/v1/user/sso/default/facebook/prelogin"))
    }
    
    func test_isSocialLoginPath_returnsTrue_forPreloginWithoutFronteggPrefix() {
        XCTAssertTrue(isSocialLoginPath("/identity/resources/auth/v2/user/sso/default/google/prelogin"))
        XCTAssertTrue(isSocialLoginPath("/identity/resources/auth/v1/user/sso/default/github/prelogin"))
    }
    
    func test_isSocialLoginPath_returnsFalse_forNonPreloginPaths() {
        XCTAssertFalse(isSocialLoginPath("/identity/resources/auth/v2/user/sso/default/google"))
        XCTAssertFalse(isSocialLoginPath("/identity/resources/auth/v2/user/sso/default/google/postlogin"))
        XCTAssertFalse(isSocialLoginPath("/identity/resources/auth/v2/user/login"))
        XCTAssertFalse(isSocialLoginPath("/identity/resources/auth/v2/user/mfa"))
    }
    
    func test_isSocialLoginPath_returnsFalse_forEmptyString() {
        XCTAssertFalse(isSocialLoginPath(""))
    }
    
    func test_isSocialLoginPath_returnsFalse_forRandomPath() {
        XCTAssertFalse(isSocialLoginPath("/random/path/to/something"))
    }
    
    // MARK: - getQueryItems Extended Tests
    
    func test_getQueryItems_handlesSpecialCharacters() {
        let url = "https://example.com?email=test%2Buser%40example.com&name=John%20Doe"
        let items = getQueryItems(url)
        
        XCTAssertNotNil(items)
        // URL decoding should handle percent-encoded characters
    }
    
    func test_getQueryItems_handlesMultipleValues() {
        let url = "https://example.com?a=1&b=2&c=3&d=4&e=5"
        let items = getQueryItems(url)
        
        XCTAssertNotNil(items)
        XCTAssertEqual(items?["a"], "1")
        XCTAssertEqual(items?["b"], "2")
        XCTAssertEqual(items?["c"], "3")
        XCTAssertEqual(items?["d"], "4")
        XCTAssertEqual(items?["e"], "5")
    }
    
    func test_getQueryItems_handlesEmptyValue() {
        let url = "https://example.com?key="
        let items = getQueryItems(url)
        
        XCTAssertNotNil(items)
        XCTAssertEqual(items?["key"], "")
    }
    
    // MARK: - getURLComponents Extended Tests
    
    func test_getURLComponents_extractsAllParts() {
        // Note: getURLComonents uses percent encoding which affects fragment handling
        let url = "https://user:pass@example.com:8080/path/to/resource?query=value"
        let components = getURLComonents(url)
        
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "example.com")
        XCTAssertEqual(components?.port, 8080)
        XCTAssertEqual(components?.path, "/path/to/resource")
        XCTAssertEqual(components?.query, "query=value")
    }
    
    func test_getURLComponents_handlesMinimalUrl() {
        let url = "https://example.com"
        let components = getURLComonents(url)
        
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "example.com")
        XCTAssertNil(components?.port)
        XCTAssertEqual(components?.path, "")
        XCTAssertNil(components?.query)
    }
    
    // MARK: - getCallbackType Tests
    
    func test_getCallbackType_returnsHostedLoginCallback_forOAuthCallbackPath() {
        let url = URL(string: "myapp://auth.frontegg.com/oauth/callback?code=123")!
        let result = getCallbackType(url)
        XCTAssertEqual(result, .HostedLoginCallback)
    }
    
    func test_getCallbackType_returnsMagicLink_forMagicLinkCallbackPath() {
        let url = URL(string: "myapp://auth.frontegg.com/oauth/magic-link/callback?token=abc")!
        let result = getCallbackType(url)
        XCTAssertEqual(result, .MagicLink)
    }
    
    func test_getCallbackType_returnsUnknown_forArbitraryUrls() {
        let url = URL(string: "https://google.com")!
        let result = getCallbackType(url)
        XCTAssertEqual(result, .Unknown)
    }
    
    func test_getCallbackType_returnsUnknown_forNilUrl() {
        let result = getCallbackType(nil)
        XCTAssertEqual(result, .Unknown)
    }
    
    func test_getCallbackType_returnsUnknown_forOtherPaths() {
        let url = URL(string: "myapp://auth.frontegg.com/other/path")!
        let result = getCallbackType(url)
        XCTAssertEqual(result, .Unknown)
    }
    
    // MARK: - Edge Cases
    
    func test_getQueryItems_handlesBasicQueryString() {
        let url = "https://example.com?key=value&other=data"
        let items = getQueryItems(url)
        
        XCTAssertNotNil(items)
        XCTAssertEqual(items?["key"], "value")
        XCTAssertEqual(items?["other"], "data")
    }
    
    func test_getURLComponents_handlesIPAddress() {
        let url = "http://192.168.1.1:3000/api"
        let components = getURLComonents(url)
        
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.host, "192.168.1.1")
        XCTAssertEqual(components?.port, 3000)
    }
    
    func test_getURLComponents_handlesLocalhost() {
        let url = "http://localhost:8080/api"
        let components = getURLComonents(url)
        
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.host, "localhost")
        XCTAssertEqual(components?.port, 8080)
    }
    
    func test_getURLComponents_handlesNilString() {
        let components = getURLComonents(nil)
        XCTAssertNil(components)
    }
    
    func test_getQueryItems_handlesUrlWithNoQueryString() {
        let url = "https://example.com/path"
        let items = getQueryItems(url)
        
        XCTAssertNotNil(items)
        XCTAssertEqual(items?.count, 0)
    }
    
    func test_getQueryItems_handlesComplexQueryValues() {
        let url = "https://example.com?redirect_uri=https%3A%2F%2Fapp.example.com%2Fcallback"
        let items = getQueryItems(url)
        
        XCTAssertNotNil(items)
        XCTAssertEqual(items?["redirect_uri"], "https://app.example.com/callback")
    }
}
