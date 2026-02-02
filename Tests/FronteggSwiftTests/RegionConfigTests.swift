//
//  RegionConfigTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class RegionConfigTests: XCTestCase {
    
    // MARK: - Decoding Tests
    
    func test_decode_succeeds_withAllFields() throws {
        let regionDict: [String: Any] = [
            "key": "us-east",
            "baseUrl": "https://us-east.example.com",
            "clientId": "client-us-east",
            "applicationId": "app-123"
        ]
        
        let data = try TestDataFactory.jsonData(from: regionDict)
        let region = try JSONDecoder().decode(RegionConfig.self, from: data)
        
        XCTAssertEqual(region.key, "us-east")
        XCTAssertEqual(region.baseUrl, "https://us-east.example.com")
        XCTAssertEqual(region.clientId, "client-us-east")
        XCTAssertEqual(region.applicationId, "app-123")
    }
    
    func test_decode_succeeds_withMinimalFields() throws {
        let regionDict: [String: Any] = [
            "key": "eu",
            "baseUrl": "https://eu.example.com",
            "clientId": "client-eu"
        ]
        
        let data = try TestDataFactory.jsonData(from: regionDict)
        let region = try JSONDecoder().decode(RegionConfig.self, from: data)
        
        XCTAssertEqual(region.key, "eu")
        XCTAssertEqual(region.baseUrl, "https://eu.example.com")
        XCTAssertEqual(region.clientId, "client-eu")
        XCTAssertNil(region.applicationId)
    }
    
    func test_decode_throwsError_whenKeyMissing() {
        let regionDict: [String: Any] = [
            "baseUrl": "https://example.com",
            "clientId": "client-123"
        ]
        
        do {
            let data = try TestDataFactory.jsonData(from: regionDict)
            _ = try JSONDecoder().decode(RegionConfig.self, from: data)
            XCTFail("Expected decoding to fail")
        } catch {
            // Expected
        }
    }
    
    func test_decode_throwsError_whenBaseUrlMissing() {
        let regionDict: [String: Any] = [
            "key": "test",
            "clientId": "client-123"
        ]
        
        do {
            let data = try TestDataFactory.jsonData(from: regionDict)
            _ = try JSONDecoder().decode(RegionConfig.self, from: data)
            XCTFail("Expected decoding to fail")
        } catch {
            // Expected
        }
    }
    
    func test_decode_throwsError_whenClientIdMissing() {
        let regionDict: [String: Any] = [
            "key": "test",
            "baseUrl": "https://example.com"
        ]
        
        do {
            let data = try TestDataFactory.jsonData(from: regionDict)
            _ = try JSONDecoder().decode(RegionConfig.self, from: data)
            XCTFail("Expected decoding to fail")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Equality Tests
    
    func test_equality_returnsTrue_forIdenticalRegions() throws {
        let regionDict: [String: Any] = [
            "key": "same",
            "baseUrl": "https://same.example.com",
            "clientId": "same-client"
        ]
        let data = try TestDataFactory.jsonData(from: regionDict)
        
        let region1 = try JSONDecoder().decode(RegionConfig.self, from: data)
        let region2 = try JSONDecoder().decode(RegionConfig.self, from: data)
        
        XCTAssertEqual(region1, region2)
    }
    
    func test_equality_returnsFalse_forDifferentKeys() throws {
        let regionDict1: [String: Any] = [
            "key": "key1",
            "baseUrl": "https://example.com",
            "clientId": "client"
        ]
        let regionDict2: [String: Any] = [
            "key": "key2",
            "baseUrl": "https://example.com",
            "clientId": "client"
        ]
        
        let data1 = try TestDataFactory.jsonData(from: regionDict1)
        let data2 = try TestDataFactory.jsonData(from: regionDict2)
        
        let region1 = try JSONDecoder().decode(RegionConfig.self, from: data1)
        let region2 = try JSONDecoder().decode(RegionConfig.self, from: data2)
        
        XCTAssertNotEqual(region1, region2)
    }
    
    func test_equality_returnsFalse_forDifferentBaseUrls() throws {
        let regionDict1: [String: Any] = [
            "key": "key",
            "baseUrl": "https://example1.com",
            "clientId": "client"
        ]
        let regionDict2: [String: Any] = [
            "key": "key",
            "baseUrl": "https://example2.com",
            "clientId": "client"
        ]
        
        let data1 = try TestDataFactory.jsonData(from: regionDict1)
        let data2 = try TestDataFactory.jsonData(from: regionDict2)
        
        let region1 = try JSONDecoder().decode(RegionConfig.self, from: data1)
        let region2 = try JSONDecoder().decode(RegionConfig.self, from: data2)
        
        XCTAssertNotEqual(region1, region2)
    }
    
    func test_equality_returnsFalse_forDifferentClientIds() throws {
        let regionDict1: [String: Any] = [
            "key": "key",
            "baseUrl": "https://example.com",
            "clientId": "client1"
        ]
        let regionDict2: [String: Any] = [
            "key": "key",
            "baseUrl": "https://example.com",
            "clientId": "client2"
        ]
        
        let data1 = try TestDataFactory.jsonData(from: regionDict1)
        let data2 = try TestDataFactory.jsonData(from: regionDict2)
        
        let region1 = try JSONDecoder().decode(RegionConfig.self, from: data1)
        let region2 = try JSONDecoder().decode(RegionConfig.self, from: data2)
        
        XCTAssertNotEqual(region1, region2)
    }
    
    // MARK: - Identifiable Tests
    
    func test_identifiable_usesKeyAsId() throws {
        let regionDict: [String: Any] = [
            "key": "my-region-key",
            "baseUrl": "https://example.com",
            "clientId": "client"
        ]
        let data = try TestDataFactory.jsonData(from: regionDict)
        let region = try JSONDecoder().decode(RegionConfig.self, from: data)
        
        XCTAssertEqual(region.id, "my-region-key")
    }
    
    // MARK: - Hashable Tests
    
    func test_hashable_sameRegionsHaveSameHash() throws {
        let regionDict: [String: Any] = [
            "key": "hash-test",
            "baseUrl": "https://example.com",
            "clientId": "client"
        ]
        let data = try TestDataFactory.jsonData(from: regionDict)
        
        let region1 = try JSONDecoder().decode(RegionConfig.self, from: data)
        let region2 = try JSONDecoder().decode(RegionConfig.self, from: data)
        
        XCTAssertEqual(region1.hashValue, region2.hashValue)
    }
    
    func test_hashable_canBeUsedInSet() throws {
        let regionDict1: [String: Any] = [
            "key": "region1",
            "baseUrl": "https://example1.com",
            "clientId": "client1"
        ]
        let regionDict2: [String: Any] = [
            "key": "region2",
            "baseUrl": "https://example2.com",
            "clientId": "client2"
        ]
        
        let data1 = try TestDataFactory.jsonData(from: regionDict1)
        let data2 = try TestDataFactory.jsonData(from: regionDict2)
        
        let region1 = try JSONDecoder().decode(RegionConfig.self, from: data1)
        let region2 = try JSONDecoder().decode(RegionConfig.self, from: data2)
        
        var regionSet = Set<RegionConfig>()
        regionSet.insert(region1)
        regionSet.insert(region2)
        
        XCTAssertEqual(regionSet.count, 2)
    }
    
}
