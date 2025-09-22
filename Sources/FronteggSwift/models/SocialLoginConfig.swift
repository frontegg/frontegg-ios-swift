//
//  File.swift
//
//
//  Created by David Antoon on 25/10/2024.
//

import Foundation

public struct SocialLoginOption: Codable {
    let type: String
    let active: Bool
    let customised: Bool
    let clientId: String?
    let redirectUrl: String
    let redirectUrlPattern: String
    let tenantId: String?
    let authorizationUrl: String?
    let backendRedirectUrl: String?
    let options: SocialLoginOptions
    let additionalScopes: [String]
}

public struct SocialLoginOptions: Codable {
    let keyId: String?
    let teamId: String?
    let privateKey: String?
    let verifyEmail: Bool
    let verifyHostedDomain: Bool?
    
    // Init with default values for non-optional fields
    init(keyId: String? = nil, teamId: String? = nil, privateKey: String? = nil, verifyEmail: Bool = false, verifyHostedDomain: Bool? = nil) {
        self.keyId = keyId
        self.teamId = teamId
        self.privateKey = privateKey
        self.verifyEmail = verifyEmail
        self.verifyHostedDomain = verifyHostedDomain
    }
}


public struct SocialLoginConfig: Codable {
    var apple: SocialLoginOption?
    var google: SocialLoginOption?
    var github: SocialLoginOption?
    var facebook: SocialLoginOption?
    var linkedin: SocialLoginOption?
    var microsoft: SocialLoginOption?
    var slack: SocialLoginOption?
    
    // Custom initializer that assigns each SocialLoginOption to the correct property
    init(options: [SocialLoginOption]) {
        for option in options {
            switch option.type.lowercased() {
            case "apple":
                self.apple = option
            case "google":
                self.google = option
            case "github":
                self.github = option
            case "facebook":
                self.facebook = option
            case "linkedin":
                self.linkedin = option
            case "microsoft":
                self.microsoft = option
            case "slack":
                self.slack = option
            default:
                continue
            }
        }
    }
    
    // Custom encoder to encode only non-nil properties dynamically
    func toJsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let jsonData = try? encoder.encode(self) {
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }
}


public enum SocialLoginProvider: String, Codable, CaseIterable {
    case facebook = "facebook"
    case google = "google"
    case microsoft = "microsoft"
    case github = "github"
    case slack = "slack"
    case apple = "apple"
    case linkedin = "linkedin"
    
    // Internal helper to access static, provider-specific details.
    internal var details: ProviderDetails { ProviderDetails.for(provider: self) }
}


public enum SocialLoginAction:String, Codable, CaseIterable {
    case login = "login"
    case signUp = "signUp"
    
}

public struct CustomSocialLoginProvidersResponse: Codable {
    let providers: [CustomSocialLoginProviderConfig]
}

public struct CustomSocialLoginProviderConfig: Codable {
    let id: String
    let type: String // e.g., "custom"
    let clientId: String
    let authorizationUrl: String
    let scopes: String
    let displayName: String
    let active: Bool
    let redirectUrl: String
}
