//
//  SocialLoginConfigTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class SocialLoginConfigTests: XCTestCase {
    
    // MARK: - SocialLoginOption Decoding Tests
    
    func test_socialLoginOption_decode_succeeds_withAllFields() throws {
        let optionDict = TestDataFactory.makeSocialLoginOption(
            type: "google",
            active: true,
            customised: true,
            clientId: "google-client-123",
            redirectUrl: "https://app.example.com/callback",
            redirectUrlPattern: "https://app.example.com/*",
            tenantId: "tenant-123",
            authorizationUrl: "https://accounts.google.com/oauth",
            backendRedirectUrl: "https://api.example.com/callback",
            options: [
                "verifyEmail": true,
                "verifyHostedDomain": false
            ],
            additionalScopes: ["drive.readonly", "calendar.events"]
        )
        
        let data = try TestDataFactory.jsonData(from: optionDict)
        let option = try JSONDecoder().decode(SocialLoginOption.self, from: data)
        
        XCTAssertEqual(option.type, "google")
        XCTAssertTrue(option.active)
        XCTAssertTrue(option.customised)
        XCTAssertEqual(option.clientId, "google-client-123")
        XCTAssertEqual(option.redirectUrl, "https://app.example.com/callback")
        XCTAssertEqual(option.redirectUrlPattern, "https://app.example.com/*")
        XCTAssertEqual(option.tenantId, "tenant-123")
        XCTAssertEqual(option.authorizationUrl, "https://accounts.google.com/oauth")
        XCTAssertEqual(option.backendRedirectUrl, "https://api.example.com/callback")
        XCTAssertEqual(option.additionalScopes, ["drive.readonly", "calendar.events"])
    }
    
    func test_socialLoginOption_decode_succeeds_withMinimalFields() throws {
        var optionDict = TestDataFactory.makeSocialLoginOption()
        optionDict.removeValue(forKey: "clientId")
        optionDict.removeValue(forKey: "tenantId")
        optionDict.removeValue(forKey: "authorizationUrl")
        optionDict.removeValue(forKey: "backendRedirectUrl")
        
        let data = try TestDataFactory.jsonData(from: optionDict)
        let option = try JSONDecoder().decode(SocialLoginOption.self, from: data)
        
        XCTAssertEqual(option.type, "google")
        XCTAssertNil(option.clientId)
        XCTAssertNil(option.tenantId)
        XCTAssertNil(option.authorizationUrl)
        XCTAssertNil(option.backendRedirectUrl)
    }
    
    func test_socialLoginOption_decode_handlesEmptyAdditionalScopes() throws {
        let optionDict = TestDataFactory.makeSocialLoginOption(additionalScopes: [])
        
        let data = try TestDataFactory.jsonData(from: optionDict)
        let option = try JSONDecoder().decode(SocialLoginOption.self, from: data)
        
        XCTAssertEqual(option.additionalScopes.count, 0)
    }
    
    // MARK: - SocialLoginConfig Tests
    
    func test_socialLoginConfig_initWithOptions_assignsCorrectly() throws {
        let googleOption = TestDataFactory.makeSocialLoginOption(type: "google", active: true)
        let facebookOption = TestDataFactory.makeSocialLoginOption(type: "facebook", active: true)
        let githubOption = TestDataFactory.makeSocialLoginOption(type: "github", active: false)
        let appleOption = TestDataFactory.makeSocialLoginOption(type: "apple", active: true)
        let microsoftOption = TestDataFactory.makeSocialLoginOption(type: "microsoft", active: true)
        let slackOption = TestDataFactory.makeSocialLoginOption(type: "slack", active: true)
        let linkedinOption = TestDataFactory.makeSocialLoginOption(type: "linkedin", active: true)
        
        let optionsData = try TestDataFactory.jsonData(from: [
            googleOption, facebookOption, githubOption, appleOption,
            microsoftOption, slackOption, linkedinOption
        ])
        let options = try JSONDecoder().decode([SocialLoginOption].self, from: optionsData)
        
        let config = SocialLoginConfig(options: options)
        
        XCTAssertNotNil(config.google)
        XCTAssertEqual(config.google?.type, "google")
        XCTAssertTrue(config.google?.active ?? false)
        
        XCTAssertNotNil(config.facebook)
        XCTAssertEqual(config.facebook?.type, "facebook")
        
        XCTAssertNotNil(config.github)
        XCTAssertFalse(config.github?.active ?? true)
        
        XCTAssertNotNil(config.apple)
        XCTAssertNotNil(config.microsoft)
        XCTAssertNotNil(config.slack)
        XCTAssertNotNil(config.linkedin)
    }
    
    func test_socialLoginConfig_initWithOptions_handlesUnknownTypes() throws {
        let unknownOption = TestDataFactory.makeSocialLoginOption(type: "unknown_provider", active: true)
        
        let optionsData = try TestDataFactory.jsonData(from: [unknownOption])
        let options = try JSONDecoder().decode([SocialLoginOption].self, from: optionsData)
        
        let config = SocialLoginConfig(options: options)
        
        // Unknown types should be ignored, all standard providers should be nil
        XCTAssertNil(config.google)
        XCTAssertNil(config.facebook)
        XCTAssertNil(config.github)
        XCTAssertNil(config.apple)
        XCTAssertNil(config.microsoft)
        XCTAssertNil(config.slack)
        XCTAssertNil(config.linkedin)
    }
    
    func test_socialLoginConfig_initWithOptions_handlesCaseInsensitivity() throws {
        let googleUpperCase = TestDataFactory.makeSocialLoginOption(type: "GOOGLE", active: true)
        let facebookMixedCase = TestDataFactory.makeSocialLoginOption(type: "FaceBook", active: true)
        
        let optionsData = try TestDataFactory.jsonData(from: [googleUpperCase, facebookMixedCase])
        let options = try JSONDecoder().decode([SocialLoginOption].self, from: optionsData)
        
        let config = SocialLoginConfig(options: options)
        
        XCTAssertNotNil(config.google)
        XCTAssertNotNil(config.facebook)
    }
    
    func test_socialLoginConfig_initWithEmptyOptions() throws {
        let config = SocialLoginConfig(options: [])
        
        XCTAssertNil(config.google)
        XCTAssertNil(config.facebook)
        XCTAssertNil(config.github)
        XCTAssertNil(config.apple)
        XCTAssertNil(config.microsoft)
        XCTAssertNil(config.slack)
        XCTAssertNil(config.linkedin)
    }
    
    func test_socialLoginConfig_toJsonString_returnsValidJson() throws {
        let googleOption = TestDataFactory.makeSocialLoginOption(type: "google", active: true)
        
        let optionsData = try TestDataFactory.jsonData(from: [googleOption])
        let options = try JSONDecoder().decode([SocialLoginOption].self, from: optionsData)
        
        let config = SocialLoginConfig(options: options)
        
        let jsonString = config.toJsonString()
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString?.contains("google") ?? false)
    }
    
    // MARK: - SocialLoginProvider Tests
    
    func test_socialLoginProvider_allCases() {
        let allProviders = SocialLoginProvider.allCases
        
        XCTAssertEqual(allProviders.count, 7)
        XCTAssertTrue(allProviders.contains(.facebook))
        XCTAssertTrue(allProviders.contains(.google))
        XCTAssertTrue(allProviders.contains(.microsoft))
        XCTAssertTrue(allProviders.contains(.github))
        XCTAssertTrue(allProviders.contains(.slack))
        XCTAssertTrue(allProviders.contains(.apple))
        XCTAssertTrue(allProviders.contains(.linkedin))
    }
    
    func test_socialLoginProvider_rawValues() {
        XCTAssertEqual(SocialLoginProvider.facebook.rawValue, "facebook")
        XCTAssertEqual(SocialLoginProvider.google.rawValue, "google")
        XCTAssertEqual(SocialLoginProvider.microsoft.rawValue, "microsoft")
        XCTAssertEqual(SocialLoginProvider.github.rawValue, "github")
        XCTAssertEqual(SocialLoginProvider.slack.rawValue, "slack")
        XCTAssertEqual(SocialLoginProvider.apple.rawValue, "apple")
        XCTAssertEqual(SocialLoginProvider.linkedin.rawValue, "linkedin")
    }
    
    func test_socialLoginProvider_codable() throws {
        let provider = SocialLoginProvider.google
        
        let encoded = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(SocialLoginProvider.self, from: encoded)
        
        XCTAssertEqual(provider, decoded)
    }
    
    // MARK: - SocialLoginAction Tests
    
    func test_socialLoginAction_allCases() {
        let allActions = SocialLoginAction.allCases
        
        XCTAssertEqual(allActions.count, 2)
        XCTAssertTrue(allActions.contains(.login))
        XCTAssertTrue(allActions.contains(.signUp))
    }
    
    func test_socialLoginAction_rawValues() {
        XCTAssertEqual(SocialLoginAction.login.rawValue, "login")
        XCTAssertEqual(SocialLoginAction.signUp.rawValue, "signUp")
    }
    
    func test_socialLoginAction_codable() throws {
        let action = SocialLoginAction.signUp
        
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(SocialLoginAction.self, from: encoded)
        
        XCTAssertEqual(action, decoded)
    }
    
    // MARK: - CustomSocialLoginProviderConfig Tests
    
    func test_customSocialLoginProviderConfig_decode() throws {
        let configDict: [String: Any] = [
            "id": "custom-123",
            "type": "custom",
            "clientId": "custom-client-id",
            "authorizationUrl": "https://custom.provider.com/oauth/authorize",
            "scopes": "openid profile email",
            "displayName": "Custom Provider",
            "active": true,
            "redirectUrl": "https://app.example.com/callback/custom"
        ]
        
        let data = try TestDataFactory.jsonData(from: configDict)
        let config = try JSONDecoder().decode(CustomSocialLoginProviderConfig.self, from: data)
        
        XCTAssertEqual(config.id, "custom-123")
        XCTAssertEqual(config.type, "custom")
        XCTAssertEqual(config.clientId, "custom-client-id")
        XCTAssertEqual(config.authorizationUrl, "https://custom.provider.com/oauth/authorize")
        XCTAssertEqual(config.scopes, "openid profile email")
        XCTAssertEqual(config.displayName, "Custom Provider")
        XCTAssertTrue(config.active)
        XCTAssertEqual(config.redirectUrl, "https://app.example.com/callback/custom")
    }
    
    // MARK: - CustomSocialLoginProvidersResponse Tests
    
    func test_customSocialLoginProvidersResponse_decode() throws {
        let responseDict: [String: Any] = [
            "providers": [
                [
                    "id": "provider-1",
                    "type": "custom",
                    "clientId": "client-1",
                    "authorizationUrl": "https://provider1.com/oauth",
                    "scopes": "openid",
                    "displayName": "Provider 1",
                    "active": true,
                    "redirectUrl": "https://example.com/callback"
                ],
                [
                    "id": "provider-2",
                    "type": "custom",
                    "clientId": "client-2",
                    "authorizationUrl": "https://provider2.com/oauth",
                    "scopes": "openid profile",
                    "displayName": "Provider 2",
                    "active": false,
                    "redirectUrl": "https://example.com/callback"
                ]
            ]
        ]
        
        let data = try TestDataFactory.jsonData(from: responseDict)
        let response = try JSONDecoder().decode(CustomSocialLoginProvidersResponse.self, from: data)
        
        XCTAssertEqual(response.providers.count, 2)
        XCTAssertEqual(response.providers[0].id, "provider-1")
        XCTAssertTrue(response.providers[0].active)
        XCTAssertEqual(response.providers[1].id, "provider-2")
        XCTAssertFalse(response.providers[1].active)
    }
    
    func test_customSocialLoginProvidersResponse_decodeEmptyProviders() throws {
        let responseDict: [String: Any] = [
            "providers": []
        ]
        
        let data = try TestDataFactory.jsonData(from: responseDict)
        let response = try JSONDecoder().decode(CustomSocialLoginProvidersResponse.self, from: data)
        
        XCTAssertEqual(response.providers.count, 0)
    }
}
