//
//  JWTHelperTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class JWTHelperTests: XCTestCase {

    /// Creates a minimal valid JWT (header.payload.signature) with base64url-encoded payload
    private func makeJWT(payloadDict: [String: Any]) throws -> String {
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" // standard {"alg":"HS256","typ":"JWT"}
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let signature = "fake_signature"
        return "\(header).\(payloadBase64).\(signature)"
    }

    func test_decode_returnsPayload_whenValidJWT() throws {
        let payload: [String: Any] = ["sub": "user-123", "email": "test@example.com"]
        let jwt = try makeJWT(payloadDict: payload)
        let decoded = try JWTHelper.decode(jwtToken: jwt)
        XCTAssertEqual(decoded["sub"] as? String, "user-123")
        XCTAssertEqual(decoded["email"] as? String, "test@example.com")
    }

    func test_decode_throws_whenTooFewSegments() {
        XCTAssertThrowsError(try JWTHelper.decode(jwtToken: "only-one-part"))
    }

    func test_decode_throws_whenPayloadNotValidBase64() {
        let invalidJWT = "header.!!!.signature"
        XCTAssertThrowsError(try JWTHelper.decode(jwtToken: invalidJWT))
    }

    func test_decode_throws_whenPayloadNotValidJSON() {
        // Base64 of non-JSON: "not json"
        let badPayload = "bm90IGpzb24"
        let jwt = "eyJhbGciOiJIUzI1NiJ9.\(badPayload).sig"
        XCTAssertThrowsError(try JWTHelper.decode(jwtToken: jwt))
    }
}
