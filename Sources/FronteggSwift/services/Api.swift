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
    private let baseUrl: String
    private let clientId: String
    private let credentialManager: CredentialManager
    
    init(baseUrl: String, clientId: String, credentialManager: CredentialManager) {
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.credentialManager = credentialManager
    }
    
    
    
    private func postRequest(path:String, body: [String: Any?]) async throws -> (Data, URLResponse) {
        let urlStr = "\(self.baseUrl)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        
        if let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        }
        
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return try await URLSession.shared.data(for: request)
    }
    
    private func getRequest(accessToken:String, path:String) async throws -> (Data, URLResponse) {
        
        let urlStr = "\(self.baseUrl)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.httpMethod = "GET"
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func refreshToken(accessToken: String, refreshToken: String) async -> AuthResponse? {
        do {
            let (data, _) = try await postRequest(path: "oauth/token", body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])
            
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            print(error)
            return nil
        }
    }
    
    internal func exchangeToken(code: String,
                                redirectUrl: String,
                                codeVerifier: String) async -> AuthResponse? {
        do {
            let (data, _) = try await postRequest(path: "oauth/token", body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectUrl,
                "code_verifier": codeVerifier,
            ])
            
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        }catch {
            print(error)
            return nil
        }
    }
    
    internal func me(accessToken: String) async throws -> User? {
        let (data, _) = try await getRequest(accessToken: accessToken, path: "identity/resources/users/v2/me")
        
        return try JSONDecoder().decode(User.self, from: data)
    }
    
}
