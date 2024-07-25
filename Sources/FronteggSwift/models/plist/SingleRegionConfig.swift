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

    init(keychainService: String, baseUrl: String, clientId: String, applicationId: String? = nil, embeddedMode: Bool) {
        self.keychainService = keychainService
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.embeddedMode = embeddedMode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
        self.keychainService = keychainService ?? "frontegg"

        let embeddedMode = try container.decodeIfPresent(Bool.self, forKey: .embeddedMode)
        self.embeddedMode = embeddedMode ?? true

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
    }
}
