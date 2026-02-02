//
//  AuthResponseTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class AuthResponseTests: XCTestCase {

    func test_decodeAuthResponse_fromJSON() throws {
        let json = """
        {
            "token_type": "Bearer",
            "refresh_token": "refresh_abc",
            "access_token": "access_xyz",
            "id_token": "id_123"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        XCTAssertEqual(response.token_type, "Bearer")
        XCTAssertEqual(response.refresh_token, "refresh_abc")
        XCTAssertEqual(response.access_token, "access_xyz")
        XCTAssertEqual(response.id_token, "id_123")
    }
}
