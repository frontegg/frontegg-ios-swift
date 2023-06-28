//
//  AuthorizeUrlGenerator.swift
//  
//
//  Created by David Frontegg on 19/01/2023.
//

import Foundation
import CommonCrypto



public class AuthorizeUrlGenerator {
    
    public static let shared = AuthorizeUrlGenerator()
    
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
    
    func generate() -> (URL, String) {
        
        let nonce = createRandomString()
        let codeVerifier = createRandomString()
        let codeChallenge = generateCodeChallenge(codeVerifier)

        let baseUrl = FronteggApp.shared.baseUrl
        let redirectUri = generateRedirectUri();
        logger.trace("CodeVerifier saved in memory to be able to validate the response")


        var authorizeUrl = URLComponents(string: baseUrl)!

        authorizeUrl.path = "/frontegg/oauth/authorize"
        authorizeUrl.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: FronteggApp.shared.clientId),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
        ]

        if let url = authorizeUrl.url{
            logger.trace("Generated url: \(url.absoluteString)")

            if let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                var loginUrl = URLComponents(string: baseUrl)!

                loginUrl.path = "/frontegg/oauth/logout"
                loginUrl.queryItems = [
                    URLQueryItem(name: "post_logout_redirect_uri", value: encodedURL),
                ]
                return (loginUrl.url!, codeVerifier)
            } else {
                logger.error("Failed to parse the generated url, baseUrl: \(baseUrl)")
                fatalError("Failed to generate authorize url")
            }
        } else {
            logger.error("Unkonwn error occured while generating authorize url, baseUrl: \(baseUrl)")
            fatalError("Failed to generate authorize url")
        }

    }
    
}
