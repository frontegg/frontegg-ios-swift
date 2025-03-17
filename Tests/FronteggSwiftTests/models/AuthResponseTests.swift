//
//  AuthResponseTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import XCTest
@testable import FronteggSwift

class AuthResponseTests: XCTestCase {
    let authResponseModel = AuthResponse(
        token_type: "Bearer",
        refresh_token: "Test Refresh Token",
        access_token: "Test Access Token",
        id_token: "Test Id Token"
    )
    
    let authResponseJson = """
{
    "token_type": "Bearer",
    "refresh_token": "Test Refresh Token",
    "access_token": "Test Access Token",
    "id_token": "Test Id Token"
}
"""
    
    
    func test_shouldDecodeJsonToModel () {
        let data = authResponseJson.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, authResponseModel)
    }
}
