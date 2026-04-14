//
//  FronteggAuth+RegionManagement.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

extension FronteggAuth {

    public func manualInit(baseUrl: String, clientId: String, applicationId: String?, entitlementsEnabled: Bool = false) {
        setLateInit(false)
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.isRegional = false
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
        self.entitlements = Entitlements(.init(api: self.api, enabled: entitlementsEnabled))
        resetEntitlementsLoadState()
        self.initializeSubscriptions()
    }

    public func manualInitRegions(regions: [RegionConfig], entitlementsEnabled: Bool = false) {
        setLateInit(false)
        self.isRegional = true
        self.regionData = regions
        setSelectedRegion(self.getSelectedRegion())

        if let config = self.selectedRegion {
            self.baseUrl = config.baseUrl
            self.clientId = config.clientId
            self.applicationId = config.applicationId
            self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
            self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
            self.entitlements = Entitlements(.init(api: self.api, enabled: entitlementsEnabled))
            resetEntitlementsLoadState()
            self.initializeSubscriptions()
        } else {
            // selectedRegion is nil (e.g. no saved region or invalid selection) – use first region as
            // fallback so api/credentials are valid. When regions is empty, skip reinit and subscriptions
            // to avoid using stale api/featureFlags/entitlements.
            if let fallback = regions.first {
                self.baseUrl = fallback.baseUrl
                self.clientId = fallback.clientId
                self.applicationId = fallback.applicationId
                self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
                self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
                self.entitlements = Entitlements(.init(api: self.api, enabled: entitlementsEnabled))
                resetEntitlementsLoadState()
                self.initializeSubscriptions()
            }
        }
    }

    public func reinitWithRegion(config: RegionConfig, entitlementsEnabled: Bool = false) {
        self.baseUrl = config.baseUrl
        self.clientId = config.clientId
        self.applicationId = config.applicationId
        setSelectedRegion(config)
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
        self.entitlements = Entitlements(.init(api: self.api, enabled: entitlementsEnabled))
        resetEntitlementsLoadState()
        loadEntitlements(forceRefresh: true)
        self.initializeSubscriptions()
    }

    public func getSelectedRegion() -> RegionConfig? {
        guard let selectedRegionKey = CredentialManager.getSelectedRegion() else {
            return nil
        }

        guard let config = self.regionData.first(where: { config in
            config.key == selectedRegionKey
        }) else {
            let keys: String = self.regionData.map { config in
                config.key
            }.joined(separator: ", ")
            logger.critical("invalid region key \(selectedRegionKey). available regions: \(keys)")
            return nil
        }

        return config
    }
}
