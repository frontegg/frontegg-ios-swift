//
//  FronteggAuth+Refresh.swift
//  FronteggSwift
//

import Foundation
import Dispatch
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Background-task handle that keeps iOS from suspending the app mid-refresh.
/// `end()` is idempotent across the expiration handler and the caller's defer.
#if canImport(UIKit) && !os(watchOS)
fileprivate final class RefreshBackgroundTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var taskId: UIBackgroundTaskIdentifier = .invalid

    @MainActor
    func begin(name: String) {
        lock.lock()
        let current = taskId
        lock.unlock()
        guard current == .invalid else { return }

        let newId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
        lock.lock()
        taskId = newId
        lock.unlock()
    }

    func end() {
        lock.lock()
        let captured = taskId
        taskId = .invalid
        lock.unlock()
        guard captured != .invalid else { return }
        if Thread.isMainThread {
            UIApplication.shared.endBackgroundTask(captured)
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.endBackgroundTask(captured)
            }
        }
    }
}
#endif

extension FronteggAuth {
    func isAutoRefreshBlocked(source: RefreshInvocationSource) -> Bool {
        let disableAutoRefresh = (try? PlistHelper.fronteggConfig())?.disableAutoRefresh ?? false
        return disableAutoRefresh && source == .internalAuto
    }


    func calculateOffset(expirationTime: Int) -> TimeInterval {
        let now = Date().timeIntervalSince1970 * 1000 // Current time in milliseconds
        let remainingTime = (Double(expirationTime) * 1000) - now

        let minRefreshWindow: Double = 20000 // Minimum 20 seconds before expiration, in milliseconds
        let adaptiveRefreshTime = remainingTime * 0.8 // 80% of remaining time

        return remainingTime > minRefreshWindow ? adaptiveRefreshTime / 1000 : max((remainingTime - minRefreshWindow) / 1000, 0)
    }

