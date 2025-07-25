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
    public var handleLoginWithCustomSocialLoginProvider:Bool = true
    public var handleLoginWithSocialProvider:Bool = true
    public var backgroundColor: UIColor? = nil

    
    /* force consent when authenticate with social login */
    public var shouldPromptSocialLoginConsent:Bool = true
    
    public var shouldSuggestSavePassword:Bool = false
    
    
    public var regionData: [RegionConfig] = []
    let credentialManager: CredentialManager
    let logger = getLogger("FronteggApp")
    let debugConfigurationChecker = DebugConfigurationChecker()

    init() {
        let config: FronteggPlist
        do {
            config = try PlistHelper.fronteggConfig()
        } catch {
            fatalError(FronteggError.configError(.couldNotLoadPlist(error.localizedDescription)).localizedDescription)
        }

        debugConfigurationChecker.runChecks()

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            fatalError(FronteggError.configError(.couldNotGetBundleID(Bundle.main.bundlePath)).localizedDescription)
        }

        self.embeddedMode = config.embeddedMode
        self.credentialManager = CredentialManager(serviceKey: config.keychainService)
        self.bundleIdentifier = bundleIdentifier
        self.handleLoginWithSocialLogin = config.loginWithSocialLogin
        self.handleLoginWithSSO = config.loginWithSSO
        self.shouldSuggestSavePassword = config.shouldSuggestSavePassword
        self.handleLoginWithSocialProvider = config.handleLoginWithCustomSocialLoginProvider
        self.handleLoginWithCustomSocialLoginProvider = config.handleLoginWithSocialProvider
        self.backgroundColor = UIColor(named: config.backgroundColor ?? "#FFFFFF") ?? .white
        
        if FronteggApp.clearKeychain(config: config) {
            self.credentialManager.clear()
        }
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
            handleLoginWithSSO:Bool = false,
            handleLoginWithCustomSocialLoginProvider:Bool = true,
            handleLoginWithSocialProvider:Bool = true

    ) {
        self.baseUrl = baseUrl
        self.clientId = cliendId
        self.applicationId = applicationId
        
        self.handleLoginWithSocialLogin = handleLoginWithSocialLogin
        self.handleLoginWithSSO = handleLoginWithSSO
        self.handleLoginWithCustomSocialLoginProvider = handleLoginWithCustomSocialLoginProvider
        self.handleLoginWithSocialProvider = handleLoginWithSocialProvider
        
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
    
    private static func clearKeychain(config: FronteggPlist) -> Bool {
        if config.keepUserLoggedInAfterReinstall {
            return false
        }
        
        let userDefaults = UserDefaults.standard
        if !userDefaults.bool(forKey: "IsFronteggFirstApplicationRun") {
            userDefaults.set(true, forKey: "IsFronteggFirstApplicationRun")
            return true
        }
        return false
    }
}
