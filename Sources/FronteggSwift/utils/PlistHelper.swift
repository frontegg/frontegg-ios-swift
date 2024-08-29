//
//  PlistHelper.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation

struct PlistHelper {
    
    private static var logLevelCache: Logger.Level? = nil
    private static var logger = getLogger("PlistHelper")
    private static let decoder = PropertyListDecoder()

    /// Decodes the Frontegg configuration plist and logs any error that occurs
    /// - Returns: the decoded model (``FronteggPlist``)
    static func fronteggConfig() throws -> FronteggPlist {

        do {
            return try plist()
        } catch {
            logger.debug(error.localizedDescription)
            throw error
        }
    }
    
    /// Decodes the Frontegg configuration plist
    /// - Returns: the decoded model (``FronteggPlist``)
    private static func plist() throws -> FronteggPlist {

        let resourceName = (getenv("frontegg-testing") != nil) ? "FronteggTest" : "Frontegg"

        guard
            let url = Bundle.main.url(forResource: resourceName, withExtension: "plist"),
            let data = try? Data(contentsOf: url)
        else {
            throw FronteggError.configError(.missingPlist)
        }

        return try decode(FronteggPlist.self, from: data, at: url.path)
    }
    
    /// Gets the required log level from cache if it exists, or attempts to read it from the Frontegg configuration plist if it wasn't previously loaded
    /// - Returns: the required logger level (``Logger/Level``)
    static func getLogLevel() -> Logger.Level {
        
        if let logLevel = PlistHelper.logLevelCache {
            return logLevel
        }

        do {
            let plist = try plist()
            return .init(with: plist.logLevel)
        } catch {
            return .warning
        }
    }
    
}

extension PlistHelper {
    
    /// Decodes a plist model using a PropertyListDecoder, and maps the errors to the internal ``FronteggError`` before logging and rethrowing them. Any unmapped errors will be logged and thrown
    /// - Parameters:
    ///   - type: The type to decode
    ///   - data: The data to decode the model from
    ///   - path: The path of the plist
    /// - Returns: The decoded model
    static func decode<Plist: Decodable>(_ type: Plist.Type, from data: Data, at path: String) throws -> Plist {
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            let mappedError = map(decodingError: error, at: path)

            logger.debug(mappedError.localizedDescription)
            throw mappedError
        } catch {
            logger.debug(error.localizedDescription)
            throw error
        }
    }
}

// MARK: - Error mapping
extension PlistHelper {
    
    /// Maps a DecodingError to the internal ``FronteggError``
    /// - Parameters:
    ///   - error: the decoding error to attempt to map
    ///   - path: the path of the plist (used as part of some of the error description)
    /// - Returns: A ``FronteggError`` if any mapping was found, or the original, unmapped error otherwise
    private static func map(decodingError error: DecodingError, at path: String) -> any Error {
        switch error {
        case
            let .keyNotFound(key, _) where key.stringValue == RegionConfig.CodingKeys.baseUrl.stringValue,
            let .keyNotFound(key, _) where key.stringValue == RegionConfig.CodingKeys.clientId.stringValue:
            return FronteggError.Configuration.missingClientIdOrBaseURL(path)
        case
            let .keyNotFound(key, _) where key.stringValue == MultiRegionConfig.CodingKeys.regions.stringValue:
            return FronteggError.Configuration.missingRegions
        case
            let .keyNotFound(key, _) where key.stringValue == RegionConfig.CodingKeys.key.stringValue:
            return FronteggError.Configuration.invalidRegions(path)
        default:
            return error
        }
    }
}
