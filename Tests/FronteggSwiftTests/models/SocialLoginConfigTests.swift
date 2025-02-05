//
//  SocialLoginConfigTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import XCTest
@testable import FronteggSwift

class SocialLoginConfigTests: XCTestCase {
    let socialLoginOptionModel = SocialLoginOption(
        type: "google",
        active: true,
        customised: false,
        clientId: "google-client-id",
        redirectUrl: "https://example.com/redirect",
        redirectUrlPattern: "https://example.com/{id}",
        tenantId: "tenant-123",
        authorizationUrl: "https://example.com/auth",
        backendRedirectUrl: "https://example.com/backend-redirect",
        options: SocialLoginOptions(
            keyId: "key-123",
            teamId: "team-456",
            privateKey: "private-key-string",
            verifyEmail: true,
            verifyHostedDomain: false
        ),
        additionalScopes: ["email", "profile"]
    )
    
    let socialLoginOptionsModel = SocialLoginOptions(
        keyId: "key-123",
        teamId: "team-456",
        privateKey: "private-key-string",
        verifyEmail: true,
        verifyHostedDomain: false
    )
    
    
    let socialLoginConfigModel = SocialLoginConfig(
        options: [
            SocialLoginOption(
                type: "apple",
                active: true,
                customised: false,
                clientId: "apple-client-id",
                redirectUrl: "https://example.com/apple-redirect",
                redirectUrlPattern: "https://example.com/apple/{id}",
                tenantId: "tenant-789",
                authorizationUrl: "https://example.com/apple-auth",
                backendRedirectUrl: "https://example.com/apple-backend-redirect",
                options: SocialLoginOptions(
                    keyId: "key-789",
                    teamId: "team-101",
                    privateKey: "apple-private-key",
                    verifyEmail: true,
                    verifyHostedDomain: true
                ),
                additionalScopes: ["email", "name"]
            ),
            SocialLoginOption(
                type: "google",
                active: true,
                customised: false,
                clientId: "google-client-id",
                redirectUrl: "https://example.com/google-redirect",
                redirectUrlPattern: "https://example.com/google/{id}",
                tenantId: "tenant-123",
                authorizationUrl: "https://example.com/google-auth",
                backendRedirectUrl: "https://example.com/google-backend-redirect",
                options: SocialLoginOptions(
                    keyId: "key-123",
                    teamId: "team-456",
                    privateKey: "google-private-key",
                    verifyEmail: true,
                    verifyHostedDomain: false
                ),
                additionalScopes: ["email", "profile"]
            ),
            SocialLoginOption(
                type: "github",
                active: true,
                customised: true,
                clientId: "github-client-id",
                redirectUrl: "https://example.com/github-redirect",
                redirectUrlPattern: "https://example.com/github/{id}",
                tenantId: "tenant-456",
                authorizationUrl: "https://example.com/github-auth",
                backendRedirectUrl: "https://example.com/github-backend-redirect",
                options: SocialLoginOptions(
                  keyId: "key-321",
                  teamId: "team-654",
                  privateKey: "github-private-key",
                  verifyEmail: true,
                  verifyHostedDomain: true
                ),
                additionalScopes: ["repo", "user"]
            )
        ]
    )
    
    
    
    let socialLoginOptionJson = """
{
  "type": "google",
  "active": true,
  "customised": false,
  "clientId": "google-client-id",
  "redirectUrl": "https://example.com/redirect",
  "redirectUrlPattern": "https://example.com/{id}",
  "tenantId": "tenant-123",
  "authorizationUrl": "https://example.com/auth",
  "backendRedirectUrl": "https://example.com/backend-redirect",
  "options": {
    "keyId": "key-123",
    "teamId": "team-456",
    "privateKey": "private-key-string",
    "verifyEmail": true,
    "verifyHostedDomain": false
  },
  "additionalScopes": ["email", "profile"]
}

"""
    
