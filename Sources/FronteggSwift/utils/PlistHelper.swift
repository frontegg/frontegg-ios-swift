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

    static func plist() throws -> FronteggPlist {

        let resourceName = (getenv("frontegg-testing") != nil) ? "FronteggTest" : "Frontegg"

        guard
            let url = Bundle.main.url(forResource: resourceName, withExtension: "plist"),
            let data = try? Data(contentsOf: url)
        else {
            let error = FronteggError.configError(.missingPlist)
            logger.debug(error.localizedDescription)
            throw error
        }

        return try decode(FronteggPlist.self, from: data, at: url.path)
    }

    static func getLogLevel() -> Logger.Level {
        
        if let logLevel = PlistHelper.logLevelCache {
            return logLevel
        }
        
        let map = [
            "trace": 0,
            "debug": 1,
            "info": 2,
            "warn": 3,
            "error": 4,
            "critical": 5
        ]
        
        let bundle = Bundle.main;
        if let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
           let values = NSDictionary(contentsOfFile: path) as? [String: Any],
           let logLevelStr = values["logLevel"] as? String,
           let logLevelNum = map[logLevelStr],
           let logLevel = Logger.Level.init(rawValue: logLevelNum) {
            
            return logLevel
        }
        
        return Logger.Level.warning
    }

    public static func bundleIdentifier() -> String {
        let bundle = Bundle.main;
        return bundle.bundleIdentifier!
    }
    
}

extension PlistHelper {

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

    private static func map(decodingError error: DecodingError, at path: String) -> any Error {
        switch error {
        case
            let .keyNotFound(key, _) where key.stringValue == RegionConfig.CodingKeys.baseUrl.stringValue,
            let .keyNotFound(key, _) where key.stringValue == RegionConfig.CodingKeys.clientId.stringValue:
            return FronteggError.Configuration.missingClientIdOrBaseURL(path)
        default:
            return error
        }
    }
}
