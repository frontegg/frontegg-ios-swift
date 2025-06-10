//
//  TenantTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import XCTest
@testable import FronteggSwift

class TenantTests: XCTestCase {
    let model = Tenant(
        id: "12345",
        name: "Acme Corp",
        creatorEmail: "creator@acmecorp.com",
        creatorName: "John Doe",
        tenantId: "tenant-001",
        createdAt: "2025-02-05T10:00:00Z",
        updatedAt: "2025-02-05T10:30:00Z",
        isReseller: false,
        metadata: "{}",
        vendorId: "vendor-123",
        website: "https://www.acmecorp.com"
    )
    
    let json = """
{
  "id": "12345",
  "name": "Acme Corp",
  "creatorEmail": "creator@acmecorp.com",
  "creatorName": "John Doe",
  "tenantId": "tenant-001",
  "createdAt": "2025-02-05T10:00:00Z",
  "updatedAt": "2025-02-05T10:30:00Z",
  "isReseller": false,
  "metadata": "{}",
  "vendorId": "vendor-123",
  "website": "https://www.acmecorp.com"
}
"""
    
    
    func test_shouldDecodeJsonToModel () {
        let data = json.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(Tenant.self, from: data) else {
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
