//
//  mocker.swift
//  demo-test
//
//  Created by David Frontegg on 19/04/2023.
//

import Foundation

enum MockServerError: Error {
    case serverUnavailable(String)
    case invalidResponse(String)
    case networkError(Error)
}

enum MockMethod: String {
    case mockEmbeddedRefreshToken
    case mockSSOPrelogin
    case mockSSOAuthSamlCallback
    case mockSSOAuthOIDCCallback
    case mockHostedLoginAuthorize
    case mockHostedLoginRefreshToken
    case mockLogout
    case mockGetMe
    case mockGetMeTenants
    case mockAuthUser
    case mockSessionsConfigurations
    case mockOauthPostlogin
    case mockVendorConfig
    case mockPreLoginWithMagicLink
    case mockPostLoginWithMagicLink
}



enum MockDataMethod: String {
    case generateUser
}

struct Mocker {
    
    static var baseUrl:String!
    static var clientId:String!
    
    
    static func fronteggConfig(bundle:Bundle) throws -> (clientId: String, baseUrl: String) {
        
        guard let url = bundle.url(forResource: "FronteggTest", withExtension: "plist") else {
            print("Failed to locate plist file.")
            exit(1)
        }
        guard let plistData = try? Data(contentsOf: url) else {
            print("Failed to read plist file.")
            exit(1)
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            print("Failed to deserialize plist data.")
            exit(1)
        }
        
        guard let clientId = plist["clientId"] as? String, let baseUrl = plist["baseUrl"] as? String else {
            let errorMessage = "Frontegg.plist file at is missing 'clientId' and/or 'baseUrl' entries!"
            print(errorMessage)
            exit(1)
        }
        
        Mocker.baseUrl = baseUrl
        Mocker.clientId = clientId
        
        return (clientId: clientId, baseUrl: baseUrl)
    }
    
