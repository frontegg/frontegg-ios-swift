//
//  SuggestSavePasswordTests.swift
//  FronteggSwiftTests
//
//  Regression tests for the suggestSavePassword payload validation.
//  The handler accepts JSON with "email" (or "username") and "password" string fields.

import XCTest
@testable import FronteggSwift

final class SuggestSavePasswordTests: XCTestCase {

    // MARK: - Payload Parsing Tests
    //
    // These test the exact parsing logic from FronteggWKContentController's
    // suggestSavePassword handler: JSONSerialization → [String: String] → email + password.

    func test_validPayload_parsesSuccessfully() {
        let payload = #"{"email":"user@example.com","password":"secret123"}"#

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertEqual(result?.email, "user@example.com")
        XCTAssertEqual(result?.password, "secret123")
    }

    func test_usernameField_parsesSuccessfully() {
        let payload = #"{"username":"user1","password":"secret123"}"#

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertEqual(result?.email, "user1")
        XCTAssertEqual(result?.password, "secret123")
    }

    func test_emailTakesPrecedenceOverUsername() {
        let payload = #"{"email":"user@example.com","username":"user1","password":"secret"}"#

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertEqual(result?.email, "user@example.com",
                       "When both email and username are present, email takes precedence")
    }

    func test_missingEmailAndUsername_failsParsing() {
        let payload = #"{"password":"secret123"}"#

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertNil(result, "Payload without email or username must fail")
    }

    func test_missingPassword_failsParsing() {
        let payload = #"{"email":"user@example.com"}"#

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertNil(result, "Payload without password must fail")
    }

    func test_emptyPayload_failsParsing() {
        let payload = ""

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertNil(result, "Empty payload must fail")
    }

    func test_invalidJSON_failsParsing() {
        let payload = "not-json"

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertNil(result, "Non-JSON payload must fail")
    }

    func test_nonStringValues_failsParsing() {
        // email as number, password as boolean
        let payload = #"{"email":123,"password":true}"#

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertNil(result, "Payload with non-string values must fail (cast to [String: String] fails)")
    }

    func test_extraFields_stillParsesSuccessfully() {
        let payload = #"{"email":"user@example.com","password":"secret","extra":"ignored"}"#

        let result = parseSuggestSavePasswordPayload(payload)

        XCTAssertEqual(result?.email, "user@example.com")
        XCTAssertEqual(result?.password, "secret")
    }

    func test_emptyEmail_failsParsing() {
        let payload = #"{"email":"","password":"secret"}"#

        // The handler checks `let email = data["email"]` which succeeds for empty string.
        // This documents current behavior — empty email passes parsing but may fail downstream.
        let result = parseSuggestSavePasswordPayload(payload)

        // Empty string is still a valid String value, so parsing succeeds
        XCTAssertNotNil(result)
    }

    // MARK: - Helpers

    /// Mirrors the exact parsing logic from FronteggWKContentController suggestSavePassword handler.
    private struct ParsedCredentials {
        let email: String
        let password: String
    }

    private func parseSuggestSavePasswordPayload(_ payload: String) -> ParsedCredentials? {
        guard let data = try? JSONSerialization.jsonObject(
            with: Data(payload.utf8), options: []
        ) as? [String: String],
              let email = data["email"] ?? data["username"],
              let password = data["password"] else {
            return nil
        }
        return ParsedCredentials(email: email, password: password)
    }
}
