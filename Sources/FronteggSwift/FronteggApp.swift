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
    public var applicationId: String? = nil
    public var bundleIdentifier: String = ""
    public var embeddedMode: Bool = true
    public var handleLoginWithSocialLogin:Bool = true
    public var handleLoginWithSSO:Bool = false
    
    /* force consent when authenticate with social login */
    public var shouldPromptSocialLoginConsent:Bool = true
    
    
    public var regionData: [RegionConfig] = []
    let credentialManager: CredentialManager
    let logger = getLogger("FronteggApp")

    init() {
        let config: FronteggPlist
        do {
            config = try PlistHelper.fronteggConfig()
        } catch {
            fatalError(FronteggError.configError(.couldNotLoadPlist(error.localizedDescription)).localizedDescription)
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            fatalError(FronteggError.configError(.couldNotLoadPlist(Bundle.main.bundlePath)).localizedDescription)
        }

        self.embeddedMode = config.embeddedMode
        self.credentialManager = CredentialManager(serviceKey: config.keychainService)
        self.bundleIdentifier = bundleIdentifier
        self.handleLoginWithSocialLogin = config.loginWithSocialLogin
        self.handleLoginWithSSO = config.loginWithSSO

        /**
         lateInit used for react-native and ionic-capacitor initialization
         */
        if config.lateInit {
            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                applicationId: self.applicationId,
                credentialManager: self.credentialManager,
                isRegional: false,
                regionData: self.regionData,
                embeddedMode: self.embeddedMode,
                isLateInit: true
            )
            return
        }

        switch config.payload {
        case let .multiRegion(config):
            logger.info("Regional frontegg initialization")
            self.regionData = config.regions

            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                applicationId: self.applicationId,
                credentialManager: self.credentialManager,
                isRegional: true,
                regionData: self.regionData,
                embeddedMode: self.embeddedMode
            )

            if let config = self.auth.selectedRegion {
                self.baseUrl = config.baseUrl
                self.clientId = config.clientId
                self.applicationId = config.applicationId
                self.auth.reinitWithRegion(config: config)

                logger.info("Frontegg Initialized succcessfully (region: \(config.key))")
                return;
            } else {
                // skip automatic authorize for regional config
                self.auth.initializing = false
                self.auth.isLoading = false
                self.auth.showLoader = false
            }

        case let .singleRegion(config):
            logger.info("Standard frontegg initialization")

            self.baseUrl = config.baseUrl
            self.clientId = config.clientId
            self.applicationId = config.applicationId

            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                applicationId: self.applicationId,
                credentialManager: self.credentialManager,
                isRegional: false,
                regionData: [],
                embeddedMode: self.embeddedMode
            )

            logger.info("Frontegg Initialized succcessfully")
        }
    }
 
    public func didFinishLaunchingWithOptions(){
        logger.info("Frontegg baseURL: \(self.baseUrl)")
    }
    
    public func manualInit(
            baseUrl: String,
            cliendId: String,
            applicationId: String? = nil,
            handleLoginWithSocialLogin: Bool = true,
            handleLoginWithSSO:Bool = false
    ) {
        self.baseUrl = baseUrl
        self.clientId = cliendId
        self.applicationId = applicationId
        
        self.handleLoginWithSocialLogin = handleLoginWithSocialLogin
        self.handleLoginWithSSO = handleLoginWithSSO
        
        self.auth.manualInit(baseUrl: baseUrl, clientId: cliendId, applicationId: applicationId)
    }
    public func manualInitRegions(
        regions: [RegionConfig],
        handleLoginWithSocialLogin: Bool = true,
        handleLoginWithSSO:Bool = false
    ) {
        self.regionData = regions
        self.handleLoginWithSocialLogin = handleLoginWithSocialLogin
        self.handleLoginWithSSO = handleLoginWithSSO
        self.auth.manualInitRegions(regions: regions)
        self.baseUrl = self.auth.baseUrl
        self.clientId = self.auth.clientId
        self.applicationId = self.auth.applicationId
    }

    public func initWithRegion(regionKey: String){
        
        if self.regionData.count == 0 {
            fatalError(FronteggError.configError(.missingRegions).localizedDescription)
        }
        
        guard let config = self.regionData.first(where: { config in
            config.key == regionKey
        }) else {
            let keys: String = self.regionData.map { config in
                config.key
            }.joined(separator: ", ")
            fatalError(FronteggError.configError(.invalidRegionKey(regionKey, keys)).localizedDescription)
        }
        
        CredentialManager.saveSelectedRegion(regionKey)
        
        self.baseUrl = config.baseUrl
        self.clientId = config.clientId
        self.applicationId = config.applicationId
        self.auth.reinitWithRegion(config: config)
        
        logger.info("Frontegg Initialized succcessfully (region: \(regionKey))")
    }
    
}