    static func getNgrokUrl() async throws -> String {
        let urlStr = "\(Mocker.baseUrl!)/ngrok"
        guard let url = URL(string: urlStr) else {
            throw MockServerError.invalidResponse("Invalid URL: \(urlStr)")
        }
        var request = URLRequest(url: url)
        request.setValue(Mocker.baseUrl!, forHTTPHeaderField: "Origin")
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw MockServerError.serverUnavailable("Mock server returned status \(httpResponse.statusCode) for \(urlStr)")
            }
            guard let result = String(data: data, encoding: .utf8) else {
                throw MockServerError.invalidResponse("Failed to decode response from \(urlStr)")
            }
            return result
        } catch {
            throw MockServerError.networkError(error)
        }
    }
    
    static func mockWithId(name: MockMethod, body: [String: Any?]) async throws -> String {
        let urlStr = "\(Mocker.baseUrl!)/mock/\(name.rawValue)"
        guard let url = URL(string: urlStr) else {
            throw MockServerError.invalidResponse("Invalid URL: \(urlStr)")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Mocker.baseUrl!, forHTTPHeaderField: "Origin")
        request.httpMethod = "POST"
        
        let json = try? JSONSerialization.data(withJSONObject: body)
        request.httpBody = json
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw MockServerError.serverUnavailable("Mock server returned status \(httpResponse.statusCode) for \(urlStr)")
            }
            guard let result = String(data: data, encoding: .utf8) else {
                throw MockServerError.invalidResponse("Failed to decode response from \(urlStr)")
            }
            return result
        } catch {
            throw MockServerError.networkError(error)
        }
    }
    static func mock(name: MockMethod, body: [String: Any?]) async throws {
        let id = try await mockWithId(name: name, body: body)
        print("Mock(\(name.rawValue)) => \(id)")
    }
    
    static func mockData(name: MockDataMethod, body: [Any]) async throws -> Any {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let jsonStr = String(data: jsonData, encoding: .utf8),
              let query = jsonStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw MockServerError.invalidResponse("Failed to encode request body")
        }
        
        let urlStr = "\(Mocker.baseUrl!)/faker/\(name.rawValue)?options=\(query)"
        print(urlStr)
        
        guard let url = URL(string: urlStr) else {
            throw MockServerError.invalidResponse("Invalid URL: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw MockServerError.serverUnavailable("Mock server returned status \(httpResponse.statusCode) for \(urlStr)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let result = json["data"] else {
                throw MockServerError.invalidResponse("Failed to parse response from \(urlStr)")
            }
            return result
        } catch {
            throw MockServerError.networkError(error)
        }
    }
    
    static func mockClearMocks() async throws {
        let urlStr = "\(Mocker.baseUrl!)/clear-mock"
        guard let url = URL(string: urlStr) else {
            throw MockServerError.invalidResponse("Invalid URL: \(urlStr)")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        request.httpMethod = "POST"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw MockServerError.serverUnavailable("Mock server returned status \(httpResponse.statusCode) for \(urlStr)")
            }
        } catch {
            throw MockServerError.networkError(error)
        }
    }
    
    
    static func mockSuccessPasswordLogin(_ oauthCode:String) async throws {
        guard let mockedUser = try await Mocker.mockData(name: .generateUser, body: [Mocker.clientId!, ["email":"test@frontegg.com"]]) as? [String: Any] else {
            throw MockServerError.invalidResponse("Failed to generate mock user")
        }
        
        let authUserOptions: [String: Any] = [
            "success":true,
            "user": mockedUser
        ]
        try await Mocker.mock(name: .mockAuthUser, body: ["options": authUserOptions])
        try await Mocker.mock(name: .mockHostedLoginRefreshToken, body: [
            "partialRequestBody": [:],
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        try await Mocker.mock(name: .mockEmbeddedRefreshToken, body: [
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        
        try await Mocker.mock(name: .mockGetMeTenants, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockGetMe, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockSessionsConfigurations, body: [:])
        
        try await Mocker.mock(name: .mockOauthPostlogin, body:[ "options": ["redirectUrl": "\(Mocker.baseUrl!)/oauth/mobile/callback?code=\(oauthCode)" ]])
        try await Mocker.mock(name: .mockLogout, body: [:])
    }
    
    
    
    static func mockSuccessSamlLogin(_ oauthCode:String) async throws {
        guard let mockedUser = try await Mocker.mockData(name: .generateUser, body: [Mocker.clientId!, ["email":"test@saml-domain.com"]]) as? [String: Any] else {
            throw MockServerError.invalidResponse("Failed to generate mock user")
        }
        
        try await Mocker.mock(name: .mockGetMeTenants, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockGetMe, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockSessionsConfigurations, body: [:])
        
        
        try await Mocker.mock(name: .mockSSOAuthSamlCallback, body: ["options":[
            "success": true,
            "baseUrl": Mocker.baseUrl!,
            "refreshTokenCookie": mockedUser["refreshTokenCookie"],
        ]])
        
        
        try await Mocker.mock(name: .mockEmbeddedRefreshToken, body: [
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        try await Mocker.mock(name: .mockHostedLoginRefreshToken, body: [
            "partialRequestBody": [:],
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        try await Mocker.mock(name: .mockOauthPostlogin, body:[ "options": ["redirectUrl": "\(Mocker.baseUrl!)/oauth/mobile/callback?code=\(oauthCode)" ]])
        try await Mocker.mock(name: .mockLogout, body: [:])
    }
    
    
    static func mockSuccessOidcLogin(_ oauthCode:String) async throws {
        guard let mockedUser = try await Mocker.mockData(name: .generateUser, body: [Mocker.clientId!, ["email":"test@oidc-domain.com"]]) as? [String: Any] else {
            throw MockServerError.invalidResponse("Failed to generate mock user")
        }
        
        try await Mocker.mock(name: .mockGetMeTenants, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockGetMe, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockSessionsConfigurations, body: [:])
        
        try await Mocker.mock(name: .mockSSOAuthOIDCCallback, body: ["options":[
            "success": true,
            "baseUrl": Mocker.baseUrl!,
            "refreshTokenCookie": mockedUser["refreshTokenCookie"],
        ]])
        
        try await Mocker.mock(name: .mockEmbeddedRefreshToken, body: [
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        try await Mocker.mock(name: .mockHostedLoginRefreshToken, body: [
            "partialRequestBody": [:],
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        try await Mocker.mock(name: .mockOauthPostlogin, body:[ "options": ["redirectUrl": "\(Mocker.baseUrl!)/oauth/mobile/callback?code=\(oauthCode)" ]])
        try await Mocker.mock(name: .mockLogout, body: [:])
    }
    
    
    static func mockSuccessMagicLink(_ oauthCode:String) async throws -> String {
        let token = UUID().uuidString
        let ngrokUrl = try await Mocker.getNgrokUrl()
        
        guard let mockedUser = try await Mocker.mockData(name: .generateUser, body: [Mocker.clientId!, ["email":"test@frontegg.com"]]) as? [String: Any] else {
            throw MockServerError.invalidResponse("Failed to generate mock user")
        }
        
        let authUserOptions: [String: Any] = [
            "success":true,
            "user": mockedUser
        ]
        
        try await Mocker.mock(name: .mockPostLoginWithMagicLink, body: [
            "options": authUserOptions,
            "requestParitalBody":["token": token]
        ])
        
        try await Mocker.mock(name: .mockGetMeTenants, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockGetMe, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockSessionsConfigurations, body: [:])
        
        
        try await Mocker.mock(name: .mockEmbeddedRefreshToken, body: [
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        
        try await Mocker.mock(name: .mockHostedLoginRefreshToken, body: [
            "partialRequestBody": [:],
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        try await Mocker.mock(name: .mockOauthPostlogin, body:[ "options": ["redirectUrl": "\(Mocker.baseUrl!)/oauth/mobile/callback?code=\(oauthCode)" ]])
        try await Mocker.mock(name: .mockLogout, body: [:])
        
        
        let magicLinkUrl = "http://localhost:3003/magic-link?ngrokUrl=\(ngrokUrl)&token=\(token)&redirectUrl=\(Mocker.baseUrl!)/oauth/"
        return magicLinkUrl
    }
    
    
    
    static func mockRefreshToken() async throws {
        guard let mockedUser = try await Mocker.mockData(name: .generateUser, body: [Mocker.clientId!, ["email":"test@frontegg.com"]]) as? [String: Any] else {
            throw MockServerError.invalidResponse("Failed to generate mock user")
        }
        
        let authUserOptions: [String: Any] = [
            "success":true,
            "user": mockedUser
        ]
        try await Mocker.mock(name: .mockAuthUser, body: ["options": authUserOptions])
        try await Mocker.mock(name: .mockHostedLoginRefreshToken, body: [
            "partialRequestBody": [:],
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        try await Mocker.mock(name: .mockEmbeddedRefreshToken, body: [
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        
        try await Mocker.mock(name: .mockGetMeTenants, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockGetMe, body: ["options":mockedUser])
        try await Mocker.mock(name: .mockSessionsConfigurations, body: [:])
        
        try await Mocker.mock(name: .mockLogout, body: [:])
    }
    
}
