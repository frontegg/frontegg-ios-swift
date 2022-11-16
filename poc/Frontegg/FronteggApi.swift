//
//  FronteggApi.swift
//  poc
//
//  Created by David Frontegg on 16/11/2022.
//

import Foundation


enum FronteggApiError: Error {
    case invalidUrl(String)
}
class FronteggApi {
    private let baseUrl: String
    private let clientId: String
    private let credentialManager: FronteggCredentialManager
    
    init(baseUrl: String, clientId: String, credentialManager: FronteggCredentialManager) {
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.credentialManager = credentialManager
    }
 
    
    
    private func postRequest(accessToken:String, path:String, body: [String: Any?]) async throws -> (Data, URLResponse) {
        
        let urlStr = "\(self.baseUrl)/frontegg/\(path)"
        guard let url = URL(string: urlStr) else {
            throw FronteggApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return try await URLSession.shared.data(for: request)
    }
    
    private func getRequest(accessToken:String, path:String) async throws -> (Data, URLResponse) {
        
        let urlStr = "\(self.baseUrl)/frontegg/\(path)"
        guard let url = URL(string: urlStr) else {
            throw FronteggApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.httpMethod = "GET"
        
        return try await URLSession.shared.data(for: request)
    }
    
    public func refreshToken(accessToken: String, refreshToken: String) async -> AuthResponse? {
        do{
            let (data, response) = try await postRequest(accessToken: accessToken, path: "oauth/token", body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])

//            print(response)
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        }catch {
            print(error)
            return nil
        }
    }
    
    
    public func me(accessToken: String) async -> FronteggUser? {
        do{
            let (data, response) = try await getRequest(accessToken: accessToken, path: "identity/resources/users/v2/me")

            print(response)
            return try JSONDecoder().decode(FronteggUser.self, from: data)
        }catch {
            print(error)
            return nil
        }
    }
    
    
    func switchTenant(tenantId: String) {
        
    }
}
