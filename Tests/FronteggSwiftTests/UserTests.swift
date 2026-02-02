//
//  UserTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class UserTests: XCTestCase {
    
    // MARK: - Decoding Tests
    
    func test_decode_succeeds_withAllFields() throws {
        let userDict = TestDataFactory.makeUser(
            id: "user-456",
            email: "john@example.com",
            mfaEnrolled: true,
            name: "John Doe",
            profilePictureUrl: "https://cdn.example.com/john.png",
            phoneNumber: "+1234567890",
            profileImage: "base64image",
            tenantId: "tenant-789",
            tenantIds: ["tenant-789", "tenant-456"],
            activatedForTenant: true,
            metadata: "{\"key\":\"value\"}",
            verified: true,
            superUser: true
        )
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.id, "user-456")
        XCTAssertEqual(user.email, "john@example.com")
        XCTAssertEqual(user.mfaEnrolled, true)
        XCTAssertEqual(user.name, "John Doe")
        XCTAssertEqual(user.profilePictureUrl, "https://cdn.example.com/john.png")
        XCTAssertEqual(user.phoneNumber, "+1234567890")
        XCTAssertEqual(user.profileImage, "base64image")
        XCTAssertEqual(user.tenantId, "tenant-789")
        XCTAssertEqual(user.tenantIds, ["tenant-789", "tenant-456"])
        XCTAssertEqual(user.activatedForTenant, true)
        XCTAssertEqual(user.metadata, "{\"key\":\"value\"}")
        XCTAssertEqual(user.verified, true)
        XCTAssertEqual(user.superUser, true)
    }
    
    func test_decode_succeeds_withMinimalFields() throws {
        // Only required fields, no optional ones
        let userDict = TestDataFactory.makeUser()
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.id, "user-123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertNil(user.phoneNumber)
        XCTAssertNil(user.profileImage)
        XCTAssertNil(user.metadata)
    }
    
    func test_decode_defaultsMfaEnrolledToFalse_whenMissing() throws {
        var userDict = TestDataFactory.makeUser()
        userDict.removeValue(forKey: "mfaEnrolled")
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.mfaEnrolled, false)
    }
    
    func test_decode_defaultsActivatedForTenantToFalse_whenMissing() throws {
        var userDict = TestDataFactory.makeUser()
        userDict.removeValue(forKey: "activatedForTenant")
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.activatedForTenant, false)
    }
    
    func test_decode_defaultsVerifiedToFalse_whenMissing() throws {
        var userDict = TestDataFactory.makeUser()
        userDict.removeValue(forKey: "verified")
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.verified, false)
    }
    
    func test_decode_defaultsSuperUserToFalse_whenMissing() throws {
        var userDict = TestDataFactory.makeUser()
        userDict.removeValue(forKey: "superUser")
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.superUser, false)
    }
    
    func test_decode_parsesRolesCorrectly() throws {
        let customRole = TestDataFactory.makeUserRole(
            id: "role-custom",
            key: "manager",
            name: "Manager"
        )
        let userDict = TestDataFactory.makeUser(roles: [customRole])
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.roles.count, 1)
        XCTAssertEqual(user.roles[0].key, "manager")
        XCTAssertEqual(user.roles[0].name, "Manager")
    }
    
    func test_decode_parsesPermissionsCorrectly() throws {
        let customPermission = TestDataFactory.makeUserRolePermission(
            key: "delete:users",
            name: "Delete Users"
        )
        let userDict = TestDataFactory.makeUser(permissions: [customPermission])
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.permissions.count, 1)
        XCTAssertEqual(user.permissions[0].key, "delete:users")
        XCTAssertEqual(user.permissions[0].name, "Delete Users")
    }
    
    func test_decode_parsesTenantsCorrectly() throws {
        let tenant1 = TestDataFactory.makeTenant(id: "t1", name: "Tenant 1")
        let tenant2 = TestDataFactory.makeTenant(id: "t2", name: "Tenant 2")
        let userDict = TestDataFactory.makeUser(
            tenants: [tenant1, tenant2],
            activeTenant: tenant1
        )
        
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user.tenants.count, 2)
        XCTAssertEqual(user.tenants[0].name, "Tenant 1")
        XCTAssertEqual(user.tenants[1].name, "Tenant 2")
        XCTAssertEqual(user.activeTenant.id, "t1")
    }
    
    // MARK: - Encoding Tests
    
    func test_encode_succeeds() throws {
        let userDict = TestDataFactory.makeUser()
        let data = try TestDataFactory.jsonData(from: userDict)
        let user = try JSONDecoder().decode(User.self, from: data)
        
        // Encode the user back
        let encodedData = try JSONEncoder().encode(user)
        
        // Decode again to verify roundtrip
        let decodedUser = try JSONDecoder().decode(User.self, from: encodedData)
        XCTAssertEqual(user, decodedUser)
    }
    
    // MARK: - Equality Tests
    
    func test_equality_returnsTrue_forIdenticalUsers() throws {
        let userDict = TestDataFactory.makeUser(id: "same-id", email: "same@example.com")
        let data = try TestDataFactory.jsonData(from: userDict)
        
        let user1 = try JSONDecoder().decode(User.self, from: data)
        let user2 = try JSONDecoder().decode(User.self, from: data)
        
        XCTAssertEqual(user1, user2)
    }
    
    func test_equality_returnsFalse_forDifferentIds() throws {
        let userDict1 = TestDataFactory.makeUser(id: "user-1")
        let userDict2 = TestDataFactory.makeUser(id: "user-2")
        
        let data1 = try TestDataFactory.jsonData(from: userDict1)
        let data2 = try TestDataFactory.jsonData(from: userDict2)
        
        let user1 = try JSONDecoder().decode(User.self, from: data1)
        let user2 = try JSONDecoder().decode(User.self, from: data2)
        
        XCTAssertNotEqual(user1, user2)
    }
    
    func test_equality_returnsFalse_forDifferentEmails() throws {
        let userDict1 = TestDataFactory.makeUser(email: "a@example.com")
        let userDict2 = TestDataFactory.makeUser(email: "b@example.com")
        
        let data1 = try TestDataFactory.jsonData(from: userDict1)
        let data2 = try TestDataFactory.jsonData(from: userDict2)
        
        let user1 = try JSONDecoder().decode(User.self, from: data1)
        let user2 = try JSONDecoder().decode(User.self, from: data2)
        
        XCTAssertNotEqual(user1, user2)
    }
    
    func test_equality_returnsFalse_forDifferentMfaEnrolled() throws {
        let userDict1 = TestDataFactory.makeUser(mfaEnrolled: true)
        let userDict2 = TestDataFactory.makeUser(mfaEnrolled: false)
        
        let data1 = try TestDataFactory.jsonData(from: userDict1)
        let data2 = try TestDataFactory.jsonData(from: userDict2)
        
        let user1 = try JSONDecoder().decode(User.self, from: data1)
        let user2 = try JSONDecoder().decode(User.self, from: data2)
        
        XCTAssertNotEqual(user1, user2)
    }
    
    // MARK: - Dictionary Initializer Tests
    
    func test_initWithDictionary_succeeds() throws {
        let userDict = TestDataFactory.makeUser(
            id: "dict-user",
            email: "dict@example.com"
        )
        
        let user = try User(dictionary: userDict)
        
        XCTAssertEqual(user.id, "dict-user")
        XCTAssertEqual(user.email, "dict@example.com")
    }
    
    func test_initWithDictionary_throws_whenMissingRequiredFields() {
        let invalidDict: [String: Any] = [
            "id": "user-123"
            // Missing email and other required fields
        ]
        
        XCTAssertThrowsError(try User(dictionary: invalidDict))
    }
}
