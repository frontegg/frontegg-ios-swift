//
//  ConfigurationError.swift
//
//
//  Created by Nick Hagi on 17/07/2024.
//

import Foundation

// MARK: - ConfigurationError
extension FronteggError {

    public enum Configuration: LocalizedError, Equatable {
        case couldNotLoadPlist(_ errorDescription: String)
        case couldNotGetBundleID(_ atPath: String)
        case missingPlist
        case missingClientIdOrBaseURL(_ atPath: String)
        case missingRegions
        case invalidRegions(_ atPath: String)
        case invalidRegionKey(_ regionKey: String, _ availableKeys: String)
        case failedToGenerateAuthorizeURL
        case socialLoginMissing(_ socialType:String)
        case wrongBaseUrl(_ baseUrl: String, _ errorDescription: String)
    }
}

// MARK: - LocalizedError
extension FronteggError.Configuration {

    public var errorDescription: String? {
        switch self {
        case let .couldNotLoadPlist(error): "Could not load Frontegg Plist: \(error)"
        case let .couldNotGetBundleID(path): "Could not get bundle identifier from Bundle.main (path: \(path))"
        case .missingPlist: "Missing Frontegg.plist file with 'clientId' and 'baseUrl' entries in main bundle!"
        case let .missingClientIdOrBaseURL(path): "Frontegg.plist file at \(path) is missing 'clientId' and/or 'baseUrl' entries!"
        case .missingRegions: "no regions in Frontegg.plist"
        case let .invalidRegions(path): "Frontegg.plist file at \(path) has invalid regions data, regions must be array of (key, baseUrl, clientId)"
        case let .invalidRegionKey(regionKey, availableKeys): "invalid region key \(regionKey). available regions: \(availableKeys)"
        case .failedToGenerateAuthorizeURL: "Failed to generate authorize url"
        case let .socialLoginMissing(socialType): "Missing social login config for \(socialType)"
        case let .wrongBaseUrl(baseUrl, errorDescription): "Wrong 'baseUrl' format (\(baseUrl), reason:` \(errorDescription)"
        }
    }
}
