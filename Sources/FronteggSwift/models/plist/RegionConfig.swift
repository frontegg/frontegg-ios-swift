//
//  Region.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation

public struct RegionConfig: Decodable, Equatable, Identifiable, Sendable, Hashable {

    public var id: String { key }
    public let key: String
    public let baseUrl: String
    public let clientId: String
    public let applicationId: String?

    enum CodingKeys: String, CodingKey {
        case key
        case baseUrl
        case clientId
        case applicationId
    }
    
    init(key: String, baseUrl: String, clientId: String, applicationId: String?) {
        self.key = key
        self.baseUrl = baseUrl
        if !self.baseUrl.hasPrefix("https://") {
            fatalError(FronteggError.configError(.wrongBaseUrl(self.baseUrl, "'baseUrl' must start with 'https://'")).localizedDescription)
        }
        self.clientId = clientId
        self.applicationId = applicationId
    }
}
