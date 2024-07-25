//
//  SingleRegionConfig.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation
struct SingleRegionConfig: Decodable, Equatable {

    let keychainService: String
    let embeddedMode: Bool
    let baseUrl: String
    let clientId: String
    let applicationId: String?
    let loginWithSocialLogin: Bool
    let loginWithSSO: Bool
    let lateInit: Bool

    init(
        keychainService: String,
        baseUrl: String,
        clientId: String,
        applicationId: String? = nil,
        embeddedMode: Bool = true,
        loginWithSocialLogin: Bool = true,
        loginWithSSO: Bool = false,
        lateInit: Bool = false
    ) {
        self.keychainService = keychainService
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.embeddedMode = embeddedMode
        self.loginWithSocialLogin = loginWithSocialLogin
        self.loginWithSSO = loginWithSSO
        self.lateInit = lateInit
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
        self.keychainService = keychainService ?? "frontegg"

        let embeddedMode = try container.decodeIfPresent(Bool.self, forKey: .embeddedMode)
        self.embeddedMode = embeddedMode ?? true
        
        let socialLogin = try container.decodeIfPresent(Bool.self, forKey: .loginWithSocialLogin)
        self.loginWithSocialLogin = socialLogin ?? true

        let ssoLogin = try container.decodeIfPresent(Bool.self, forKey: .loginWithSSO)
        self.loginWithSSO = ssoLogin ?? false

        let lateInit = try container.decodeIfPresent(Bool.self, forKey: .lateInit)
        self.lateInit = lateInit ?? false

        self.baseUrl = try container.decode(String.self, forKey: .baseUrl)
        self.clientId = try container.decode(String.self, forKey: .clientId)
        self.applicationId = try container.decodeIfPresent(String.self, forKey: .applicationId)

    }

    enum CodingKeys: CodingKey {
        case keychainService
        case baseUrl
        case clientId
        case applicationId
        case embeddedMode
        case loginWithSocialLogin
        case loginWithSSO
        case lateInit
    }
}
