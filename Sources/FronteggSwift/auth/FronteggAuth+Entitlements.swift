//
//  FronteggAuth+Entitlements.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

extension FronteggAuth {

    func resetEntitlementsLoadState() {
        let pending = entitlementsLoadLock.withLock { () -> [((Bool) -> Void)] in
            entitlementsLoadInProgress = false
            entitlementsLoadForceRefreshPending = false
            let pending = entitlementsLoadPendingCompletions
            entitlementsLoadPendingCompletions.removeAll()
            return pending
        }
        pending.forEach { c in
            if Thread.isMainThread {
                c(false)
            } else {
                DispatchQueue.main.async { c(false) }
            }
        }
    }

    func resolveAccessTokenForCurrentUser() -> String? {
        if let token = self.accessToken, !token.isEmpty { return token }
        let config = try? PlistHelper.fronteggConfig()
        let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
        if enableSessionPerTenant, let tenantId = self.user?.activeTenant.id {
            return try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .accessToken)
        }
        return try? credentialManager.get(key: KeychainKeys.accessToken.rawValue)
    }

    public func loadEntitlements(forceRefresh: Bool = false, completion: ((Bool) -> Void)? = nil) {
        func wrapCompletion(_ c: @escaping (Bool) -> Void) -> (Bool) -> Void {
            return { success in
                if Thread.isMainThread {
                    c(success)
                } else {
                    DispatchQueue.main.async { c(success) }
                }
            }
        }
        entitlementsLoadLock.lock()
        if !forceRefresh && entitlements.hasLoaded {
            entitlementsLoadLock.unlock()
            if let c = completion {
                wrapCompletion(c)(true)
            }
            return
        }
        if entitlementsLoadInProgress {
            if forceRefresh {
                entitlementsLoadForceRefreshPending = true
            }
            if let c = completion {
                entitlementsLoadPendingCompletions.append(wrapCompletion(c))
            }
            entitlementsLoadLock.unlock()
            return
        }
        entitlementsLoadInProgress = true
        if let c = completion {
            entitlementsLoadPendingCompletions.append(wrapCompletion(c))
        }
        entitlementsLoadLock.unlock()
        performEntitlementsLoad()
    }

    enum EntitlementsLoadNextStep {
        case reload
        case invoke([((Bool) -> Void)])
    }

    func finishEntitlementsLoadCycle() -> EntitlementsLoadNextStep {
        entitlementsLoadLock.withLock {
            entitlementsLoadInProgress = false
            if entitlementsLoadForceRefreshPending {
                entitlementsLoadForceRefreshPending = false
                entitlementsLoadInProgress = true
                return .reload
            }

            let completions = entitlementsLoadPendingCompletions
            entitlementsLoadPendingCompletions.removeAll()
            return .invoke(completions)
        }
    }

    func performEntitlementsLoad() {
        Task {
            let success: Bool
            if let token = resolveAccessTokenForCurrentUser() {
                success = await entitlements.load(accessToken: token)
            } else {
                logger.warning("loadEntitlements: no access token available")
                success = false
            }

            switch finishEntitlementsLoadCycle() {
            case .reload:
                performEntitlementsLoad()
            case .invoke(let completions):
                completions.forEach { $0(success) }
            }
        }
    }

    public func getFeatureEntitlements(featureKey: String) -> Entitlement {
        guard self.user != nil else {
            return Entitlement(isEntitled: false, justification: "NOT_AUTHENTICATED")
        }
        return entitlements.checkFeature(featureKey: featureKey)
    }

    public func getPermissionEntitlements(permissionKey: String) -> Entitlement {
        guard self.user != nil else {
            return Entitlement(isEntitled: false, justification: "NOT_AUTHENTICATED")
        }
        return entitlements.checkPermission(permissionKey: permissionKey)
    }

    public func getEntitlements(options: EntitledToOptions) -> Entitlement {
        switch options {
        case .featureKey(let key):
            return getFeatureEntitlements(featureKey: key)
        case .permissionKey(let key):
            return getPermissionEntitlements(permissionKey: key)
        }
    }
}
