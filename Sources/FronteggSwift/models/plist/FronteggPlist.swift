//
//  FronteggPlist.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation

enum FronteggPlist: Equatable {

    case singleRegion(SingleRegionConfig)
    case multiRegion(MultiRegionConfig)
}

// MARK: - Init
extension FronteggPlist: Decodable {

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

// MARK: - Helper Properties
extension FronteggPlist {

    var keychainService: String {
        switch self {
        case .singleRegion(let config): config.keychainService
        case .multiRegion(let config): config.keychainService
        }
    }

    var embeddedMode: Bool {
        switch self {
        case .singleRegion(let config): config.embeddedMode
        case .multiRegion(let config): config.embeddedMode
        }
    }

    var loginWithSocialLogin: Bool {
        switch self {
        case .singleRegion(let config): config.loginWithSocialLogin
        case .multiRegion(let config): config.loginWithSocialLogin
        }
    }

    var loginWithSSO: Bool {
        switch self {
        case .singleRegion(let config): config.loginWithSSO
        case .multiRegion(let config): config.loginWithSSO
        }
    }

    var lateInit: Bool {
        switch self {
        case .singleRegion(let config): config.lateInit
        case .multiRegion(let config): config.lateInit
        }
    }
}
