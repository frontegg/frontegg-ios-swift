//
//  PlistHelper.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation

public struct RegionConfig {
    public var key: String
    public var baseUrl: String
    public var clientId: String
    
    public init(key: String, baseUrl: String, clientId: String){
        self.key = key
        self.baseUrl = baseUrl
        self.clientId = clientId
    }
}

struct PlistHelper {
    
    private static var logLevelCache: Logger.Level? = nil
    private static var logger = getLogger("PlistHelper")

    public static func fronteggConfig() throws -> (clientId: String, baseUrl: String, keychainService: String, bundleIdentifier: String) {
        let bundle = Bundle.main;
        
        let resourceName = (getenv("frontegg-testing") != nil) ? "FronteggTest" : "Frontegg"
        
        guard let path = bundle.path(forResource: resourceName, ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            let error = FronteggError.configError(.missingPlist)
            logger.debug(error.localizedDescription)
            throw error
        }
        
        guard let clientId = values["clientId"] as? String, let baseUrl = values["baseUrl"] as? String else {
            let error = FronteggError.configError(.missingClientIdOrBaseURL(path))
            logger.debug(error.localizedDescription)
            throw error
        }
        
        let keychainService = values["keychainService"] as? String ?? "frontegg"
        
        return (clientId: clientId, baseUrl: baseUrl, keychainService: keychainService, bundleIdentifier: bundle.bundleIdentifier!)
    }
    
    public static func fronteggRegionalConfig() throws -> (regions: [RegionConfig], keychainService: String, bundleIdentifier: String) {
        let bundle = Bundle.main;
        
        let resourceName = (getenv("frontegg-testing") != nil) ? "FronteggTest" : "Frontegg"
        
        guard let path = bundle.path(forResource: resourceName, ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            let error = FronteggError.configError(.missingPlist)
            logger.debug(error.localizedDescription)
            throw error
        }
        
        guard 
            let regions = values["regions"] as? [[String: String]],
            !regions.isEmpty
        else {
            let error = FronteggError.configError(.missingRegions)
            logger.debug(error.localizedDescription)
            throw error
        }
        
        let keychainService = values["keychainService"] as? String ?? "frontegg"
        
        let regionConfigs = try regions.map { dict in
            guard 
                let key = dict["key"],
                let baseUrl = dict["baseUrl"],
                let clientId = dict["clientId"] 
            else {
                let error = FronteggError.configError(.invalidRegions(path))
                logger.debug(error.localizedDescription)
                throw error
            }
            return RegionConfig(key: key, baseUrl: baseUrl, clientId: clientId)
        }
        return (regions: regionConfigs, keychainService: keychainService, bundleIdentifier: bundle.bundleIdentifier!)
    }
    
    
    public static func getLogLevel() -> Logger.Level {
        
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
    

    
    public static func isEmbeddedMode() -> Bool {
        
        let bundle = Bundle.main;
        if let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
           let values = NSDictionary(contentsOfFile: path) as? [String: Any],
           let embeddedMode =  values["embeddedMode"] as? Bool {
            
            return embeddedMode
        }
        
        return true
    }
    
    public static func isLateInit() -> Bool {
        let bundle = Bundle.main;
        if let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
           let values = NSDictionary(contentsOfFile: path) as? [String: Any],
           let lateInit =  values["lateInit"] as? Bool {
            
           return lateInit
        }
        return false
    }
    
    
    public static func getKeychainService() -> String {
        let bundle = Bundle.main;
        if let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
           let values = NSDictionary(contentsOfFile: path) as? [String: Any],
           let keychainService =  values["keychainService"] as? String {
            
           return keychainService
        }
        return "frontegg"
    }
    
    public static func getNativeBridgeOptions() -> [String: Bool] {
        let bundle = Bundle.main;
        
        var loginWithSocialLogin:Bool = true
        var loginWithSSO:Bool = false
        
        if let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
           let values = NSDictionary(contentsOfFile: path) as? [String: Any] {
            
            loginWithSocialLogin = (values["loginWithSocialLogin"] as? Bool) ?? true
            loginWithSSO = (values["loginWithSSO"] as? Bool) ?? false
            
        }
        return [
            "loginWithSocialLogin": loginWithSocialLogin,
            "loginWithSSO": loginWithSSO
        ]
    }
    
}

