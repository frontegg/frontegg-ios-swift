//
//  MultiRegionConfig.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation

struct MultiRegionConfig: Decodable, Equatable {

    let keychainService: String
    let embeddedMode: Bool
    let regions: [RegionConfig]

    init(keychainService: String, embeddedMode: Bool, regions: [RegionConfig]) {
        self.keychainService = keychainService
        self.embeddedMode = embeddedMode
        self.regions = regions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
        self.keychainService = keychainService ?? "frontegg"

        let embeddedMode = try container.decodeIfPresent(Bool.self, forKey: .embeddedMode)
        self.embeddedMode = embeddedMode ?? true

        self.regions = try container.decode([RegionConfig].self, forKey: .regions)

    }

    enum CodingKeys: String, CodingKey {
        case keychainService
        case embeddedMode
        case regions
    }
}
