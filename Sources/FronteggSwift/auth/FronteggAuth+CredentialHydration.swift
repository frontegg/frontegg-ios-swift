//
//  FronteggAuth+CredentialHydration.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

extension FronteggAuth {

    public func setCredentials(accessToken: String, refreshToken: String, user: User? = nil) async {
        await setCredentialsInternal(accessToken: accessToken, refreshToken: refreshToken, user: user, hydrationMode: .authoritative)
    }

    func hydrationModeDescription(_ hydrationMode: CredentialHydrationMode) -> String {
        switch hydrationMode {
        case .authoritative:
            return "authoritative"
        case .refreshPreserveCachedUser:
            return "refreshPreserveCachedUser"
        case .preserveCachedOrDerivedUser:
            return "preserveCachedOrDerivedUser"
        }
    }


    func resolveBestEffortUser(accessToken: String, includeInMemory: Bool = true) -> User? {
        if includeInMemory, let currentUser = self.user {
            return currentUser
        }

        if let offlineUser = self.credentialManager.getOfflineUser() {
            return offlineUser
        }

        guard let claims = try? JWTHelper.decode(jwtToken: accessToken),
              let jwtUser = User.fromJWT(claims) else {
            return nil
        }

        self.logger.info("Using JWT-derived user as best-effort fallback")
        return jwtUser
    }

    func authoritativeUserLoadFailure(from error: Error) -> Error? {
        if case let CredentialHydrationFailure.authoritativeUserLoadFailed(underlying) = error {
            return underlying
        }
        return nil
    }

    func logPreservedSessionAfterAuthoritativeUserLoadFailure(_ error: Error, stage: String) {
        let reflectedError = String(reflecting: error)
        let connectivityFailure = isConnectivityError(error)
        if connectivityFailure {
            self.logger.warning("\(stage) user load failed due to connectivity issues (\(reflectedError)). Preserving session with valid tokens and entering offline mode.")
        } else {
            self.logger.warning("\(stage) user load failed with non-connectivity error (\(reflectedError)). Preserving session because tokens are already valid.")
        }

        SentryHelper.addBreadcrumb(
            "Preserving session after authoritative user load failure",
            category: "auth",
            level: connectivityFailure ? .info : .warning,
            data: [
                "stage": stage,
                "connectivityError": connectivityFailure,
                "error": reflectedError
            ]
        )
    }

    func clearAuthStateAfterHydrationFailure(error: Error, hydrationMode: CredentialHydrationMode) async {
        await MainActor.run {
            self.logger.error("Failed to set credentials (hydrationMode: \(self.hydrationModeDescription(hydrationMode)), error: \(error))")
            setRefreshToken(nil)
            setAccessToken(nil)
            setUser(nil)
            setIsAuthenticated(false)
            setInitializing(false)
            setAppLink(false)
            setIsLoading(false)
        }
    }

