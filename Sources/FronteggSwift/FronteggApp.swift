//
//  FronteggApp.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation
import UIKit

public class FronteggApp {
    
    public static let shared = FronteggApp()
    
    public var auth: FronteggAuth
    public var baseUrl: String = ""
    public var clientId: String = ""
    var api: Api
    let credentialManager: CredentialManager
    let logger = getLogger("FronteggApp")
    var regionData: [RegionConfig] = []
    var selectedRegion: String? = nil
    var isRegional: Bool = false
    
    init() {
        
        if let data = try? PlistHelper.fronteggRegionalConfig() {
            logger.info("Regional frontegg initialization")
            self.regionData = data.regions;
            self.isRegional = true
            self.baseUrl = ""
            self.clientId = ""
            self.credentialManager = CredentialManager(serviceKey: data.keychainService)
            self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId)
            
            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                api: self.api,
                credentialManager: self.credentialManager,
                requestAuthorize: false
            )
            
            self.selectedRegion = CredentialManager.getSelectedRegion()
            if let region = self.selectedRegion {
                self.initWithRegion(regionKey: region)
            }
            return;
        }
        
        
        logger.info("Standard frontegg initialization")
        guard let data = try? PlistHelper.fronteggConfig() else {
            exit(1)
        }
        
        
        self.baseUrl = data.baseUrl
        self.clientId = data.clientId
        self.credentialManager = CredentialManager(serviceKey: data.keychainService)
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId)
        
        self.auth = FronteggAuth(
            baseUrl: self.baseUrl,
            clientId: self.clientId,
            api: self.api,
            credentialManager: self.credentialManager,
            requestAuthorize: true
        )
        
        logger.info("Frontegg Initialized succcessfully")
    }
 
    public func didFinishLaunchingWithOptions(){
        logger.info("Frontegg baseURL: \(self.baseUrl)")
    }
    
    public func initWithRegion( regionKey:String ){
        
        if ( self.regionData.count == 0 ){
            logger.critical("illegal state. Frontegg.plist does not contains regions array")
            exit(1)
        }
        
        guard let config = self.regionData.first(where: { config in
            config.key == regionKey
        }) else {
            let keys: String = self.regionData.map { config in
                config.key
            }.joined(separator: ", ")
            logger.critical("invalid region key \(regionKey). available regions: \(keys)")
            exit(1)
        }
        
        CredentialManager.saveSelectedRegion(regionKey)
        self.baseUrl = config.baseUrl
        self.clientId = config.clientId
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId)
        
        self.auth = FronteggAuth(
            baseUrl: self.baseUrl,
            clientId: self.clientId,
            api: self.api,
            credentialManager: self.credentialManager,
            requestAuthorize: true
        )
        
        logger.info("Frontegg Initialized succcessfully (region: \(regionKey))")
    }
    
}
