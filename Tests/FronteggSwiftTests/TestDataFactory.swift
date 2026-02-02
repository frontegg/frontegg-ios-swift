//
//  TestDataFactory.swift
//  FronteggSwiftTests
//
//  Factory methods for creating test data across all tests

import Foundation
@testable import FronteggSwift

// MARK: - Test Data Factory

enum TestDataFactory {
    
    // MARK: - User Role Permission
    
    static func makeUserRolePermission(
        id: String = "perm-123",
        key: String = "read:users",
        name: String = "Read Users",
        description: String? = "Permission to read user data",
        categoryId: String = "cat-1",
        fePermission: Bool = false,
        createdAt: String = "2024-01-01T00:00:00.000Z",
        updatedAt: String = "2024-01-01T00:00:00.000Z"
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "key": key,
            "name": name,
            "categoryId": categoryId,
            "fePermission": fePermission,
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
        if let description = description {
            dict["description"] = description
        }
        return dict
    }
    
    // MARK: - User Role
    
    static func makeUserRole(
        id: String = "role-123",
        key: String = "admin",
        isDefault: Bool = false,
        name: String = "Admin",
        description: String? = "Administrator role",
        permissions: [String] = ["read:users", "write:users"],
        tenantId: String? = "tenant-123",
        vendorId: String = "vendor-123",
        createdAt: String = "2024-01-01T00:00:00.000Z",
        updatedAt: String = "2024-01-01T00:00:00.000Z"
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "key": key,
            "isDefault": isDefault,
            "name": name,
            "permissions": permissions,
            "vendorId": vendorId,
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
        if let description = description {
            dict["description"] = description
        }
        if let tenantId = tenantId {
            dict["tenantId"] = tenantId
        }
        return dict
    }
    
    // MARK: - Tenant
    
