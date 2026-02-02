//
//  UserRolePermissionTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class UserRolePermissionTests: XCTestCase {
    
    // MARK: - Decoding Tests
    
    func test_decode_succeeds_withAllFields() throws {
        let permDict = TestDataFactory.makeUserRolePermission(
            id: "perm-xyz",
            key: "manage:settings",
            name: "Manage Settings",
            description: "Can manage application settings",
            categoryId: "settings-cat",
            fePermission: true,
            createdAt: "2024-01-01T00:00:00.000Z",
            updatedAt: "2024-06-15T12:00:00.000Z"
        )
        
        let data = try TestDataFactory.jsonData(from: permDict)
        let perm = try JSONDecoder().decode(UserRolePermission.self, from: data)
        
        XCTAssertEqual(perm.id, "perm-xyz")
        XCTAssertEqual(perm.key, "manage:settings")
        XCTAssertEqual(perm.name, "Manage Settings")
        XCTAssertEqual(perm.description, "Can manage application settings")
        XCTAssertEqual(perm.categoryId, "settings-cat")
        XCTAssertEqual(perm.fePermission, true)
        XCTAssertEqual(perm.createdAt, "2024-01-01T00:00:00.000Z")
        XCTAssertEqual(perm.updatedAt, "2024-06-15T12:00:00.000Z")
    }
    
    func test_decode_succeeds_withMinimalFields() throws {
        var permDict = TestDataFactory.makeUserRolePermission()
        permDict.removeValue(forKey: "description")
        
        let data = try TestDataFactory.jsonData(from: permDict)
        let perm = try JSONDecoder().decode(UserRolePermission.self, from: data)
        
        XCTAssertEqual(perm.id, "perm-123")
        XCTAssertNil(perm.description)
    }
    
    func test_decode_handlesFePermissionFlag() throws {
        let fePermDict = TestDataFactory.makeUserRolePermission(fePermission: true)
        let customPermDict = TestDataFactory.makeUserRolePermission(fePermission: false)
        
        let feData = try TestDataFactory.jsonData(from: fePermDict)
        let customData = try TestDataFactory.jsonData(from: customPermDict)
        
        let decodedFe = try JSONDecoder().decode(UserRolePermission.self, from: feData)
        let decodedCustom = try JSONDecoder().decode(UserRolePermission.self, from: customData)
        
        XCTAssertTrue(decodedFe.fePermission)
        XCTAssertFalse(decodedCustom.fePermission)
    }
    
    // MARK: - Encoding Tests
    
    func test_encode_succeeds() throws {
        let permDict = TestDataFactory.makeUserRolePermission()
        let data = try TestDataFactory.jsonData(from: permDict)
        let perm = try JSONDecoder().decode(UserRolePermission.self, from: data)
        
        // Encode the permission back
        let encodedData = try JSONEncoder().encode(perm)
        
        // Decode again to verify roundtrip
        let decodedPerm = try JSONDecoder().decode(UserRolePermission.self, from: encodedData)
        XCTAssertEqual(perm, decodedPerm)
    }
    
    // MARK: - Equality Tests
    
    func test_equality_returnsTrue_forIdenticalPermissions() throws {
        let permDict = TestDataFactory.makeUserRolePermission(id: "same-id", key: "same:key")
        let data = try TestDataFactory.jsonData(from: permDict)
        
        let perm1 = try JSONDecoder().decode(UserRolePermission.self, from: data)
        let perm2 = try JSONDecoder().decode(UserRolePermission.self, from: data)
        
        XCTAssertEqual(perm1, perm2)
    }
    
    func test_equality_returnsFalse_forDifferentIds() throws {
        let permDict1 = TestDataFactory.makeUserRolePermission(id: "perm-1")
        let permDict2 = TestDataFactory.makeUserRolePermission(id: "perm-2")
        
        let data1 = try TestDataFactory.jsonData(from: permDict1)
        let data2 = try TestDataFactory.jsonData(from: permDict2)
        
        let perm1 = try JSONDecoder().decode(UserRolePermission.self, from: data1)
        let perm2 = try JSONDecoder().decode(UserRolePermission.self, from: data2)
        
        XCTAssertNotEqual(perm1, perm2)
    }
    
    func test_equality_returnsFalse_forDifferentKeys() throws {
        let permDict1 = TestDataFactory.makeUserRolePermission(key: "read:users")
        let permDict2 = TestDataFactory.makeUserRolePermission(key: "write:users")
        
        let data1 = try TestDataFactory.jsonData(from: permDict1)
        let data2 = try TestDataFactory.jsonData(from: permDict2)
        
        let perm1 = try JSONDecoder().decode(UserRolePermission.self, from: data1)
        let perm2 = try JSONDecoder().decode(UserRolePermission.self, from: data2)
        
        XCTAssertNotEqual(perm1, perm2)
    }
    
    func test_equality_returnsFalse_forDifferentCategoryIds() throws {
        let permDict1 = TestDataFactory.makeUserRolePermission(categoryId: "cat-1")
        let permDict2 = TestDataFactory.makeUserRolePermission(categoryId: "cat-2")
        
        let data1 = try TestDataFactory.jsonData(from: permDict1)
        let data2 = try TestDataFactory.jsonData(from: permDict2)
        
        let perm1 = try JSONDecoder().decode(UserRolePermission.self, from: data1)
        let perm2 = try JSONDecoder().decode(UserRolePermission.self, from: data2)
        
        XCTAssertNotEqual(perm1, perm2)
    }
}
