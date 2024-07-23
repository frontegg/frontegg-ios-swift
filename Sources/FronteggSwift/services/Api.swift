//
//  FronteggApi.swift
//
//  Created by David Frontegg on 16/11/2022.
//

import Foundation


enum ApiError: Error {
    case invalidUrl(String)
}
public class Api {
    private let logger = getLogger("Api")
    private let baseUrl: String
    private let clientId: String
    private let applicationId: String?
    private var cookieName: String
    private let credentialManager: CredentialManager
    
    init(baseUrl: String, clientId: String, applicationId: String?) {
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.credentialManager = CredentialManager(serviceKey: "frontegg")
        
        self.cookieName = "fe_refresh_\(clientId)"
        if let range = self.cookieName.range(of: "-") {
            self.cookieName.removeSubrange(range)
        }
    }
    
    internal func putRequest(path:String, body: [String: Any?]) async throws -> (Data, URLResponse) {
        let urlStr = "\(self.baseUrl)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        
        if (self.applicationId != nil) {
            request.setValue(self.applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        if let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        }
        
        request.httpMethod = "PUT"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func postRequest(path:String, body: [String: Any?], additionalHeaders: [String: String] = [:]) async throws -> (Data, URLResponse) {
        let urlStr = "\(self.baseUrl)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        
        if (self.applicationId != nil) {
            request.setValue(self.applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        additionalHeaders.forEach({ (key: String, value: String) in
            request.setValue(value, forHTTPHeaderField: key)
        })
        
        if let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        }
        
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func getRequest(path:String, accessToken:String?, refreshToken: String? = nil) async throws -> (Data, URLResponse) {
        
        let urlStr = "\(self.baseUrl)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        if(accessToken != nil){
            request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "authorization")
        }
        if(refreshToken != nil){
            let cookieHeaderValue = "\(self.cookieName)=\(refreshToken!)"
            request.setValue(cookieHeaderValue, forHTTPHeaderField: "cookie")
        }
        if (self.applicationId != nil) {
            request.setValue(self.applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        request.httpMethod = "GET"
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func refreshToken(accessToken: String, refreshToken: String) async -> AuthResponse? {
        do {
            let (data, _) = try await postRequest(path: "oauth/token", body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])
            
            let text = String(data: data, encoding: .utf8)!
            print("result \(text)")
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            print(error)
            return nil
        }
    }
    
    internal func exchangeToken(code: String,
                                redirectUrl: String,
                                codeVerifier: String) async -> (AuthResponse?, FronteggError?) {
        do {
            let (data, _) = try await postRequest(path: "oauth/token", body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectUrl,
                "code_verifier": codeVerifier,
            ])
            
            return (try JSONDecoder().decode(AuthResponse.self, from: data), nil)
        }catch {
            return (nil, FronteggError.authError(.couldNotExchangeToken(error.localizedDescription)))
        }
    }
    
    internal func me(accessToken: String) async throws -> User? {
        let (meData, _) = try await getRequest(path: "identity/resources/users/v2/me", accessToken: accessToken)
        
        var meObj = try JSONSerialization.jsonObject(with: meData, options: [])  as! [String: Any]
        
        let (tenantsData, _) = try await getRequest(path: "identity/resources/users/v3/me/tenants", accessToken: accessToken)
        
        let tenantsObj = try JSONSerialization.jsonObject(with: tenantsData, options: [])  as! [String: Any]
        
        meObj["tenants"] = tenantsObj["tenants"]
        meObj["activeTenant"] = tenantsObj["activeTenant"]
        
        let mergedData = try JSONSerialization.data(withJSONObject: meObj)

        
        return try JSONDecoder().decode(User.self, from: mergedData)
    }
    
    
    public func switchTenant(tenantId: String) async throws -> Void {
        _ = try await putRequest(path: "identity/resources/users/v1/tenant", body: ["tenantId":tenantId])
    }
    
    internal func logout(accessToken: String?, refreshToken: String?) async {
        
        do {
            let (_, response) = try await postRequest(path: "identity/resources/auth/v1/logout", body: ["refreshToken":refreshToken])
            
            if let res = response as? HTTPURLResponse, res.statusCode != 401 {
                self.logger.info("logged out successfully")
            }else {
                self.logger.info("Already logged out")
            }
        }catch {
            self.logger.info("Uknonwn error when try to logout: \(error)")
        }
    }
    
    
}
