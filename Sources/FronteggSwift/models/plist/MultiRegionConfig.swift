//
//  MultiRegionConfig.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation

struct MultiRegionConfig: Decodable, Equatable {

    let regions: [RegionConfig]

    init(regions: [RegionConfig]) {
        self.regions = regions
    }
}