    func refreshTokenWhenNeeded() {
        if isAutoRefreshBlocked(source: .internalAuto) {
            logger.info("Skipping auto refresh (disableAutoRefresh=true)")
            return
        }
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
                    await self.refreshTokenIfNeededInternal(source: .internalAuto)
                }
                return
            }

            logger.debug("Access token found. Attempting to decode JWT...")

            // Decode the access token to get the expiration time
            let decode = try JWTHelper.decode(jwtToken: accessToken)
            guard let expirationTime = decode["exp"] as? Int else {
                logger.warning("JWT missing exp claim in refreshTokenWhenNeeded. Refreshing immediately.")
                Task {
                    await self.refreshTokenIfNeededInternal(source: .internalAuto)
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
                    await self.refreshTokenIfNeededInternal(source: .internalAuto)
                }
            } else {
                logger.info("Scheduling token refresh after \(offset) seconds")
                self.scheduleTokenRefresh(offset: offset, source: .internalAuto)
            }
        } catch {
            logger.error("Failed to decode JWT: \(error.localizedDescription)")
            Task {
                await self.refreshTokenIfNeededInternal(source: .internalAuto)
            }
        }
    }



    func scheduleTokenRefresh(
        offset: TimeInterval,
        attempts: Int = 0,
        skipNetworkCheck: Bool = false,
        source: RefreshInvocationSource = .internalAuto
    ) {
        if isAutoRefreshBlocked(source: source) {
            logger.info("Skipping auto refresh scheduling (disableAutoRefresh=true)")
            cancelScheduledTokenRefresh()
            return
        }
        cancelScheduledTokenRefresh()
        logger.info("Schedule token refresh after, (\(offset) s) (attempt: \(attempts))")

        var workItem: DispatchWorkItem? = nil
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let workItem, !workItem.isCancelled else { return }
            Task {
                if await self.isLoginInProgress {
                    self.logger.info(
                        "Scheduled token refresh fired during login. Retrying in \(self.scheduledRefreshDeferredRetryDelay)s"
                    )
                    self.scheduleTokenRefresh(
                        offset: self.scheduledRefreshDeferredRetryDelay,
                        attempts: attempts,
                        skipNetworkCheck: skipNetworkCheck,
                        source: source
                    )
                    return
                }
                await self.refreshTokenIfNeededInternal(
                    source: source,
                    attempts: attempts,
                    skipNetworkCheck: skipNetworkCheck
                )
            }
        }
        refreshTokenDispatch = workItem
        if let workItem {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + offset, execute: workItem)
        }

    }

    func cancelScheduledTokenRefresh() {
        logger.info("Canceling previous refresh token task")
        refreshTokenDispatch?.cancel()
        refreshTokenDispatch = nil
    }

    /// Writes rotated tokens to the keychain before post-refresh work runs so a
    /// mid-flow suspend/kill cannot leave the keychain holding the invalidated
    /// token. Non-throwing: `setCredentialsInternal` saves again on the happy path.
    internal func persistRotatedTokensImmediately(
        accessToken: String,
        refreshToken: String,
        tenantId: String?,
        enableSessionPerTenant: Bool
    ) {
        do {
            if enableSessionPerTenant, let tenantId = tenantId {
                try self.credentialManager.saveTokenForTenant(refreshToken, tenantId: tenantId, tokenType: .refreshToken)
                try self.credentialManager.saveTokenForTenant(accessToken, tenantId: tenantId, tokenType: .accessToken)
                self.logger.info("Persisted rotated tokens to keychain (tenant: \(tenantId)) immediately after refresh")
            } else {
                try self.credentialManager.save(key: KeychainKeys.refreshToken.rawValue, value: refreshToken)
                try self.credentialManager.save(key: KeychainKeys.accessToken.rawValue, value: accessToken)
                self.logger.info("Persisted rotated tokens to keychain (global) immediately after refresh")
            }
        } catch {
            self.logger.error("Failed to persist rotated tokens to keychain immediately after refresh: \(error)")
            SentryHelper.logError(error, context: [
                "auth": [
                    "method": "persistRotatedTokensImmediately",
                    "enableSessionPerTenant": enableSessionPerTenant,
                    "hasTenantId": tenantId != nil
                ],
                "error": [
                    "type": "immediate_rotation_persistence_failed"
                ]
            ])
        }
    }

    public func refreshTokenIfNeeded(attempts: Int = 0, skipNetworkCheck: Bool = false) async -> Bool {
        await refreshTokenIfNeededInternal(
            source: .manualUser,
            attempts: attempts,
            skipNetworkCheck: skipNetworkCheck
        )
    }

    /// Must be called while holding `refreshSerializationLock`.
    private func claimOrStartRefreshTaskLocked(
        source: RefreshInvocationSource,
        attempts: Int,
        skipNetworkCheck: Bool
    ) -> Task<Bool, Never> {
        if let existing = inflightRefreshTask {
            return existing
        }
        let task = Task<Bool, Never> { [weak self] in
            guard let self = self else { return false }
            let result = await self.performRefreshTokenFlow(
                source: source,
                attempts: attempts,
                skipNetworkCheck: skipNetworkCheck
            )
            self.refreshSerializationLock.withLock {
                self.inflightRefreshTask = nil
            }
            return result
        }
        inflightRefreshTask = task
        return task
    }

    internal func refreshTokenIfNeededInternal(
        source: RefreshInvocationSource,
        attempts: Int = 0,
        skipNetworkCheck: Bool = false
    ) async -> Bool {
        let task: Task<Bool, Never> = refreshSerializationLock.withLock {
            claimOrStartRefreshTaskLocked(
                source: source,
                attempts: attempts,
                skipNetworkCheck: skipNetworkCheck
            )
        }
        return await task.value
    }

    /// Body of the serialized refresh; only one instance runs at a time.
    internal func performRefreshTokenFlow(
        source: RefreshInvocationSource,
        attempts: Int = 0,
        skipNetworkCheck: Bool = false
    ) async -> Bool {
        if isAutoRefreshBlocked(source: source) {
            logger.info("Skipping auto refresh (disableAutoRefresh=true)")
            return false
        }
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
                await handleOfflineLikeFailure(
                    error: nil,
                    enableOfflineMode: enableOfflineMode,
                    attempts: attempts,
                    source: source
                )
                return false
            }
        } else {
            // Offline mode not enabled - use NetworkStatusMonitor.isActive (will make /test call)
            guard await NetworkStatusMonitor.isActive else {
                self.logger.info("Refresh rescheduled due to inactive internet")
                await handleOfflineLikeFailure(
                    error: nil,
                    enableOfflineMode: enableOfflineMode,
                    attempts: attempts,
                    source: source
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

        // Keep the app awake for the full rotation window so iOS cannot suspend
        // us between the server rotating the token and the keychain write.
#if canImport(UIKit) && !os(watchOS)
        let bgTaskHandle = RefreshBackgroundTaskHandle()
        await MainActor.run {
            bgTaskHandle.begin(name: "FronteggRefreshToken")
        }
        defer { bgTaskHandle.end() }
#endif

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

            // Persist rotated tokens before setCredentialsInternal so a /me
            // hang or mid-flow kill cannot strand the new refresh token.
            let tenantIdForImmediatePersistence: String? = enableSessionPerTenant
                ? (currentTenantId ?? preservedTenantId ?? credentialManager.getLastActiveTenantId())
                : nil
            persistRotatedTokensImmediately(
                accessToken: data.access_token,
                refreshToken: data.refresh_token,
                tenantId: tenantIdForImmediatePersistence,
                enableSessionPerTenant: enableSessionPerTenant
            )

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
                // If the in-memory refresh token was rotated by another path
                // while our request was in flight, the 401 is stale — don't
                // wipe credentials.
                let currentInMemoryRefreshToken = await MainActor.run { self.refreshToken }
                if let current = currentInMemoryRefreshToken, current != refreshToken {
                    self.logger.warning("Refresh failed but in-memory refresh token has already been rotated; skipping credential wipe")
                    SentryHelper.addBreadcrumb(
                        "Refresh token rotation race detected; skipping logout",
                        category: "auth",
                        level: .warning,
                        data: [
                            "sentRefreshTokenLength": refreshToken.count,
                            "currentRefreshTokenLength": current.count,
                            "attempts": attempts,
                            "enableSessionPerTenant": enableSessionPerTenant
                        ]
                    )
                    return false
                }

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
            await handleOfflineLikeFailure(
                error: error,
                enableOfflineMode: enableOfflineMode,
                attempts: effectiveAttempts,
                skipNetworkCheck: skipNetworkCheck,
                source: source
            )
            return false

        } catch {
            await handleOfflineLikeFailure(
                error: error,
                enableOfflineMode: enableOfflineMode,
                attempts: effectiveAttempts,
                skipNetworkCheck: skipNetworkCheck,
                source: source
            )
            return false
        }
    }

}
