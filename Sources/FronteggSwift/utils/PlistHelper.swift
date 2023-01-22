//
//  PlistHelper.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation
import Logging

struct PlistHelper {
    
    private static var logLevelCache: Logger.Level? = nil
    
    public static func fronteggConfig() throws -> (clientId: String, baseUrl: String, keychainService: String?) {
        let bundle = Bundle.main;
        guard let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            let errorMessage = "Missing Frontegg.plist file with 'clientId' and 'baseUrl' entries in main bundle!"
            print(errorMessage)
            throw FronteggError.configError(errorMessage)
        }
        
        guard let clientId = values["clientId"] as? String, let baseUrl = values["baseUrl"] as? String else {
            let errorMessage = "Frontegg.plist file at \(path) is missing 'clientId' and/or 'baseUrl' entries!"
            print(errorMessage)
            throw FronteggError.configError(errorMessage)
        }
        
        return (clientId: clientId, baseUrl: baseUrl, keychainService: values["keychainService"] as? String)
    }
    
    public static func getLogLevel() -> Logger.Level {
        
        if let logLevel = PlistHelper.logLevelCache {
            return logLevel
        }
        
        let bundle = Bundle.main;
        if let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
           let values = NSDictionary(contentsOfFile: path) as? [String: Any],
           let logLevelStr = values["logLevel"] as? String,
           let logLevel = Logger.Level.init(rawValue: logLevelStr) {
            
            return logLevel
        }
        
        return Logger.Level.warning
    }
}
