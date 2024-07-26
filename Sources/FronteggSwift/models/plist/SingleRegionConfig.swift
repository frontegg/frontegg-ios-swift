//
//  SingleRegionConfig.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation
struct SingleRegionConfig: Decodable, Equatable {

    let baseUrl: String
    let clientId: String
    let applicationId: String?

    init(
        baseUrl: String,
        clientId: String,
        applicationId: String? = nil
    ) {
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.baseUrl = try container.decode(String.self, forKey: .baseUrl)
        self.clientId = try container.decode(String.self, forKey: .clientId)
        self.applicationId = try container.decodeIfPresent(String.self, forKey: .applicationId)

    }

    enum CodingKeys: CodingKey {
        case baseUrl
        case clientId
        case applicationId
    }
}
