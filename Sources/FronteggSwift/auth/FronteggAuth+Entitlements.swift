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

    public func getFeatureEntitlements(featureKey: String, customAttributes: [String: Any?]? = nil) -> Entitlement {
        guard self.user != nil else {
            return Entitlement(isEntitled: false, justification: NotEntitledJustification.NOT_AUTHENTICATED)
        }
        return entitlements.checkFeature(
            featureKey: featureKey,
            attributes: attributesForEvaluation(customAttributes: customAttributes)
        )
    }

    public func getPermissionEntitlements(permissionKey: String, customAttributes: [String: Any?]? = nil) -> Entitlement {
        guard self.user != nil else {
            return Entitlement(isEntitled: false, justification: NotEntitledJustification.NOT_AUTHENTICATED)
        }
        return entitlements.checkPermission(
            permissionKey: permissionKey,
            attributes: attributesForEvaluation(customAttributes: customAttributes)
        )
    }

    public func getEntitlements(options: EntitledToOptions, customAttributes: [String: Any?]? = nil) -> Entitlement {
        switch options {
        case .featureKey(let key):
            return getFeatureEntitlements(featureKey: key, customAttributes: customAttributes)
        case .permissionKey(let key):
            return getPermissionEntitlements(permissionKey: key, customAttributes: customAttributes)
        }
    }

    /// Builds the attribute bag rule conditions are evaluated against — JWT claims
    /// from the current access token plus any host-app `customAttributes`. The
    /// downstream `AttributesPreparer` adds the `frontegg.` and `jwt.` prefixes
    /// (e.g. `frontegg.tenantId`, `jwt.email`) so a server-emitted rule like
    /// `attribute = "frontegg.tenantId"` can look the value up directly.
    ///
    /// Decoding the JWT inline keeps each entitlement check honest against the
    /// current token — if the SDK just switched tenants and the JWT now carries
    /// `tenantId = "B"`, the check sees `B` immediately, without waiting for the
    /// entitlements reload to settle.
    private func attributesForEvaluation(customAttributes: [String: Any?]?) -> Attributes {
        var jwtClaims: [String: Any?] = [:]
        if let token = self.accessToken, !token.isEmpty,
           let decoded = try? JWTHelper.decode(jwtToken: token) {
            jwtClaims = decoded.mapValues { $0 as Any? }
        }
        return Attributes(custom: customAttributes, jwt: jwtClaims)
    }
}
