//
//  AuthorizeUrlGenerator.swift
//  
//
//  Created by David Frontegg on 19/01/2023.
//

import Foundation
import CommonCrypto



class AuthorizeUrlGenerator {
    
    private let logger = getLogger("AuthorizeUrlGenerator")
    
    private func createRandomString(_ length: Int = 16) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0 ..< length).map{ _ in letters.randomElement()! })
    }
    
    private func digest(_ input : NSData) -> NSData {
        
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)
        
        CC_SHA256(input.bytes, UInt32(input.length), &hash)
        return NSData(bytes: hash, length: digestLength)
        
    }
    
    private func generateCodeChallenge(_ codeVerifier: String) -> String {
        let data = codeVerifier.data(using: .utf8)!
        let sha256 = digest(data as NSData)
        return sha256.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
    
    func generate() -> URL {
        let nonce = createRandomString()
        let codeVerifier = createRandomString()
        let codeChallenge = generateCodeChallenge(codeVerifier)
        
        let baseUrl = FronteggApp.shared.baseUrl
        
        logger.trace("CodeVerifier saved in memory to be able to validate the response")
        FronteggAuth.shared.codeVerifier = codeVerifier
        
        
        var authorizeUrl = URLComponents(string: baseUrl)!
        
        authorizeUrl.path = "/oauth/authorize"
        authorizeUrl.queryItems = [
            URLQueryItem(name: "redirect_uri", value: URLConstants.generateRedirectUri(baseUrl)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: FronteggApp.shared.clientId),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        
        if let url = authorizeUrl.url{
            logger.trace("Generated url: \(url.absoluteString)")
            return url
        } else {
            logger.error("Unkonwn error occured while generating authorize url, baseUrl: \(baseUrl)")
            fatalError("Failed to generate authorize url")
        }
        
        
    }
    
}
