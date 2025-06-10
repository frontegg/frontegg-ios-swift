//
//  File.swift
//
//
//  Created by David Antoon on 25/10/2024.
//

import Foundation

public struct SocialLoginOption: Codable, Equatable {
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
    
    public static func == (lhs: SocialLoginOption, rhs: SocialLoginOption) -> Bool {
        return lhs.type == rhs.type &&
        lhs.active == rhs.active &&
        lhs.customised == rhs.customised &&
        lhs.clientId == rhs.clientId &&
        lhs.redirectUrl == rhs.redirectUrl &&
        lhs.redirectUrlPattern == rhs.redirectUrlPattern &&
        lhs.tenantId == rhs.tenantId &&
        lhs.authorizationUrl == rhs.authorizationUrl &&
        lhs.backendRedirectUrl == rhs.backendRedirectUrl &&
        lhs.options == rhs.options &&
        lhs.additionalScopes == rhs.additionalScopes
    }
}


public struct SocialLoginOptions: Codable, Equatable {
    let keyId: String?
    let teamId: String?
    let privateKey: String?
    let verifyEmail: Bool
    let verifyHostedDomain: Bool?
    
    public static func == (lhs: SocialLoginOptions, rhs: SocialLoginOptions) -> Bool {
        return lhs.keyId == rhs.keyId &&
        lhs.teamId == rhs.teamId &&
        lhs.privateKey == rhs.privateKey &&
        lhs.verifyEmail == rhs.verifyEmail &&
        lhs.verifyHostedDomain == rhs.verifyHostedDomain
    }
    
    // Custom initializer with default values
    init(keyId: String? = nil, teamId: String? = nil, privateKey: String? = nil, verifyEmail: Bool = false, verifyHostedDomain: Bool? = nil) {
        self.keyId = keyId
        self.teamId = teamId
        self.privateKey = privateKey
        self.verifyEmail = verifyEmail
        self.verifyHostedDomain = verifyHostedDomain
    }
}


public struct SocialLoginConfig: Codable, Equatable {
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
    
    public static func == (lhs: SocialLoginConfig, rhs: SocialLoginConfig) -> Bool {
        return lhs.apple == rhs.apple &&
        lhs.google == rhs.google &&
        lhs.github == rhs.github &&
        lhs.facebook == rhs.facebook &&
        lhs.linkedin == rhs.linkedin &&
        lhs.microsoft == rhs.microsoft &&
        lhs.slack == rhs.slack
    }
}

