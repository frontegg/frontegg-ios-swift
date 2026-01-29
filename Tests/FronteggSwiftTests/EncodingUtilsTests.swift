//
//  EncodingUtilsTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class EncodingUtilsTests: XCTestCase {

    // MARK: - String.toDecodedData() (Base64URL decode)

    func test_toDecodedData_returnsData_whenValidBase64URL() {
        // "Hello" in Base64URL: SGVsbG8= -> SGVsbG8 (padding removed for Base64URL)
        let base64URL = "SGVsbG8"
        let data = base64URL.toDecodedData()
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func test_toDecodedData_handlesBase64URLReplacements() {
        // Base64URL uses - and _ instead of + and /
        let base64URL = "SGVsbG8-" // invalid but tests replacement
        let normalized = base64URL.replacingOccurrences(of: "-", with: "+")
        let data = base64URL.toDecodedData()
        // After replacement: SGVsbG8+ ; with padding: SGVsbG8+=
        XCTAssertNotNil(data)
    }

    func test_toDecodedData_returnsNil_whenInvalidBase64() {
        let invalid = "!!!"
        let data = invalid.toDecodedData()
        XCTAssertNil(data)
    }

    func test_toDecodedData_withPadding() {
        let withPadding = "SGVsbG8="
        let data = withPadding.toDecodedData()
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    // MARK: - Data.toEncodedBase64() (Base64URL encode)

    func test_toEncodedBase64_producesBase64URLFormat() {
        let original = "Hello".data(using: .utf8)!
        let encoded = original.toEncodedBase64()
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertTrue(encoded.contains("-") || encoded.contains("_") || encoded.count > 0)
    }

    func test_toEncodedBase64_roundtripWithToDecodedData() {
        let original = "Test data 123".data(using: .utf8)!
        let encoded = original.toEncodedBase64()
        let decoded = encoded.toDecodedData()
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - createRandomString

    func test_createRandomString_returnsCorrectLength() {
        let s = createRandomString(32)
        XCTAssertEqual(s.count, 32)
    }

    func test_createRandomString_defaultLength() {
        let s = createRandomString()
        XCTAssertEqual(s.count, 16)
    }

    func test_createRandomString_containsOnlyAlphanumeric() {
        let s = createRandomString(100)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        XCTAssertTrue(s.unicodeScalars.allSatisfy { allowed.contains($0) })
    }
}
