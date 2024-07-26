//
//  FronteggPlist.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation

struct FronteggPlist: Decodable, Equatable {
    
    let keychainService: String
    let embeddedMode: Bool
    let loginWithSocialLogin: Bool
    let loginWithSSO: Bool
    let lateInit: Bool
    let payload: Payload

    enum CodingKeys: CodingKey {
        case keychainService
        case embeddedMode
        case loginWithSocialLogin
        case loginWithSSO
        case lateInit
    }

    init(
        keychainService: String = "frontegg",
        embeddedMode: Bool = true,
        loginWithSocialLogin: Bool = true,
        loginWithSSO: Bool = false,
        lateInit: Bool = false,
        payload: FronteggPlist.Payload
    ) {
        self.keychainService = keychainService
        self.embeddedMode = embeddedMode
        self.loginWithSocialLogin = loginWithSocialLogin
        self.loginWithSSO = loginWithSSO
        self.lateInit = lateInit
        self.payload = payload
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

        self.payload = try Payload(from: decoder)
    }
}

extension FronteggPlist {

    enum Payload: Equatable {

        case singleRegion(SingleRegionConfig)
        case multiRegion(MultiRegionConfig)
    }
}

// MARK: - Init
extension FronteggPlist.Payload: Decodable {

    init(from decoder: any Decoder) throws {
        do {
            let multiRegion = try decoder.singleValueContainer().decode(MultiRegionConfig.self)
            self = .multiRegion(multiRegion)
        } catch {
            let singleRegion = try decoder.singleValueContainer().decode(SingleRegionConfig.self)
            self = .singleRegion(singleRegion)
        }
    }
}
