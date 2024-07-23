//
//  ConfigurationError.swift
//
//
//  Created by Nick Hagi on 17/07/2024.
//

import Foundation

// MARK: - ConfigurationError
extension FronteggError {

    public enum Configuration: LocalizedError {
        case missingPlist
        case missingClientIdOrBaseURL(_ atPath: String)
        case missingRegions
        case invalidRegions(_ atPath: String)
    }
}

// MARK: - LocalizedError
extension FronteggError.Configuration {

    public var errorDescription: String? {
        switch self {
        case .missingPlist: "Missing Frontegg.plist file with 'clientId' and 'baseUrl' entries in main bundle!"
        case let .missingClientIdOrBaseURL(path): "Frontegg.plist file at \(path) is missing 'clientId' and/or 'baseUrl' entries!"
        case .missingRegions: "no regions in Frontegg.plist"
        case let .invalidRegions(path): "Frontegg.plist file at \(path) has invalid regions data, regions must be array of (key, baseUrl, clientId)"
        }
    }
}
