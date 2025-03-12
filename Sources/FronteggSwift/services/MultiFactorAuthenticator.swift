//
//  MultiFactorAuthenticator.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 10.03.2025.
//

import Foundation


class MultiFactorAuthenticator {
    private let api: Api
    private let baseUrl: String
    
    init(api: Api, baseUrl: String) {
        self.api = api
        self.baseUrl = baseUrl
    }
    
    func start(
        mfaRequestJson: String
    ) throws -> (URL, String) {
        do {
            // Encode JSON string to Base64
            let base64EncodedState = Data(mfaRequestJson.utf8).base64EncodedString()
            
            let directLogin: [String: Any] = [
                "type": "direct",
                "data": "\(baseUrl)/oauth/account/mfa-mobile-authenticator?state=\(base64EncodedState)"
            ]
            
            var generatedUrl: (URL, String)
            
            // Generate Authorization URL
            let directLoginJsonData = try JSONSerialization.data(withJSONObject: directLogin, options: [])
            let directLoginJsonString = directLoginJsonData.base64EncodedString()
            
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: directLoginJsonString)
            
            return generatedUrl
        } catch {
            print("Error during JSON serialization: \(error)")
            throw FronteggError.authError(.failedToAuthenticate)
        }
    }
    
    func start(
        mfaRequestData: [String: Any],
        refreshToken: String? = nil
    ) async throws -> (URL, String) {
        var jsonResponse = mfaRequestData
        
        // Refresh token handling
        if let refreshTokenCookie = refreshToken {
            guard let requestMfaDict = await api.refreshTokenForMfa(refreshTokenCookie: refreshTokenCookie) else {
                print("Failed to get MFA data after refreshToken")
                throw FronteggError.authError(.failedToAuthenticate)
            }
            jsonResponse = requestMfaDict
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: jsonResponse, options: [])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to convert JSON to string.")
            throw FronteggError.authError(.failedToAuthenticate)
        }
        
        return try start(mfaRequestJson: jsonString)
    }
}
