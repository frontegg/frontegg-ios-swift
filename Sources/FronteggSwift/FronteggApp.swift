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
    public var bundleIdentifier: String = ""
    public var embeddedMode: Bool = true;
    
    public var regionData: [RegionConfig] = []
    let credentialManager: CredentialManager
    let logger = getLogger("FronteggApp")
    
    
    init() {
        
        self.embeddedMode = PlistHelper.isEmbeddedMode()
        let keychainService = PlistHelper.getKeychainService()
        self.credentialManager = CredentialManager(serviceKey: keychainService)
        self.bundleIdentifier = PlistHelper.bundleIdentifier()
        
        
        /**
         lateInit used for react-native and ionic-capacitor initialization
         */
        if(PlistHelper.isLateInit()){
            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                credentialManager: self.credentialManager,
                isRegional: false,
                regionData: self.regionData,
                embeddedMode: self.embeddedMode,
                isLateInit: true
            )
            return
        }
        
        if let data = try? PlistHelper.fronteggRegionalConfig() {
            logger.info("Regional frontegg initialization")
            self.regionData = data.regions
            
            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                credentialManager: self.credentialManager,
                isRegional:true,
                regionData: self.regionData,
                embeddedMode: self.embeddedMode
            )
            
            if let config = self.auth.selectedRegion {
                self.baseUrl = config.baseUrl
                self.clientId = config.clientId
                self.auth.reinitWithRegion(config: config)
                
                logger.info("Frontegg Initialized succcessfully (region: \(config.key))")
                return;
            }else {
                // skip automatic authorize for regional config
                self.auth.initializing = false
                self.auth.isLoading = false
                self.auth.showLoader = false
            }
            
            return;
        }
        
        
        logger.info("Standard frontegg initialization")
        guard let data = try? PlistHelper.fronteggConfig() else {
            exit(1)
        }
        
        
        self.baseUrl = data.baseUrl
        self.clientId = data.clientId
        
        self.auth = FronteggAuth(
            baseUrl: self.baseUrl,
            clientId: self.clientId,
            credentialManager: self.credentialManager,
            isRegional: false,
            regionData: [],
            embeddedMode: self.embeddedMode
        )
        
        logger.info("Frontegg Initialized succcessfully")
    }
    
    public func didFinishLaunchingWithOptions(){
        logger.info("Frontegg baseURL: \(self.baseUrl)")
    }
    
    public func manualInit(baseUrl: String, cliendId:String) {
        self.baseUrl = baseUrl
        self.clientId = cliendId
        
        self.auth.manualInit(baseUrl: baseUrl, clientId: cliendId)
    }
    public func manualInitRegions(regions: [RegionConfig]) {
        self.regionData = regions
        self.auth.manualInitRegions(regions: regions)
        self.baseUrl = self.auth.baseUrl
        self.clientId = self.auth.clientId
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
        self.auth.reinitWithRegion(config: config)
        
        logger.info("Frontegg Initialized succcessfully (region: \(regionKey))")
    }
    
}
