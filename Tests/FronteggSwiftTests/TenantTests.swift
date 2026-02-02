//
//  TenantTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class TenantTests: XCTestCase {
    
    // MARK: - Decoding Tests
    
    func test_decode_succeeds_withAllFields() throws {
        let tenantDict = TestDataFactory.makeTenant(
            id: "tenant-abc",
            name: "Acme Corp",
            creatorEmail: "admin@acme.com",
            creatorName: "Admin User",
            tenantId: "tenant-abc",
            createdAt: "2024-01-15T10:30:00.000Z",
            updatedAt: "2024-06-20T15:45:00.000Z",
            isReseller: true,
            metadata: "{\"plan\":\"enterprise\"}",
            vendorId: "vendor-xyz",
            website: "https://acme.com"
        )
        
        let data = try TestDataFactory.jsonData(from: tenantDict)
        let tenant = try JSONDecoder().decode(Tenant.self, from: data)
        
        XCTAssertEqual(tenant.id, "tenant-abc")
        XCTAssertEqual(tenant.name, "Acme Corp")
        XCTAssertEqual(tenant.creatorEmail, "admin@acme.com")
        XCTAssertEqual(tenant.creatorName, "Admin User")
        XCTAssertEqual(tenant.tenantId, "tenant-abc")
        XCTAssertEqual(tenant.createdAt, "2024-01-15T10:30:00.000Z")
        XCTAssertEqual(tenant.updatedAt, "2024-06-20T15:45:00.000Z")
        XCTAssertEqual(tenant.isReseller, true)
        XCTAssertEqual(tenant.metadata, "{\"plan\":\"enterprise\"}")
        XCTAssertEqual(tenant.vendorId, "vendor-xyz")
        XCTAssertEqual(tenant.website, "https://acme.com")
    }
    
    func test_decode_succeeds_withMinimalFields() throws {
        // Only required fields, no optional ones
        var tenantDict = TestDataFactory.makeTenant()
        tenantDict.removeValue(forKey: "creatorEmail")
        tenantDict.removeValue(forKey: "creatorName")
        tenantDict.removeValue(forKey: "website")
        
        let data = try TestDataFactory.jsonData(from: tenantDict)
        let tenant = try JSONDecoder().decode(Tenant.self, from: data)
        
        XCTAssertEqual(tenant.id, "tenant-123")
        XCTAssertEqual(tenant.name, "Test Tenant")
        XCTAssertNil(tenant.creatorEmail)
        XCTAssertNil(tenant.creatorName)
        XCTAssertNil(tenant.website)
    }
    
    func test_decode_handlesResellerFlagCorrectly() throws {
        let resellerTenant = TestDataFactory.makeTenant(isReseller: true)
        let regularTenant = TestDataFactory.makeTenant(isReseller: false)
        
        let resellerData = try TestDataFactory.jsonData(from: resellerTenant)
        let regularData = try TestDataFactory.jsonData(from: regularTenant)
        
        let decodedReseller = try JSONDecoder().decode(Tenant.self, from: resellerData)
        let decodedRegular = try JSONDecoder().decode(Tenant.self, from: regularData)
        
        XCTAssertTrue(decodedReseller.isReseller)
        XCTAssertFalse(decodedRegular.isReseller)
    }
    
    // MARK: - Encoding Tests
    
    func test_encode_succeeds() throws {
        let tenantDict = TestDataFactory.makeTenant()
        let data = try TestDataFactory.jsonData(from: tenantDict)
        let tenant = try JSONDecoder().decode(Tenant.self, from: data)
        
        // Encode the tenant back
        let encodedData = try JSONEncoder().encode(tenant)
        
        // Decode again to verify roundtrip
        let decodedTenant = try JSONDecoder().decode(Tenant.self, from: encodedData)
        XCTAssertEqual(tenant, decodedTenant)
    }
    
    // MARK: - Equality Tests
    
    func test_equality_returnsTrue_forIdenticalTenants() throws {
        let tenantDict = TestDataFactory.makeTenant(id: "same-id", name: "Same Name")
        let data = try TestDataFactory.jsonData(from: tenantDict)
        
        let tenant1 = try JSONDecoder().decode(Tenant.self, from: data)
        let tenant2 = try JSONDecoder().decode(Tenant.self, from: data)
        
        XCTAssertEqual(tenant1, tenant2)
    }
    
    func test_equality_returnsFalse_forDifferentIds() throws {
        let tenantDict1 = TestDataFactory.makeTenant(id: "tenant-1")
        let tenantDict2 = TestDataFactory.makeTenant(id: "tenant-2")
        
        let data1 = try TestDataFactory.jsonData(from: tenantDict1)
        let data2 = try TestDataFactory.jsonData(from: tenantDict2)
        
        let tenant1 = try JSONDecoder().decode(Tenant.self, from: data1)
        let tenant2 = try JSONDecoder().decode(Tenant.self, from: data2)
        
        XCTAssertNotEqual(tenant1, tenant2)
    }
    
    func test_equality_returnsFalse_forDifferentNames() throws {
        let tenantDict1 = TestDataFactory.makeTenant(name: "Tenant A")
        let tenantDict2 = TestDataFactory.makeTenant(name: "Tenant B")
        
        let data1 = try TestDataFactory.jsonData(from: tenantDict1)
        let data2 = try TestDataFactory.jsonData(from: tenantDict2)
        
        let tenant1 = try JSONDecoder().decode(Tenant.self, from: data1)
        let tenant2 = try JSONDecoder().decode(Tenant.self, from: data2)
        
        XCTAssertNotEqual(tenant1, tenant2)
    }
    
    func test_equality_returnsFalse_forDifferentVendorIds() throws {
        let tenantDict1 = TestDataFactory.makeTenant(vendorId: "vendor-1")
        let tenantDict2 = TestDataFactory.makeTenant(vendorId: "vendor-2")
        
        let data1 = try TestDataFactory.jsonData(from: tenantDict1)
        let data2 = try TestDataFactory.jsonData(from: tenantDict2)
        
        let tenant1 = try JSONDecoder().decode(Tenant.self, from: data1)
        let tenant2 = try JSONDecoder().decode(Tenant.self, from: data2)
        
        XCTAssertNotEqual(tenant1, tenant2)
    }
}