    func setCredentialsInternal(accessToken: String, refreshToken: String, user: User? = nil, hydrationMode: CredentialHydrationMode) async {
        self.logger.info("Setting credentials (refresh token length: \(refreshToken.count), hydrationMode: \(hydrationModeDescription(hydrationMode)))")

        var accessToken = accessToken
        var refreshToken = refreshToken

        do {
            let config = try? PlistHelper.fronteggConfig()
            let enableSessionPerTenant = config?.enableSessionPerTenant ?? false

            // Decode token to get tenantId
            var decode = try JWTHelper.decode(jwtToken: accessToken)

            // Resolve user: refresh paths prefer cached user, authoritative paths fetch from /me
            let userToUse: User
            if let providedUser = user {
                userToUse = providedUser
            } else if hydrationMode == .refreshPreserveCachedUser, let existingUser = self.user {
                let jwtTenantId = decode["tenantId"] as? String
                if jwtTenantId != nil && jwtTenantId != existingUser.tenantId {
                    self.logger.info("Refresh path: tenant changed in JWT (\(jwtTenantId!) vs cached \(existingUser.tenantId)), fetching fresh user data")
                    do {
                        let meResult = try await self.api.me(accessToken: accessToken, refreshToken: refreshToken)
                        guard let fetchedUser = meResult.user else {
                            throw FronteggError.authError(.failedToLoadUserData("User data is nil"))
                        }
                        userToUse = fetchedUser
                        if let newTokens = meResult.refreshedTokens {
                            accessToken = newTokens.access_token
                            refreshToken = newTokens.refresh_token
                            decode = try JWTHelper.decode(jwtToken: accessToken)
                            self.logger.info("Refresh path: adopted re-refreshed tokens after tenant correction")
                        }
                    } catch {
                        throw CredentialHydrationFailure.authoritativeUserLoadFailed(error)
                    }
                } else {
                    self.logger.info("Refresh path: using existing in-memory user (tenant unchanged)")
                    userToUse = existingUser
                }
            } else if hydrationMode != .authoritative, let existingUser = self.user {
                self.logger.info("\(hydrationModeDescription(hydrationMode)) path: using existing in-memory user")
                userToUse = existingUser
            } else if hydrationMode != .authoritative,
                      let config = config, config.enableOfflineMode,
                      let offlineUser = self.credentialManager.getOfflineUser() {
                self.logger.info("\(hydrationModeDescription(hydrationMode)) path: using cached offline user")
                userToUse = offlineUser
            } else if hydrationMode == .preserveCachedOrDerivedUser {
                guard let derivedUser = self.resolveBestEffortUser(accessToken: accessToken, includeInMemory: false) else {
                    throw FronteggError.authError(.failedToLoadUserData("No cached or derived user available"))
                }
                self.logger.info("Callback recovery path: using best-effort derived user without /me")
                userToUse = derivedUser
            } else {
                do {
                    let meResult = try await self.api.me(accessToken: accessToken, refreshToken: refreshToken)
                    guard let fetchedUser = meResult.user else {
                        throw FronteggError.authError(.failedToLoadUserData("User data is nil"))
                    }
                    userToUse = fetchedUser
                    if let newTokens = meResult.refreshedTokens {
                        accessToken = newTokens.access_token
                        refreshToken = newTokens.refresh_token
                        decode = try JWTHelper.decode(jwtToken: accessToken)
                        self.logger.info("Adopted re-refreshed tokens from me() call")
                    }
                } catch {
                    throw CredentialHydrationFailure.authoritativeUserLoadFailed(error)
                }
            }

            var tenantIdToUse: String? = nil

            // Store tokens per tenant if enableSessionPerTenant is enabled
            if enableSessionPerTenant {
                logger.info("[SessionPerTenant] setCredentials called with enableSessionPerTenant=true")
                logger.info("[SessionPerTenant] Server's active tenant: \(userToUse.activeTenant.id)")

                if let localTenantId = credentialManager.getLastActiveTenantId() {
                    logger.info("[SessionPerTenant] Found preserved local tenant ID: \(localTenantId)")
                    // Validate that the preserved tenant is still valid for this user
                    if userToUse.tenants.contains(where: { $0.id == localTenantId }) {
                        tenantIdToUse = localTenantId
                        logger.info("[SessionPerTenant] Using LOCAL tenant ID: \(localTenantId) (ignoring server's active tenant: \(userToUse.activeTenant.id))")
                    } else {
                        // Preserved tenant is not valid for this user (e.g., logged in with different account)
                        // Fall back to server's active tenant
                        logger.warning("[SessionPerTenant] Preserved tenant ID (\(localTenantId)) not found in user's tenants list. Available: \(userToUse.tenants.map { $0.id }). Falling back to server's active tenant.")
                        tenantIdToUse = userToUse.activeTenant.id
                        let savedTenantId = userToUse.activeTenant.id
                        self.credentialManager.saveLastActiveTenantId(savedTenantId)
                        logger.info("[SessionPerTenant] Using server's active tenant: \(savedTenantId) (saved as local tenant)")
                    }
                } else {
                    let serverTenantId = userToUse.activeTenant.id
                    logger.warning("[SessionPerTenant] No local tenant stored, using server's active tenant: \(serverTenantId)")
                    tenantIdToUse = serverTenantId
                    self.credentialManager.saveLastActiveTenantId(serverTenantId)
                    logger.info("[SessionPerTenant] Saved server's active tenant: \(serverTenantId) as local tenant")
                }
            }

            var finalUserToUse = userToUse
            if enableSessionPerTenant, let localTenantId = tenantIdToUse {
                logger.info("[SessionPerTenant] Attempting to modify user object to use local tenant: \(localTenantId)")
                if let matchingTenant = userToUse.tenants.first(where: { $0.id == localTenantId }) {
                    do {
                        let userDict = try JSONEncoder().encode(userToUse)
                        var userJson = try JSONSerialization.jsonObject(with: userDict) as! [String: Any]

                        if let matchingTenantData = try? JSONEncoder().encode(matchingTenant),
                           let matchingTenantDict = try? JSONSerialization.jsonObject(with: matchingTenantData) as? [String: Any] {
                            userJson["activeTenant"] = matchingTenantDict
                            userJson["tenantId"] = matchingTenant.tenantId

                            let modifiedUserData = try JSONSerialization.data(withJSONObject: userJson)
                            finalUserToUse = try JSONDecoder().decode(User.self, from: modifiedUserData)

                            if localTenantId != userToUse.activeTenant.id {
                                logger.info("[SessionPerTenant] Modified user to use local tenant (\(localTenantId)) instead of server's active tenant (\(userToUse.activeTenant.id))")
                            } else {
                                logger.info("[SessionPerTenant] User already matches local tenant (\(localTenantId))")
                            }
                        } else {
                            logger.warning("[SessionPerTenant] Failed to encode matching tenant data")
                        }
                    } catch {
                        logger.warning("[SessionPerTenant] Failed to modify user for local tenant: \(error). Using server's active tenant.")
                    }
                } else {
                    logger.error("[SessionPerTenant] Local tenant ID (\(localTenantId)) not found in user's tenants list. This should not happen. Available tenants: \(userToUse.tenants.map { $0.id })")
                }
            }

            // Set in-memory state FIRST before saving to keychain
            // This ensures user stays logged in even if keychain save fails
            let userToSet = finalUserToUse
            let refreshOffset: TimeInterval?
            if let expirationTime = decode["exp"] as? Int {
                refreshOffset = calculateOffset(expirationTime: expirationTime)
            } else {
                refreshOffset = nil
                logger.warning("JWT missing exp claim during credential setup. Skipping refresh scheduling until a later refresh check.")
            }
            let accessTokenToSet = accessToken
            let refreshTokenToSet = refreshToken
            let shouldEnterOfflineMode = hydrationMode == .preserveCachedOrDerivedUser
            if !shouldEnterOfflineMode {
                clearTransientConnectivityStateAfterAuthenticatedSuccess()
            }
            await MainActor.run {
                setRefreshToken(refreshTokenToSet)
                setAccessToken(accessTokenToSet)
                setUser(userToSet)
                setIsAuthenticated(true)
                setIsOfflineMode(shouldEnterOfflineMode)
                setAppLink(false)
                setInitializing(false)
                setIsStepUpAuthorization(false)

                // isLoading must be at the bottom
                setIsLoading(false)

                if !shouldEnterOfflineMode, let refreshOffset {
                    scheduleTokenRefresh(offset: refreshOffset)
                } else {
                    cancelScheduledTokenRefresh()
                }
                loadEntitlements(forceRefresh: true)
            }

            // Now try to save to keychain (non-critical - user is already logged in)
            do {
                if enableSessionPerTenant, let tenantId = tenantIdToUse {
                    try self.credentialManager.saveTokenForTenant(refreshToken, tenantId: tenantId, tokenType: .refreshToken)
                    try self.credentialManager.saveTokenForTenant(accessToken, tenantId: tenantId, tokenType: .accessToken)
                    logger.info("Saved tokens for tenant: \(tenantId)")
                } else {
                    try self.credentialManager.save(key: KeychainKeys.refreshToken.rawValue, value: refreshToken)
                    try self.credentialManager.save(key: KeychainKeys.accessToken.rawValue, value: accessToken)
                    logger.info("Saved tokens to keychain")
                }

                if let config = config, config.enableOfflineMode {
                    self.credentialManager.saveOfflineUser(user: finalUserToUse)
                    logger.info("Saved offline user data")
                }
            } catch {
                logger.warning("Failed to save credentials to keychain (user will remain logged in for this session): \(error)")
                if let config = config, config.enableOfflineMode {
                    self.credentialManager.saveOfflineUser(user: finalUserToUse)
                }
            }

            // Diagnostic: warn if offline mode is enabled but offline artifacts are missing
            if let config = config, config.enableOfflineMode {
                if self.credentialManager.getOfflineUser() == nil {
                    logger.error("DIAGNOSTIC: enableOfflineMode=true but offline user data was NOT persisted after setCredentials. Offline restore will be degraded.")
                }
            }

        } catch {
            let enableOfflineMode = (try? PlistHelper.fronteggConfig())?.enableOfflineMode ?? false
            if let userLoadFailure = authoritativeUserLoadFailure(from: error),
               enableOfflineMode,
               isConnectivityError(userLoadFailure),
               let resolvedUser = self.resolveBestEffortUser(accessToken: accessToken) {
                self.logPreservedSessionAfterAuthoritativeUserLoadFailure(
                    userLoadFailure,
                    stage: "setCredentialsInternal"
                )
                let enableSessionPerTenant = (try? PlistHelper.fronteggConfig())?.enableSessionPerTenant ?? false
                let accessTokenToSet = accessToken
                let refreshTokenToSet = refreshToken
                await MainActor.run {
                    setRefreshToken(refreshTokenToSet)
                    setAccessToken(accessTokenToSet)
                    setUser(resolvedUser)
                    setIsAuthenticated(true)
                    setIsOfflineMode(true)
                    setInitializing(false)
                    setIsLoading(false)
                }
                // Persist refreshed tokens to keychain so they survive app crash/kill
                do {
                    if enableSessionPerTenant, let tenantId = credentialManager.getLastActiveTenantId() {
                        try credentialManager.saveTokenForTenant(refreshToken, tenantId: tenantId, tokenType: .refreshToken)
                        try credentialManager.saveTokenForTenant(accessToken, tenantId: tenantId, tokenType: .accessToken)
                    } else {
                        try credentialManager.save(key: KeychainKeys.refreshToken.rawValue, value: refreshToken)
                        try credentialManager.save(key: KeychainKeys.accessToken.rawValue, value: accessToken)
                    }
                    credentialManager.saveOfflineUser(user: resolvedUser)
                    self.logger.info("Persisted refreshed tokens to keychain (post-/me failure)")
                } catch {
                    self.logger.warning("Failed to persist refreshed tokens to keychain: \(error)")
                }
                // Schedule token refresh so fresh tokens don't silently expire and /me is reattempted
                let refreshOffset: TimeInterval
                if let decode = try? JWTHelper.decode(jwtToken: accessToken),
                   let exp = decode["exp"] as? Int {
                    refreshOffset = calculateOffset(expirationTime: exp)
                } else {
                    self.logger.warning("Could not decode access token JWT for refresh scheduling, using 30s fallback")
                    refreshOffset = 30
                }
                await MainActor.run {
                    scheduleTokenRefresh(offset: refreshOffset)
                }
                // Start monitoring without an immediate callback so the preserved offline state
                // remains observable until a later probe or connectivity transition.
                ensureOfflineMonitoringActive(emitInitialState: false)
            } else {
                await clearAuthStateAfterHydrationFailure(error: error, hydrationMode: hydrationMode)
            }
        }
    }
}