    let socialLoginConfigJson = """
{
  "apple": {
    "type": "apple",
    "active": true,
    "customised": false,
    "clientId": "apple-client-id",
    "redirectUrl": "https://example.com/apple-redirect",
    "redirectUrlPattern": "https://example.com/apple/{id}",
    "tenantId": "tenant-789",
    "authorizationUrl": "https://example.com/apple-auth",
    "backendRedirectUrl": "https://example.com/apple-backend-redirect",
    "options": {
      "keyId": "key-789",
      "teamId": "team-101",
      "privateKey": "apple-private-key",
      "verifyEmail": true,
      "verifyHostedDomain": true
    },
    "additionalScopes": ["email", "name"]
  },
  "google": {
    "type": "google",
    "active": true,
    "customised": false,
    "clientId": "google-client-id",
    "redirectUrl": "https://example.com/google-redirect",
    "redirectUrlPattern": "https://example.com/google/{id}",
    "tenantId": "tenant-123",
    "authorizationUrl": "https://example.com/google-auth",
    "backendRedirectUrl": "https://example.com/google-backend-redirect",
    "options": {
      "keyId": "key-123",
      "teamId": "team-456",
      "privateKey": "google-private-key",
      "verifyEmail": true,
      "verifyHostedDomain": false
    },
    "additionalScopes": ["email", "profile"]
  },
  "github": {
    "type": "github",
    "active": true,
    "customised": true,
    "clientId": "github-client-id",
    "redirectUrl": "https://example.com/github-redirect",
    "redirectUrlPattern": "https://example.com/github/{id}",
    "tenantId": "tenant-456",
    "authorizationUrl": "https://example.com/github-auth",
    "backendRedirectUrl": "https://example.com/github-backend-redirect",
    "options": {
      "keyId": "key-321",
      "teamId": "team-654",
      "privateKey": "github-private-key",
      "verifyEmail": true,
      "verifyHostedDomain": true
    },
    "additionalScopes": ["repo", "user"]
  }
}
"""
    
    let socialLoginOptionsJson = """
{
  "keyId": "key-123",
  "teamId": "team-456",
  "privateKey": "private-key-string",
  "verifyEmail": true,
  "verifyHostedDomain": false
}
"""
    
    
    func test_shouldDecodeSocialLoginOptionJsonToModel () {
        let data = socialLoginOptionJson.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(SocialLoginOption.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, self.socialLoginOptionModel)
    }
    
    func test_shouldEncodeSocialLoginOptionModelToJson () {
        // Convert json string to dictionary
        guard let jsonData = socialLoginOptionJson.data(using: .utf8),
              let expectedMap = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            XCTFail("Failed to convert JSON string to dictionary")
            return
        }
        
        // Encode model to JSON
        guard let encodedData = try? JSONEncoder().encode(self.socialLoginOptionModel),
              let encodedMap = try? JSONSerialization.jsonObject(with: encodedData, options: []) as? [String: Any] else {
            XCTFail("Model should be encoded successfully")
            return
        }
        
        // Compare the dictionaries (maps)
        XCTAssertTrue(NSDictionary(dictionary:expectedMap).isEqual(to:encodedMap), "Encoded model does not match the expected JSON")
    }
    
    func test_shouldDecodeSocialLoginConfigJsonToModel () {
        let data = socialLoginConfigJson.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(SocialLoginConfig.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, self.socialLoginConfigModel)
    }
    
    func test_shouldEncodeSocialLoginConfigModelToJson () {
        // Convert json string to dictionary
        guard let jsonData = socialLoginConfigJson.data(using: .utf8),
              let expectedMap = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            XCTFail("Failed to convert JSON string to dictionary")
            return
        }
        
        // Encode model to JSON
        guard let encodedData = try? JSONEncoder().encode(self.socialLoginConfigModel),
              let encodedMap = try? JSONSerialization.jsonObject(with: encodedData, options: []) as? [String: Any] else {
            XCTFail("Model should be encoded successfully")
            return
        }
        
        // Compare the dictionaries (maps)
        XCTAssertTrue(NSDictionary(dictionary:expectedMap).isEqual(to:encodedMap), "Encoded model does not match the expected JSON")
    }
    
    func test_shouldDecodeSocialLoginOptionsJsonToModel () {
        let data = socialLoginOptionsJson.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(SocialLoginOptions.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, self.socialLoginOptionsModel)
    }
    
    func test_shouldEncodeSocialLoginOptionsModelToJson () {
        // Convert json string to dictionary
        guard let jsonData = socialLoginOptionsJson.data(using: .utf8),
              let expectedMap = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            XCTFail("Failed to convert JSON string to dictionary")
            return
        }
        
        // Encode model to JSON
        guard let encodedData = try? JSONEncoder().encode(self.socialLoginOptionsModel),
              let encodedMap = try? JSONSerialization.jsonObject(with: encodedData, options: []) as? [String: Any] else {
            XCTFail("Model should be encoded successfully")
            return
        }
        
        // Compare the dictionaries (maps)
        XCTAssertTrue(NSDictionary(dictionary:expectedMap).isEqual(to:encodedMap), "Encoded model does not match the expected JSON")
    }
}
