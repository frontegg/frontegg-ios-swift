//
//  UserTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import XCTest
@testable import FronteggSwift

class UserTests: XCTestCase {
    let userDictionary = [
        "id": "user-001",
        "email": "user@example.com",
        "mfaEnrolled": true,
        "name": "John Doe",
        "profilePictureUrl": "https://www.example.com/profile.jpg",
        "phoneNumber": "+1234567890",
        "profileImage": "https://www.example.com/image.jpg",
        "roles": [
            [
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
            ]
        ],
        "permissions": [
            [
                "id": "permission-001",
                "key": "admin_access",
                "name": "Admin Access",
                "description": "Allows full administrative privileges",
                "categoryId": "category-001",
                "fePermission": true,
                "createdAt": "2025-02-05T10:00:00Z",
                "updatedAt": "2025-02-05T10:30:00Z"
            ]
        ],
        "tenantId": "tenant-001",
        "tenantIds": ["tenant-001", "tenant-002"],
        "tenants": [
            [
                "id": "tenant-001",
                "name": "Tenant One",
                "creatorEmail": "creator@tenantone.com",
                "creatorName": "Alice",
                "tenantId": "tenant-001",
                "createdAt": "2025-01-01T10:00:00Z",
                "updatedAt": "2025-01-02T10:00:00Z",
                "isReseller": false,
                "metadata": "{}",
                "vendorId": "vendor-123",
                "website": "https://www.tenantone.com"
            ]
        ],
        "activeTenant": [
            "id": "tenant-001",
            "name": "Tenant One",
            "creatorEmail": "creator@tenantone.com",
            "creatorName": "Alice",
            "tenantId": "tenant-001",
            "createdAt": "2025-01-01T10:00:00Z",
            "updatedAt": "2025-01-02T10:00:00Z",
            "isReseller": false,
            "metadata": "{}",
            "vendorId": "vendor-123",
            "website": "https://www.tenantone.com"
        ],
        "activatedForTenant": true,
        "metadata": "{}",
        "verified": true,
        "superUser": false
    ] as [String : Any]

    
    let json = """
{
  "id": "user-001",
  "email": "user@example.com",
  "mfaEnrolled": true,
  "name": "John Doe",
  "profilePictureUrl": "https://www.example.com/profile.jpg",
  "phoneNumber": "+1234567890",
  "profileImage": "https://www.example.com/image.jpg",
  "roles": [
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
  ],
  "permissions": [
    {
      "id": "permission-001",
      "key": "admin_access",
      "name": "Admin Access",
      "description": "Allows full administrative privileges",
      "categoryId": "category-001",
      "fePermission": true,
      "createdAt": "2025-02-05T10:00:00Z",
      "updatedAt": "2025-02-05T10:30:00Z"
    }
  ],
  "tenantId": "tenant-001",
  "tenantIds": ["tenant-001", "tenant-002"],
  "tenants": [
    {
      "id": "tenant-001",
      "name": "Tenant One",
      "creatorEmail": "creator@tenantone.com",
      "creatorName": "Alice",
      "tenantId": "tenant-001",
      "createdAt": "2025-01-01T10:00:00Z",
      "updatedAt": "2025-01-02T10:00:00Z",
      "isReseller": false,
      "metadata": "{}",
      "vendorId": "vendor-123",
      "website": "https://www.tenantone.com"
    }
  ],
  "activeTenant": {
    "id": "tenant-001",
    "name": "Tenant One",
    "creatorEmail": "creator@tenantone.com",
    "creatorName": "Alice",
    "tenantId": "tenant-001",
    "createdAt": "2025-01-01T10:00:00Z",
    "updatedAt": "2025-01-02T10:00:00Z",
    "isReseller": false,
    "metadata": "{}",
    "vendorId": "vendor-123",
    "website": "https://www.tenantone.com"
  },
  "activatedForTenant": true,
  "metadata": "{}",
  "verified": true,
  "superUser": false
}
"""
    
    
    func test_shouldDecodeJsonToModel () {
        let data = json.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(User.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, try User(dictionary: self.userDictionary))
    }
    
    func test_shouldEncodeModelToJson () {
        // Convert json string to dictionary
        guard let jsonData = json.data(using: .utf8),
              let expectedMap = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            XCTFail("Failed to convert JSON string to dictionary")
            return
        }
        
        // Encode model to JSON
        let encodedMap = self.userDictionary
        
        // Compare the dictionaries (maps)
        XCTAssertTrue(NSDictionary(dictionary:expectedMap).isEqual(to:encodedMap), "Encoded model does not match the expected JSON")
    }
}
