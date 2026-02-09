//
//  LoginPerAccountTests.swift
//  FronteggSwiftTests
//
//  Tests for login-per-account (custom login box): organization query parameter
//  and URL contract. Tests that call FronteggApp.shared or AuthorizeUrlGenerator.shared.generate()
//  require a host app with Frontegg.plist and are omitted in the package test target.
//

import XCTest
@testable import FronteggSwift

final class LoginPerAccountTests: XCTestCase {

    // MARK: - Query parameter constant

    func test_organizationQueryParameterName_isOrganization() {
        XCTAssertEqual(
            AuthorizeUrlGenerator.organizationQueryParameterName,
            "organization",
            "Authorize URL for login-per-account must use query param 'organization' per Frontegg docs"
        )
    }

    // MARK: - URL format (organization param)

    func test_authorizeUrlWithOrganization_parsesCorrectly() {
        let urlString = "https://auth.example.com/oauth/authorize?organization=acme&response_type=code"
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            XCTFail("Could not parse URL")
            return
        }
        let organization = queryItems.first(where: { $0.name == AuthorizeUrlGenerator.organizationQueryParameterName })?.value
        XCTAssertEqual(organization, "acme")
    }

    func test_authorizeUrlWithoutOrganization_hasNoOrganizationParam() {
        let urlString = "https://auth.example.com/oauth/authorize?response_type=code"
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            XCTFail("Could not parse URL")
            return
        }
        let organization = queryItems.first(where: { $0.name == AuthorizeUrlGenerator.organizationQueryParameterName })?.value
        XCTAssertNil(organization)
    }

    /// Verifies the expected query string shape when organization is present (contract test).
    func test_organizationQueryString_format() {
        let paramName = AuthorizeUrlGenerator.organizationQueryParameterName
        let alias = "my-tenant"
        var comps = URLComponents(string: "https://auth.example.com/oauth/authorize")!
        comps.queryItems = [URLQueryItem(name: paramName, value: alias)]
        guard let url = comps.url else {
            XCTFail("Could not build URL")
            return
        }
        XCTAssertTrue(url.absoluteString.contains("organization=my-tenant") || url.absoluteString.contains("organization=my%2Dtenant"))
    }
}
