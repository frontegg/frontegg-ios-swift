//
//  UserRoleTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import XCTest
@testable import FronteggSwift

class UserRoleTests: XCTestCase {
    let model = UserRole(
        id: "role-001",
        key: "admin",
        isDefault: true,
        name: "Administrator",
        description: "Full access to all resources",
        permissions: ["create", "read", "update", "delete"],
        tenantId: "tenant-001",
        vendorId: "vendor-123",
        createdAt: "2025-02-05T10:00:00Z",
        updatedAt: "2025-02-05T10:30:00Z"
    )
    
    let json = """
{
    "id": "role-001",
    "key": "admin",
    "isDefault": true,
    "name": "Administrator",
    "description": "Full access to all resources",
    "permissions": ["create", "read", "update", "delete"],
    "tenantId": "tenant-001",
    "vendorId": "vendor-123",
    "createdAt": "2025-02-05T10:00:00Z",
    "updatedAt": "2025-02-05T10:30:00Z"
}
"""
    
    
    func test_shouldDecodeJsonToModel () {
        let data = json.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(UserRole.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, self.model)
    }
    
    func test_shouldEncodeModelToJson () {
        // Convert json string to dictionary
        guard let jsonData = json.data(using: .utf8),
              let expectedMap = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            XCTFail("Failed to convert JSON string to dictionary")
            return
        }
        
        // Encode model to JSON
        guard let encodedData = try? JSONEncoder().encode(self.model),
              let encodedMap = try? JSONSerialization.jsonObject(with: encodedData, options: []) as? [String: Any] else {
            XCTFail("Model should be encoded successfully")
            return
        }
        
        // Compare the dictionaries (maps)
        XCTAssertTrue(NSDictionary(dictionary:expectedMap).isEqual(to:encodedMap), "Encoded model does not match the expected JSON")
    }
}
