//
//  MultiRegionConfig.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation

struct MultiRegionConfig: Decodable, Equatable {

    let keychainService: String
    let regions: [RegionConfig]
    let embeddedMode: Bool
    let loginWithSocialLogin: Bool
    let loginWithSSO: Bool
    let lateInit: Bool

    init(
        keychainService: String,
        regions: [RegionConfig],
        embeddedMode: Bool = true,
        loginWithSocialLogin: Bool = true,
        loginWithSSO: Bool = false,
        lateInit: Bool = false
    ) {
        self.keychainService = keychainService
        self.embeddedMode = embeddedMode
        self.regions = regions
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

        self.regions = try container.decode([RegionConfig].self, forKey: .regions)

    }

    enum CodingKeys: String, CodingKey {
        case keychainService
        case embeddedMode
        case regions
        case loginWithSocialLogin
        case loginWithSSO
        case lateInit
    }
}
