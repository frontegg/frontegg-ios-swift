//
//  FronteggAuth+Refresh.swift
//  FronteggSwift
//

import Foundation
import Dispatch

extension FronteggAuth {

    func calculateOffset(expirationTime: Int) -> TimeInterval {
        let now = Date().timeIntervalSince1970 * 1000 // Current time in milliseconds
        let remainingTime = (Double(expirationTime) * 1000) - now

        let minRefreshWindow: Double = 20000 // Minimum 20 seconds before expiration, in milliseconds
        let adaptiveRefreshTime = remainingTime * 0.8 // 80% of remaining time

        return remainingTime > minRefreshWindow ? adaptiveRefreshTime / 1000 : max((remainingTime - minRefreshWindow) / 1000, 0)
    }

    func refreshTokenWhenNeeded() {
        do {
            logger.info("Checking if refresh token is available...")

            let config = try? PlistHelper.fronteggConfig()
            let enableSessionPerTenant = config?.enableSessionPerTenant ?? false

            // Check if the refresh token is available
            if self.refreshToken == nil {
                if enableSessionPerTenant {
                    // Try to load tenant-specific token
                    if let user = self.user {
                        let tenantId = user.activeTenant.id
                        if let tenantToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken) {
                            logger.info("Reloaded refresh token for tenant \(tenantId) from keychain in refreshTokenWhenNeeded")
                            DispatchQueue.main.sync {
                                setRefreshToken(tenantToken)
                            }
                        } else {
                            logger.debug("No refresh token available for tenant \(tenantId). Exiting...")
                            return
                        }
                    } else if let offlineUser = credentialManager.getOfflineUser() {
                        let tenantId = offlineUser.activeTenant.id
                        if let tenantToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken) {
                            logger.info("Reloaded refresh token for tenant \(tenantId) from keychain in refreshTokenWhenNeeded")
                            DispatchQueue.main.sync {
                                setRefreshToken(tenantToken)
                            }
                        } else {
                            logger.debug("No refresh token available for tenant \(tenantId). Exiting...")
                            return
                        }
                    } else {
                        logger.debug("No user or tenant information available. Exiting...")
                        return
                    }
                } else {
                    // Try to reload from keychain before giving up (legacy behavior)
                if let keychainToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                    logger.info("Reloaded refresh token from keychain in refreshTokenWhenNeeded")
                    // Use async dispatch to avoid deadlock if already on main thread
                    if Thread.isMainThread {
                        setRefreshToken(keychainToken)
                    } else {
                        DispatchQueue.main.async { [weak self] in
                            self?.setRefreshToken(keychainToken)
                        }
                    }
                } else {
                    logger.debug("No refresh token available in memory or keychain. Exiting...")
                    return
                    }
                }
            }

            logger.debug("Refresh token is available. Checking access token...")

            // Check if the access token is available
            guard let accessToken = self.accessToken else {
                logger.debug("No access token found. Attempting to refresh token...")
                Task {
                    await self.refreshTokenIfNeeded()
                }
                return
            }

            logger.debug("Access token found. Attempting to decode JWT...")

            // Decode the access token to get the expiration time
            let decode = try JWTHelper.decode(jwtToken: accessToken)
            guard let expirationTime = decode["exp"] as? Int else {
                logger.warning("JWT missing exp claim in refreshTokenWhenNeeded. Refreshing immediately.")
                Task {
                    await self.refreshTokenIfNeeded()
                }
                return
            }
            logger.debug("JWT decoded successfully. Expiration time: \(expirationTime)")

            let offset = calculateOffset(expirationTime: expirationTime)
            logger.debug("Calculated offset for token refresh: \(offset) seconds")

            // If offset is zero, refresh immediately
            if offset == 0 {
                logger.info("Offset is zero. Refreshing token immediately...")
                Task {
                    await self.refreshTokenIfNeeded()
                }
            } else {
                logger.info("Scheduling token refresh after \(offset) seconds")
                self.scheduleTokenRefresh(offset: offset)
            }
        } catch {
            logger.error("Failed to decode JWT: \(error.localizedDescription)")
            Task {
                await self.refreshTokenIfNeeded()
            }
        }
    }



    func scheduleTokenRefresh(offset: TimeInterval, attempts: Int = 0, skipNetworkCheck: Bool = false) {
        cancelScheduledTokenRefresh()
        logger.info("Schedule token refresh after, (\(offset) s) (attempt: \(attempts))")

        var workItem: DispatchWorkItem? = nil
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !(workItem!.isCancelled) else { return }
            Task {
                await self.refreshTokenIfNeeded(attempts: attempts, skipNetworkCheck: skipNetworkCheck)
            }
        }
        refreshTokenDispatch = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + offset, execute: workItem!)

    }

    func cancelScheduledTokenRefresh() {
        logger.info("Canceling previous refresh token task")
        refreshTokenDispatch?.cancel()
        refreshTokenDispatch = nil
    }

    public func refreshTokenIfNeeded(attempts: Int = 0, skipNetworkCheck: Bool = false) async -> Bool {
        let config = try? PlistHelper.fronteggConfig()
        let enableOfflineMode = config?.enableOfflineMode ?? false
        let enableSessionPerTenant = config?.enableSessionPerTenant ?? false

        // Try to reload from keychain if in-memory token is nil
        var refreshToken = self.refreshToken
        var currentTenantId: String? = nil

        if enableSessionPerTenant {
            if let localTenantId = credentialManager.getLastActiveTenantId() {
                currentTenantId = localTenantId
                logger.info("Using LOCAL tenant ID for refresh: \(localTenantId)")
            } else {
                if let offlineUser = credentialManager.getOfflineUser() {
                    currentTenantId = offlineUser.activeTenant.id
                    if let tid = currentTenantId {
                        credentialManager.saveLastActiveTenantId(tid)
                        logger.info("No local tenant stored, using offline user's tenant: \(tid) (saved as local tenant)")
                    }
                } else {
                    logger.info("No local tenant stored and no offline user available for refresh")
                }
            }

            // Load tenant-specific refresh token
            if let tenantId = currentTenantId {
                if refreshToken == nil {
                    if let tenantToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken) {
                        self.logger.info("Reloaded refresh token for tenant \(tenantId) from keychain")
                        await MainActor.run {
                            setRefreshToken(tenantToken)
                        }
                        refreshToken = tenantToken
                    } else {
                        if let legacyToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                            self.logger.warning("No tenant-specific token found for tenant \(tenantId), falling back to legacy token (migration scenario)")
                            await MainActor.run {
                                setRefreshToken(legacyToken)
                            }
                            refreshToken = legacyToken
                        } else {
                            self.logger.info("No refresh token found for tenant \(tenantId) and no legacy token available. Tenant ID preserved for SessionPerTenant, but cannot refresh without token.")
                            return false
                        }
                    }
                }
            } else {
                if refreshToken == nil {
                    if let legacyToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                        self.logger.warning("No tenant ID available, falling back to legacy token (migration scenario)")
                        await MainActor.run {
                            setRefreshToken(legacyToken)
                        }
                        refreshToken = legacyToken
                    } else {
                        self.logger.info("No refresh token available. Cannot refresh.")
                        return false
                    }
                }
            }
        } else {
            // Legacy behavior: load global refresh token
            if refreshToken == nil {
                if let keychainToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                    self.logger.info("Reloaded refresh token from keychain")
                    await MainActor.run {
                        setRefreshToken(keychainToken)
                    }
                    refreshToken = keychainToken
                } else {
                    self.logger.info("No refresh token available in legacy mode. Cannot refresh.")
                    return false
                }
            }
        }

        guard let refreshToken = refreshToken else {
            self.logger.info("No refresh token found in memory or keychain")
            return false
        }

        if skipNetworkCheck {
            self.logger.info("Skipping pre-refresh network gate and attempting refresh directly")
        } else if enableOfflineMode {
            // Hard no-network (quick exit path) — advisory only; actual request errors remain authoritative
            let isNetworkAvailable = await checkNetworkPath(timeout: 300_000_000)

            guard isNetworkAvailable else {
                self.logger.info("Refresh rescheduled due to inactive internet (path check, no /test call)")
                handleOfflineLikeFailure(
                    error: nil,
                    enableOfflineMode: enableOfflineMode,
                    attempts: attempts
                )
                return false
            }
        } else {
            // Offline mode not enabled - use NetworkStatusMonitor.isActive (will make /test call)
            guard await NetworkStatusMonitor.isActive else {
                self.logger.info("Refresh rescheduled due to inactive internet")
                handleOfflineLikeFailure(
                    error: nil,
                    enableOfflineMode: enableOfflineMode,
                    attempts: attempts
                )
                return false
            }
        }

        // Reset effective attempts when transitioning from offline back to online.
        // Connectivity-inflated counters should not cause premature credential wipe
        // on the first non-connectivity error after reconnection.
        let effectiveAttempts: Int
        if self.lastAttemptReason == .noNetwork {
            self.logger.info("Network was unavailable (accumulated attempts: \(attempts)), resetting counter for online retry.")
            effectiveAttempts = 0
        } else {
            effectiveAttempts = attempts
        }

        if effectiveAttempts > 10 {
            self.logger.info("Refresh token attempts exceeded, logging out")
            // Preserve lastActiveTenantId when enableSessionPerTenant is enabled
            if enableSessionPerTenant {
                let preservedTenantId = credentialManager.getLastActiveTenantId()
                self.logger.info("🔵 [SessionPerTenant] Preserving lastActiveTenantId (\(preservedTenantId ?? "nil")) after refresh attempts exceeded")
                self.credentialManager.clear(excludingKeys: [KeychainKeys.lastActiveTenantId.rawValue])
            } else {
                self.credentialManager.clear()
            }
            await MainActor.run {
                self.setInitializing(false)
                self.setIsAuthenticated(false)
                self.setAccessToken(nil)
                self.setRefreshToken(nil)
                self.setRefreshingToken(false)
                self.setIsLoading(false) // last
            }
            return false
        }

        self.lastAttemptReason = nil

        if await self.isLoginInProgress {
            self.logger.info("Skip refreshing token - login in progress")
            return false
        }

        if self.refreshingToken {
            self.logger.info("Skip refreshing token - already in progress")
            return false
        }

        self.logger.info("Refreshing token")
        setRefreshingToken(true)
        defer { setRefreshingToken(false) }

        let preservedTenantId = enableSessionPerTenant ? credentialManager.getLastActiveTenantId() : nil

        // Log token refresh attempt details
        SentryHelper.addBreadcrumb(
            "Token refresh attempt started",
            category: "auth",
            level: .info,
            data: [
                "attempts": attempts,
                "enableSessionPerTenant": enableSessionPerTenant,
                "preservedTenantId": preservedTenantId ?? "nil",
                "hasRefreshToken": true,
                "refreshTokenLength": refreshToken.count,
                "hasAccessToken": accessToken != nil
            ]
        )

        do {
            if enableSessionPerTenant {
                if let preserved = preservedTenantId {
                    self.logger.info("Refreshing token with preserved tenant ID: \(preserved)")
                } else {
                    self.logger.warning("WARNING: No tenant ID stored before token refresh! This should not happen.")
                    SentryHelper.logMessage(
                        "Token refresh attempted without preserved tenant ID",
                        level: .warning,
                        context: [
                            "auth": [
                                "method": "refreshTokenIfNeeded",
                                "attempts": attempts,
                                "enableSessionPerTenant": true
                            ],
                            "error": [
                                "type": "missing_tenant_id"
                            ]
                        ]
                    )
                }
            }

            var data: AuthResponse

            if enableSessionPerTenant, let tenantId = currentTenantId {
                // Try tenant-specific refresh first
                // Include access token if available - it may be needed for tenant-specific refresh
                let currentAccessToken = self.accessToken
                do {
                    self.logger.info("Attempting tenant-specific refresh with tenantId: \(tenantId)")
                    SentryHelper.addBreadcrumb(
                        "Attempting tenant-specific token refresh",
                        category: "auth",
                        level: .info,
                        data: [
                            "tenantId": tenantId,
                            "hasAccessToken": currentAccessToken != nil,
                            "refreshTokenLength": refreshToken.count
                        ]
                    )
                    data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: tenantId, accessToken: currentAccessToken)
                    self.logger.info("Tenant-specific refresh successful")
                } catch {
                    // Intentionally broad fallback: a tenant-scoped refresh can fail even when the
                    // same refresh token is still valid on the standard endpoint after server-side
                    // tenant changes or partial backend rollout.
                    self.logger.warning("Tenant-specific refresh failed: \(error). Falling back to standard OAuth refresh.")
                    SentryHelper.logMessage(
                        "Tenant-specific refresh failed, falling back to standard refresh",
                        level: .warning,
                        context: [
                            "auth": [
                                "method": "refreshTokenIfNeeded",
                                "tenantId": tenantId,
                                "attempts": attempts
                            ],
                            "error": [
                                "type": "tenant_specific_refresh_failed",
                                "message": error.localizedDescription
                            ]
                        ]
                    )
                    data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
                    self.logger.info("Standard OAuth refresh successful (fallback)")
                }
            } else {
                // Standard OAuth refresh for non-per-tenant sessions
                SentryHelper.addBreadcrumb(
                    "Attempting standard OAuth token refresh",
                    category: "auth",
                    level: .info,
                    data: [
                        "refreshTokenLength": refreshToken.count,
                        "enableSessionPerTenant": enableSessionPerTenant
                    ]
                )
                data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
            }

            if enableSessionPerTenant, let preserved = preservedTenantId {
                if credentialManager.getLastActiveTenantId() != preserved {
                    self.logger.warning("CRITICAL: Tenant ID was lost during refresh! Restoring: \(preserved)")
                    credentialManager.saveLastActiveTenantId(preserved)
                }
            }

            await self.setCredentialsInternal(
                accessToken: data.access_token,
                refreshToken: data.refresh_token,
                hydrationMode: .refreshPreserveCachedUser
            )

            let didHydrateAuthenticatedSession = await MainActor.run {
                self.isAuthenticated && self.accessToken != nil && self.refreshToken != nil
            }
            guard didHydrateAuthenticatedSession else {
                self.logger.warning(
                    "Token refresh completed, but credential hydration did not restore an authenticated session"
                )
                return false
            }

            self.logger.info("Token refreshed successfully")

            // Log successful token refresh
            SentryHelper.addBreadcrumb(
                "Token refresh successful",
                category: "auth",
                level: .info,
                data: [
                    "attempts": attempts,
                    "enableSessionPerTenant": enableSessionPerTenant,
                    "preservedTenantId": preservedTenantId ?? "nil",
                    "newAccessTokenLength": data.access_token.count,
                    "newRefreshTokenLength": data.refresh_token.count
                ]
            )

            return true

        } catch let error as FronteggError {
            if case .authError(FronteggError.Authentication.failedToRefreshToken(let message)) = error {
                let tenantIdToPreserve: String? = enableSessionPerTenant
                    ? (preservedTenantId ?? credentialManager.getLastActiveTenantId())
                    : nil

                if enableSessionPerTenant {
                    self.logger.warning("🔵 [SessionPerTenant] Token refresh failed, but preserving tenant ID: \(tenantIdToPreserve ?? "nil")")
                }

                var context: [String: [String: Any]] = [
                    "auth": [
                        "method": "refreshTokenIfNeeded",
                        "attempts": attempts,
                        "enableSessionPerTenant": enableSessionPerTenant,
                        "hasPreservedTenantId": enableSessionPerTenant && preservedTenantId != nil
                    ],
                    "error": [
                        "type": "failed_to_refresh_token",
                        "message": message
                    ]
                ]

                if enableSessionPerTenant {
                    context["auth"] = (context["auth"] ?? [:]).merging([
                        "preservedTenantId": preservedTenantId as Any,
                        "tenantIdToPreserve": tenantIdToPreserve as Any
                    ]) { _, new in new }
                }

                SentryHelper.logMessage(
                    "Api: failed to refresh token, error: \(message)",
                    level: .error,
                    context: context
                )

                if enableSessionPerTenant {
                    self.credentialManager.clear(excludingKeys: [KeychainKeys.lastActiveTenantId.rawValue])
                } else {
                    self.credentialManager.clear()
                }

                await MainActor.run {
                    self.setInitializing(false)
                    self.setIsAuthenticated(false)
                    self.setUser(nil)
                    self.setIsOfflineMode(false)
                    self.setAccessToken(nil)
                    self.setRefreshToken(nil)
                    self.setIsLoading(false)
                }
                return false
            }

            // Everything else → centralized offline-like handler decides
            handleOfflineLikeFailure(
                error: error,
                enableOfflineMode: enableOfflineMode,
                attempts: effectiveAttempts,
                skipNetworkCheck: skipNetworkCheck
            )
            return false

        } catch {
            handleOfflineLikeFailure(
                error: error,
                enableOfflineMode: enableOfflineMode,
                attempts: effectiveAttempts,
                skipNetworkCheck: skipNetworkCheck
            )
            return false
        }
    }

}