    static func makeTenant(
        id: String = "tenant-123",
        name: String = "Test Tenant",
        creatorEmail: String? = "creator@example.com",
        creatorName: String? = "Creator Name",
        tenantId: String = "tenant-123",
        createdAt: String = "2024-01-01T00:00:00.000Z",
        updatedAt: String = "2024-01-01T00:00:00.000Z",
        isReseller: Bool = false,
        metadata: String = "{}",
        vendorId: String = "vendor-123",
        website: String? = "https://example.com"
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "tenantId": tenantId,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "isReseller": isReseller,
            "metadata": metadata,
            "vendorId": vendorId
        ]
        if let creatorEmail = creatorEmail {
            dict["creatorEmail"] = creatorEmail
        }
        if let creatorName = creatorName {
            dict["creatorName"] = creatorName
        }
        if let website = website {
            dict["website"] = website
        }
        return dict
    }
    
    // MARK: - User
    
    static func makeUser(
        id: String = "user-123",
        email: String = "test@example.com",
        mfaEnrolled: Bool = false,
        name: String = "Test User",
        profilePictureUrl: String = "https://example.com/avatar.png",
        phoneNumber: String? = nil,
        profileImage: String? = nil,
        roles: [[String: Any]]? = nil,
        permissions: [[String: Any]]? = nil,
        tenantId: String = "tenant-123",
        tenantIds: [String] = ["tenant-123"],
        tenants: [[String: Any]]? = nil,
        activeTenant: [String: Any]? = nil,
        activatedForTenant: Bool = true,
        metadata: String? = nil,
        verified: Bool = true,
        superUser: Bool = false
    ) -> [String: Any] {
        let defaultRoles = roles ?? [makeUserRole()]
        let defaultPermissions = permissions ?? [makeUserRolePermission()]
        let defaultTenant = makeTenant(id: tenantId, tenantId: tenantId)
        let defaultTenants = tenants ?? [defaultTenant]
        let defaultActiveTenant = activeTenant ?? defaultTenant
        
        var dict: [String: Any] = [
            "id": id,
            "email": email,
            "mfaEnrolled": mfaEnrolled,
            "name": name,
            "profilePictureUrl": profilePictureUrl,
            "roles": defaultRoles,
            "permissions": defaultPermissions,
            "tenantId": tenantId,
            "tenantIds": tenantIds,
            "tenants": defaultTenants,
            "activeTenant": defaultActiveTenant,
            "activatedForTenant": activatedForTenant,
            "verified": verified,
            "superUser": superUser
        ]
        
        if let phoneNumber = phoneNumber {
            dict["phoneNumber"] = phoneNumber
        }
        if let profileImage = profileImage {
            dict["profileImage"] = profileImage
        }
        if let metadata = metadata {
            dict["metadata"] = metadata
        }
        
        return dict
    }
    
    // MARK: - Auth Response
    
    static func makeAuthResponse(
        tokenType: String = "Bearer",
        refreshToken: String = "refresh-token-123",
        accessToken: String = "access-token-123",
        idToken: String = "id-token-123"
    ) -> [String: Any] {
        return [
            "token_type": tokenType,
            "refresh_token": refreshToken,
            "access_token": accessToken,
            "id_token": idToken
        ]
    }
    
    // MARK: - Social Login Option
    
    static func makeSocialLoginOption(
        type: String = "google",
        active: Bool = true,
        customised: Bool = false,
        clientId: String? = "client-123",
        redirectUrl: String = "https://example.com/callback",
        redirectUrlPattern: String = "https://example.com/*",
        tenantId: String? = nil,
        authorizationUrl: String? = nil,
        backendRedirectUrl: String? = nil,
        options: [String: Any]? = nil,
        additionalScopes: [String] = []
    ) -> [String: Any] {
        let defaultOptions: [String: Any] = options ?? [
            "verifyEmail": false
        ]
        
        var dict: [String: Any] = [
            "type": type,
            "active": active,
            "customised": customised,
            "redirectUrl": redirectUrl,
            "redirectUrlPattern": redirectUrlPattern,
            "options": defaultOptions,
            "additionalScopes": additionalScopes
        ]
        
        if let clientId = clientId {
            dict["clientId"] = clientId
        }
        if let tenantId = tenantId {
            dict["tenantId"] = tenantId
        }
        if let authorizationUrl = authorizationUrl {
            dict["authorizationUrl"] = authorizationUrl
        }
        if let backendRedirectUrl = backendRedirectUrl {
            dict["backendRedirectUrl"] = backendRedirectUrl
        }
        
        return dict
    }
    
    // MARK: - Region Config
    
    static func makeRegionConfig(
        key: String = "us",
        baseUrl: String = "https://us.example.com",
        clientId: String = "client-123",
        applicationId: String? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "key": key,
            "baseUrl": baseUrl,
            "clientId": clientId
        ]
        if let applicationId = applicationId {
            dict["applicationId"] = applicationId
        }
        return dict
    }
    
    // MARK: - JWT Helpers
    
    /// Creates a minimal valid JWT (header.payload.signature) with base64url-encoded payload
    static func makeJWT(payloadDict: [String: Any]) throws -> String {
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" // standard {"alg":"HS256","typ":"JWT"}
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let signature = "fake_signature"
        return "\(header).\(payloadBase64).\(signature)"
    }
    
    /// Creates a JWT for step-up authentication testing
    static func makeStepUpJWT(
        authTime: Double? = nil,
        acr: String? = nil,
        amr: [String]? = nil,
        sub: String = "user-123"
    ) throws -> String {
        var payload: [String: Any] = ["sub": sub]
        if let authTime = authTime {
            payload["auth_time"] = authTime
        }
        if let acr = acr {
            payload["acr"] = acr
        }
        if let amr = amr {
            payload["amr"] = amr
        }
        return try makeJWT(payloadDict: payload)
    }
    
    // MARK: - JSON Data Conversion
    
    static func jsonData(from dict: [String: Any]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: dict, options: [])
    }
    
    static func jsonData(from array: [[String: Any]]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: array, options: [])
    }
}
