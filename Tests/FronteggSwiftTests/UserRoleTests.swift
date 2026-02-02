//
//  UserRoleTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class UserRoleTests: XCTestCase {
    
    // MARK: - Decoding Tests
    
    func test_decode_succeeds_withAllFields() throws {
        let roleDict = TestDataFactory.makeUserRole(
            id: "role-abc",
            key: "super-admin",
            isDefault: true,
            name: "Super Admin",
            description: "Has all permissions",
            permissions: ["read:all", "write:all", "delete:all"],
            tenantId: "tenant-xyz",
            vendorId: "vendor-123",
            createdAt: "2024-01-01T00:00:00.000Z",
            updatedAt: "2024-06-15T12:00:00.000Z"
        )
        
        let data = try TestDataFactory.jsonData(from: roleDict)
        let role = try JSONDecoder().decode(UserRole.self, from: data)
        
        XCTAssertEqual(role.id, "role-abc")
        XCTAssertEqual(role.key, "super-admin")
        XCTAssertEqual(role.isDefault, true)
        XCTAssertEqual(role.name, "Super Admin")
        XCTAssertEqual(role.description, "Has all permissions")
        XCTAssertEqual(role.permissions, ["read:all", "write:all", "delete:all"])
        XCTAssertEqual(role.tenantId, "tenant-xyz")
        XCTAssertEqual(role.vendorId, "vendor-123")
        XCTAssertEqual(role.createdAt, "2024-01-01T00:00:00.000Z")
        XCTAssertEqual(role.updatedAt, "2024-06-15T12:00:00.000Z")
    }
    
    func test_decode_succeeds_withMinimalFields() throws {
        var roleDict = TestDataFactory.makeUserRole()
        roleDict.removeValue(forKey: "description")
        roleDict.removeValue(forKey: "tenantId")
        
        let data = try TestDataFactory.jsonData(from: roleDict)
        let role = try JSONDecoder().decode(UserRole.self, from: data)
        
        XCTAssertEqual(role.id, "role-123")
        XCTAssertNil(role.description)
        XCTAssertNil(role.tenantId)
    }
    
    func test_decode_handlesEmptyPermissions() throws {
        let roleDict = TestDataFactory.makeUserRole(permissions: [])
        
        let data = try TestDataFactory.jsonData(from: roleDict)
        let role = try JSONDecoder().decode(UserRole.self, from: data)
        
        XCTAssertEqual(role.permissions.count, 0)
    }
    
    func test_decode_handlesIsDefaultFlag() throws {
        let defaultRole = TestDataFactory.makeUserRole(isDefault: true)
        let nonDefaultRole = TestDataFactory.makeUserRole(isDefault: false)
        
        let defaultData = try TestDataFactory.jsonData(from: defaultRole)
        let nonDefaultData = try TestDataFactory.jsonData(from: nonDefaultRole)
        
        let decodedDefault = try JSONDecoder().decode(UserRole.self, from: defaultData)
        let decodedNonDefault = try JSONDecoder().decode(UserRole.self, from: nonDefaultData)
        
        XCTAssertTrue(decodedDefault.isDefault)
        XCTAssertFalse(decodedNonDefault.isDefault)
    }
    
    // MARK: - Encoding Tests
    
    func test_encode_succeeds() throws {
        let roleDict = TestDataFactory.makeUserRole()
        let data = try TestDataFactory.jsonData(from: roleDict)
        let role = try JSONDecoder().decode(UserRole.self, from: data)
        
        // Encode the role back
        let encodedData = try JSONEncoder().encode(role)
        
        // Decode again to verify roundtrip
        let decodedRole = try JSONDecoder().decode(UserRole.self, from: encodedData)
        XCTAssertEqual(role, decodedRole)
    }
    
    // MARK: - Equality Tests
    
    func test_equality_returnsTrue_forIdenticalRoles() throws {
        let roleDict = TestDataFactory.makeUserRole(id: "same-id", key: "same-key")
        let data = try TestDataFactory.jsonData(from: roleDict)
        
        let role1 = try JSONDecoder().decode(UserRole.self, from: data)
        let role2 = try JSONDecoder().decode(UserRole.self, from: data)
        
        XCTAssertEqual(role1, role2)
    }
    
    func test_equality_returnsFalse_forDifferentIds() throws {
        let roleDict1 = TestDataFactory.makeUserRole(id: "role-1")
        let roleDict2 = TestDataFactory.makeUserRole(id: "role-2")
        
        let data1 = try TestDataFactory.jsonData(from: roleDict1)
        let data2 = try TestDataFactory.jsonData(from: roleDict2)
        
        let role1 = try JSONDecoder().decode(UserRole.self, from: data1)
        let role2 = try JSONDecoder().decode(UserRole.self, from: data2)
        
        XCTAssertNotEqual(role1, role2)
    }
    
    func test_equality_returnsFalse_forDifferentPermissions() throws {
        let roleDict1 = TestDataFactory.makeUserRole(permissions: ["read:users"])
        let roleDict2 = TestDataFactory.makeUserRole(permissions: ["read:users", "write:users"])
        
        let data1 = try TestDataFactory.jsonData(from: roleDict1)
        let data2 = try TestDataFactory.jsonData(from: roleDict2)
        
        let role1 = try JSONDecoder().decode(UserRole.self, from: data1)
        let role2 = try JSONDecoder().decode(UserRole.self, from: data2)
        
        XCTAssertNotEqual(role1, role2)
    }
}
