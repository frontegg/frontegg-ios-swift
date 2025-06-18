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
    
    func generate(
        loginHint: String? = nil,
        loginAction: String? = nil,
        remainCodeVerifier: Bool = false,
        stepUp:Bool = false,
        maxAge: TimeInterval? = nil
    ) -> (URL, String) {
        
        let nonce = createRandomString()
        let codeVerifier = remainCodeVerifier ? (CredentialManager.getCodeVerifier() ?? createRandomString()) : createRandomString()
        let codeChallenge = generateCodeChallenge(codeVerifier)
        
        let baseUrl = FronteggApp.shared.baseUrl
        let redirectUri = generateRedirectUri();
        
        
        var authorizeUrl = URLComponents(string: baseUrl)!
        
        authorizeUrl.path = "/oauth/authorize"
        
        var queryParams = [
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: FronteggApp.shared.applicationId ?? FronteggApp.shared.clientId),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        if stepUp {
            queryParams.append(URLQueryItem(name: "acr_values", value: StepUpConstants.ACR_VALUE))
            
            if let maxAge = maxAge {
                queryParams.append(URLQueryItem(name: "max_age", value: String(maxAge)))
            }
        } else {
            queryParams.append(URLQueryItem(name: "prompt", value: "login"))
        }
        
        if (loginHint != nil) {
            queryParams.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        
        if (loginAction != nil) {
            queryParams.append(URLQueryItem(name: "login_direct_action", value: loginAction))
            
            authorizeUrl.queryItems = queryParams
            
            if let url = authorizeUrl.url{
                return (url, codeVerifier)
            } else {
                logger.error("Unkonwn error occured while generating authorize url, baseUrl: \(baseUrl)")
                fatalError(FronteggError.configError(.failedToGenerateAuthorizeURL).localizedDescription)
            }
        }
        
        
        authorizeUrl.queryItems = queryParams
        
        // https://stackoverflow.com/a/37314144
        if (loginHint?.contains("+") ?? false){
            logger.error(authorizeUrl.percentEncodedQuery!)
            authorizeUrl.percentEncodedQuery=authorizeUrl.percentEncodedQuery?.replacingOccurrences(of:"+",with: "%2B")
        }
        
        
        if let url = authorizeUrl.url {
            logger.trace("Generated url: \(url.absoluteString)")
            return (url, codeVerifier);
        } else {
            logger.error("Unkonwn error occured while generating authorize url, baseUrl: \(baseUrl)")
            fatalError(FronteggError.configError(.failedToGenerateAuthorizeURL).localizedDescription)
        }
        
    }
}
