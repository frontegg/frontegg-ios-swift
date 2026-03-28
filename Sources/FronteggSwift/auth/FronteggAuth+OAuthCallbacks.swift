//
//  FronteggAuth+OAuthCallbacks.swift
//  FronteggSwift
//
//  Created by Frontegg on 2025.
//

import Foundation
import UIKit

extension FronteggAuth {

    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String, _ completion: @escaping FronteggAuth.CompletionHandler) {
        handleHostedLoginCallback(
            code,
            codeVerifier,
            oauthState: nil,
            redirectUri: nil,
            flow: .login,
            completePendingFlowOnSuccess: false,
            completion: completion
        )
    }

    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String?, _ completion: @escaping FronteggAuth.CompletionHandler) {
        handleHostedLoginCallback(
            code,
            codeVerifier,
            oauthState: nil,
            redirectUri: nil,
            flow: .login,
            completePendingFlowOnSuccess: false,
            completion: completion
        )
    }

    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String?, redirectUri: String?, _ completion: @escaping FronteggAuth.CompletionHandler) {
        handleHostedLoginCallback(
            code,
            codeVerifier,
            oauthState: nil,
            redirectUri: redirectUri,
            flow: .login,
            completePendingFlowOnSuccess: false,
            completion: completion
        )
    }

    // MARK: OAuth Errors — see FronteggAuth+OAuthErrors.swift

    func completePendingOAuthFlowIfNeeded(
        oauthState: String?,
        codeVerifier: String?,
        matchedPendingOAuthState: Bool,
        completePendingFlowOnSuccess: Bool
    ) {
        guard completePendingFlowOnSuccess else { return }
        if matchedPendingOAuthState, let oauthState, !oauthState.isEmpty {
            CredentialManager.clearPendingOAuth(state: oauthState)
            CredentialManager.clearCodeVerifierIfMatching(codeVerifier)
            return
        }
        CredentialManager.completePendingOAuthFlow(using: codeVerifier)
    }

    func clearMatchedPendingOAuthFlowIfNeeded(
        oauthState: String?,
        codeVerifier: String?,
        matchedPendingOAuthState: Bool,
        managePendingOAuthFlow: Bool
    ) {
        guard managePendingOAuthFlow,
              matchedPendingOAuthState,
              let oauthState,
              !oauthState.isEmpty else {
            return
        }

        CredentialManager.clearPendingOAuth(state: oauthState)
        CredentialManager.clearCodeVerifierIfMatching(codeVerifier)
    }

    func oauthCodeVerifierError(
        for oauthState: String?,
        resolution: CredentialManager.CodeVerifierResolution
    ) -> FronteggError.Authentication {
        if oauthState != nil && resolution.hasPendingOAuthStates {
            return .invalidOAuthState
        }
        return .codeVerifierNotFound
    }

    func handleHostedLoginCallback(
        _ code: String,
        _ codeVerifier: String?,
        oauthState: String?,
        redirectUri: String?,
        flow: FronteggOAuthFlow = .login,
        completePendingFlowOnSuccess: Bool,
        matchedPendingOAuthState: Bool = false,
        completion: @escaping FronteggAuth.CompletionHandler
    ) {

        Task {
            // Use provided redirectUri or generate default one.
            // For magic link flow, use the redirectUri from the callback URL.
            let redirectUri = redirectUri ?? generateRedirectUri()

            await MainActor.run {
                self.setIsLoading(true)
                self.isLoginInProgress = true
            }

            self.logger.info("Handling hosted login callback (redirectUri: \(redirectUri), hasCodeVerifier: \(codeVerifier != nil))")
            logger.info("Exchanging hosted login callback token")
            let (responseData, error) = await api.exchangeToken(
                code: code,
                redirectUrl: redirectUri,
                codeVerifier: codeVerifier
            )

            if let error {
                logger.error("Hosted login token exchange failed: \(error.localizedDescription)")

                SentryHelper.logError(error, context: [
                    "token_exchange": [
                        "redirectUri": redirectUri,
                        "codeLength": code.count,
                        "codeVerifierUsed": codeVerifier != nil,
                        "method": "handleHostedLoginCallback"
                    ],
                    "error": [
                        "type": "token_exchange_failed",
                        "stage": "api_exchange"
                    ]
                ])

                self.clearMatchedPendingOAuthFlowIfNeeded(
                    oauthState: oauthState,
                    codeVerifier: codeVerifier,
                    matchedPendingOAuthState: matchedPendingOAuthState,
                    managePendingOAuthFlow: completePendingFlowOnSuccess
                )
                self.reportOAuthFailure(error: error, flow: flow)
                await MainActor.run {
                    self.isLoginInProgress = false
                    completion(.failure(error))
                    self.setIsLoading(false)
                    self.setWebLoading(false)
                }
                return
            }

            guard let data = responseData else {
                logger.error("Hosted login token exchange returned nil response data")
                let authError = FronteggError.authError(.failedToAuthenticate)
                self.clearMatchedPendingOAuthFlowIfNeeded(
                    oauthState: oauthState,
                    codeVerifier: codeVerifier,
                    matchedPendingOAuthState: matchedPendingOAuthState,
                    managePendingOAuthFlow: completePendingFlowOnSuccess
                )
                self.reportOAuthFailure(error: authError, flow: flow)
                await MainActor.run {
                    self.isLoginInProgress = false
                    completion(.failure(authError))
                    self.setIsLoading(false)
                    self.setWebLoading(false)
                }
                return
            }

            logger.info("Hosted login token exchange succeeded")

            do {
                logger.info("Going to load user data")
                let meResult = try await self.api.me(
                    accessToken: data.access_token,
                    refreshToken: data.refresh_token
                )
                let hydratedTokens = meResult.refreshedTokens ?? data
                let user = meResult.user

                guard let user = user else {
                    let authError = FronteggError.authError(.failedToLoadUserData("User data is nil"))
                    self.clearMatchedPendingOAuthFlowIfNeeded(
                        oauthState: oauthState,
                        codeVerifier: codeVerifier,
                        matchedPendingOAuthState: matchedPendingOAuthState,
                        managePendingOAuthFlow: completePendingFlowOnSuccess
                    )
                    self.reportOAuthFailure(error: authError, flow: flow)
                    await MainActor.run {
                        self.isLoginInProgress = false
                        completion(.failure(authError))
                        self.setIsLoading(false)
                        self.setWebLoading(false)
                    }
                    return
                }

                await setCredentials(
                    accessToken: hydratedTokens.access_token,
                    refreshToken: hydratedTokens.refresh_token,
                    user: user
                )
                self.completePendingOAuthFlowIfNeeded(
                    oauthState: oauthState,
                    codeVerifier: codeVerifier,
                    matchedPendingOAuthState: matchedPendingOAuthState,
                    completePendingFlowOnSuccess: completePendingFlowOnSuccess
                )

                // Call completion on main thread to avoid race conditions
                // This ensures the completion handler always runs on the main thread
                // Use the user from memory state (which may have been modified to use local tenant)
                await MainActor.run {
                    self.isLoginInProgress = false
                    self.setWebLoading(false)
                    // Return the user from memory state, which may have been modified to use local tenant
                    if let modifiedUser = self.user {
                        completion(.success(modifiedUser))
                    } else {
                        completion(.success(user))
                    }
                }
            } catch {
                logger.error("Hosted login callback failed to load user data: \(error.localizedDescription)")
                let enableOfflineMode = (try? PlistHelper.fronteggConfig())?.enableOfflineMode ?? false

                if enableOfflineMode && isConnectivityError(error) {
                    // Token exchange succeeded — tokens are valid.
                    // Preserve them and enter offline mode instead of discarding.
                    let fallbackUser = self.resolveBestEffortUser(
                        accessToken: data.access_token,
                        includeInMemory: false
                    )
                    if fallbackUser != nil {
                        self.logPreservedSessionAfterAuthoritativeUserLoadFailure(
                            error,
                            stage: "handleHostedLoginCallback"
                        )
                    }

                    guard let fallbackUser else {
                        let authError = FronteggError.authError(.failedToLoadUserData(error.localizedDescription))
                        self.clearMatchedPendingOAuthFlowIfNeeded(
                            oauthState: oauthState,
                            codeVerifier: codeVerifier,
                            matchedPendingOAuthState: matchedPendingOAuthState,
                            managePendingOAuthFlow: completePendingFlowOnSuccess
                        )
                        self.reportOAuthFailure(error: authError, flow: flow)
                        await MainActor.run {
                            self.isLoginInProgress = false
                            completion(.failure(authError))
                            self.setIsLoading(false)
                            self.setWebLoading(false)
                        }
                        return
                    }

                    await self.setCredentialsInternal(
                        accessToken: data.access_token,
                        refreshToken: data.refresh_token,
                        user: fallbackUser,
                        hydrationMode: .preserveCachedOrDerivedUser
                    )
                    let hydratedSession = await MainActor.run {
                        (isAuthenticated: self.isAuthenticated, user: self.user)
                    }
                    guard hydratedSession.isAuthenticated,
                          let resolvedUser = hydratedSession.user else {
                        let authError = FronteggError.authError(.failedToAuthenticate)
                        self.clearMatchedPendingOAuthFlowIfNeeded(
                            oauthState: oauthState,
                            codeVerifier: codeVerifier,
                            matchedPendingOAuthState: matchedPendingOAuthState,
                            managePendingOAuthFlow: completePendingFlowOnSuccess
                        )
                        self.reportOAuthFailure(error: authError, flow: flow)
                        await MainActor.run {
                            self.isLoginInProgress = false
                            completion(.failure(authError))
                            self.setIsLoading(false)
                            self.setWebLoading(false)
                        }
                        return
                    }
                    await MainActor.run {
                        self.setIsOfflineMode(true)
                    }
                    self.ensureOfflineMonitoringActive(emitInitialState: false)
                    self.completePendingOAuthFlowIfNeeded(
                        oauthState: oauthState,
                        codeVerifier: codeVerifier,
                        matchedPendingOAuthState: matchedPendingOAuthState,
                        completePendingFlowOnSuccess: completePendingFlowOnSuccess
                    )
                    await MainActor.run {
                        self.isLoginInProgress = false
                        self.setWebLoading(false)
                        completion(.success(resolvedUser))
                    }
                } else {
                    let authError = FronteggError.authError(.failedToLoadUserData(error.localizedDescription))
                    self.clearMatchedPendingOAuthFlowIfNeeded(
                        oauthState: oauthState,
                        codeVerifier: codeVerifier,
                        matchedPendingOAuthState: matchedPendingOAuthState,
                        managePendingOAuthFlow: completePendingFlowOnSuccess
                    )
                    self.reportOAuthFailure(error: authError, flow: flow)
                    await MainActor.run {
                        self.isLoginInProgress = false
                        completion(.failure(authError))
                        self.setIsLoading(false)
                        self.setWebLoading(false)
                    }
                }
                return
            }

        }

    }


    public func getOrRefreshAccessTokenAsync() async throws -> String? {
        self.logger.info("Waiting for isLoading | initializing | refreshingToken indicators")

        let maxAttempts = 100 // Max waiting attempts to avoid infinite loops (20 seconds total)
        var attempt = 0
        while (self.isLoading || self.initializing || self.refreshingToken) && attempt < maxAttempts {
            try await Task.sleep(nanoseconds: 200_000_000) // Sleep for 200ms
            attempt += 1
        }

        if attempt == maxAttempts {
            self.logger.error("Timeout while waiting for isLoading to complete (20 seconds)")
            throw FronteggError.authError(.failedToAuthenticate)
        }

        self.logger.info("Checking if refresh token exists")

        let config = try? PlistHelper.fronteggConfig()
        let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
        let enableOfflineMode = config?.enableOfflineMode ?? false

        // Reload both refresh and access tokens from storage using consistent precedence
        let artifacts = resolveStoredSessionArtifacts(enableSessionPerTenant: enableSessionPerTenant)

        // Reload refresh token
        var refreshToken = self.refreshToken
        if refreshToken == nil, let storedRefresh = artifacts.refreshToken {
            self.logger.info("Reloaded refresh token from keychain in getOrRefreshAccessTokenAsync")
            await MainActor.run { setRefreshToken(storedRefresh) }
            refreshToken = storedRefresh
        }

        // Reload access token from keychain if in-memory is nil
        if self.accessToken == nil, let storedAccess = artifacts.accessToken {
            self.logger.info("Reloaded access token from keychain in getOrRefreshAccessTokenAsync")
            await MainActor.run { setAccessToken(storedAccess) }
        }

        guard let refreshToken = refreshToken else {
            self.logger.info("No refresh token found in memory or keychain")
            return nil
        }

        self.logger.info("Check if the access token exists and is still valid")

        if let accessToken = self.accessToken {
            do {
                let decodedToken = try JWTHelper.decode(jwtToken: accessToken)
                if let exp = decodedToken["exp"] as? Int {
                    let offset = self.calculateOffset(expirationTime: exp)
                    self.logger.info("Access token offset: \(offset)")
                    if offset > 15 { // Ensure token has more than 15 seconds validity
                        return accessToken
                    }
                }
            } catch {
                self.logger.error("Failed to decode JWT: \(error.localizedDescription)")
            }
        }

        if enableOfflineMode {
            let isNetworkAvailable = await checkNetworkPath(timeout: 300_000_000)
            if !isNetworkAvailable {
                self.logger.info("Network unavailable in getOrRefreshAccessTokenAsync, returning cached token and entering offline mode")
                await applyConnectivityLossState(enableOfflineMode: enableOfflineMode)
                self.startOfflineMonitoringAfterManualConnectivityFailure(enableOfflineMode: enableOfflineMode)
                return self.accessToken
            }
        }

        self.logger.info("Refreshing access token")

        setRefreshingToken(true)
        defer {
            setRefreshingToken(false)
        }

        // Reuse config and enableSessionPerTenant from earlier in the function
        var currentTenantId: String? = nil

        if enableSessionPerTenant {
            // Prioritize lastActiveTenantId for per-tenant session isolation
            if let localTenantId = credentialManager.getLastActiveTenantId() {
                currentTenantId = localTenantId
                self.logger.info("Using LOCAL tenant ID for refresh in getOrRefreshAccessTokenAsync: \(localTenantId)")
            } else if let user = self.user {
                currentTenantId = user.activeTenant.id
                self.logger.info("No local tenant stored, using user's active tenant: \(currentTenantId!)")
            } else if let offlineUser = credentialManager.getOfflineUser() {
                currentTenantId = offlineUser.activeTenant.id
                self.logger.info("No local tenant stored, using offline user's tenant: \(currentTenantId!)")
            }
        }

        var attempts = 0
        while attempts < 5 {
            do {
                var data: AuthResponse

                if enableSessionPerTenant, let tenantId = currentTenantId {
                    // Try tenant-specific refresh first
                    // Include access token if available - it may be needed for tenant-specific refresh
                    let currentAccessToken = self.accessToken
                    do {
                        self.logger.info("Attempting tenant-specific refresh with tenantId: \(tenantId) in getOrRefreshAccessTokenAsync")
                        data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: tenantId, accessToken: currentAccessToken)
                        self.logger.info("Tenant-specific refresh successful in getOrRefreshAccessTokenAsync")
                    } catch {
                        // Keep the fallback broad here too: the tenant endpoint can reject a refresh
                        // while the standard endpoint still accepts it during recovery/migration.
                        self.logger.warning("Tenant-specific refresh failed in getOrRefreshAccessTokenAsync: \(error). Falling back to standard OAuth refresh.")
                        data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
                        self.logger.info("Standard OAuth refresh successful (fallback) in getOrRefreshAccessTokenAsync")
                    }
                } else {
                    // Standard OAuth refresh for non-per-tenant sessions
                    data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
                }

                await self.setCredentialsInternal(accessToken: data.access_token, refreshToken: data.refresh_token, hydrationMode: .refreshPreserveCachedUser)
                self.logger.info("Token refreshed successfully")
                return self.accessToken
            } catch let error as FronteggError {
                if case .authError(FronteggError.Authentication.failedToRefreshToken(let message)) = error {
                    SentryHelper.logMessage(
                        "Api: failed to refresh token, error: \(message)",
                        level: .error,
                        context: [
                            "auth": [
                                "method": "getOrRefreshAccessTokenAsync",
                                "attempts": attempts + 1,
                                "enableSessionPerTenant": enableSessionPerTenant
                            ],
                            "error": [
                                "type": "failed_to_refresh_token",
                                "message": message
                            ]
                        ]
                    )
                    return nil
                }
                self.logger.error("Failed to refresh token: \(error.localizedDescription), retrying... (\(attempts + 1) attempts)")

                SentryHelper.logError(error, context: [
                    "auth": [
                        "method": "getOrRefreshAccessTokenAsync",
                        "attempts": attempts + 1,
                        "enableSessionPerTenant": enableSessionPerTenant
                    ],
                    "error": [
                        "type": "token_refresh_error"
                    ]
                ])

                // Note: FronteggError is a custom enum, not a URL/POSIX error.
                // Real connectivity errors (URLError) are caught by the generic catch below.
                attempts += 1
                try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep for 1 second before retrying
            } catch {
                self.logger.error("Unknown error while refreshing token: \(error.localizedDescription), retrying... (\(attempts + 1) attempts)")

                SentryHelper.logError(error, context: [
                    "auth": [
                        "method": "getOrRefreshAccessTokenAsync",
                        "attempts": attempts + 1,
                        "enableSessionPerTenant": enableSessionPerTenant
                    ],
                    "error": [
                        "type": "unknown_token_refresh_error"
                    ]
                ])

                // On connectivity error while offline, return cached token instead of retrying
                if enableOfflineMode && isConnectivityError(error) {
                    self.logger.info("Connectivity error in getOrRefreshAccessTokenAsync, preserving cached session and returning cached token")
                    await applyConnectivityLossState(enableOfflineMode: enableOfflineMode)
                    self.startOfflineMonitoringAfterManualConnectivityFailure(enableOfflineMode: enableOfflineMode)
                    return self.accessToken
                }

                attempts += 1
                try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep for 1 second before retrying
            }
        }

        throw FronteggError.authError(.failedToAuthenticate)
    }

    public func getOrRefreshAccessToken(_ completion: @escaping FronteggAuth.AccessTokenHandler) {
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let token = try await self.getOrRefreshAccessTokenAsync()
                    DispatchQueue.main.async {
                        completion(.success(token))
                    }
                } catch let error as FronteggError {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                } catch {
                    self.logger.error("Failed to get or refresh token: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    func pendingOAuthState(from url: URL) -> String? {
        CredentialManager.pendingOAuthState(from: url)
    }

    func matchesGeneratedRedirectUri(_ url: URL) -> Bool {
        guard
            let expected = URLComponents(string: generateRedirectUri()),
            let actual = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return false
        }

        return actual.scheme == expected.scheme
            && actual.host == expected.host
            && actual.path == expected.path
    }

    internal func createOauthCallbackHandler(
        _ completion: @escaping FronteggAuth.CompletionHandler,
        allowLastCodeVerifierFallback: Bool = false,
        redirectUriOverride: String? = nil,
        pendingOAuthState: String? = nil,
        flow: FronteggOAuthFlow = .login
    ) -> ((URL?, Error?) -> Void) {

        return { [weak self] callbackUrl, error in
            guard let self = self else { return }

            func clearPendingOAuthState(_ state: String?) {
                guard let state, !state.isEmpty else {
                    return
                }
                CredentialManager.clearPendingOAuth(state: state)
            }

            func clearRelevantPendingOAuthState(callbackState: String?) {
                clearPendingOAuthState(callbackState ?? pendingOAuthState)
            }

            if let error {
                clearPendingOAuthState(pendingOAuthState)
                let fronteggError = FronteggError.authError(.other(error))
                self.reportOAuthFailure(error: fronteggError, flow: flow)
                completion(.failure(fronteggError))
                return
            }

            guard let url = callbackUrl else {
                clearPendingOAuthState(pendingOAuthState)
                let fronteggError = FronteggError.authError(.unknown)
                self.reportOAuthFailure(error: fronteggError, flow: flow)
                completion(.failure(fronteggError))
                return
            }

            let parsedQueryItems = getQueryItems(url.absoluteString)
            guard let queryItems = parsedQueryItems else {
                clearPendingOAuthState(pendingOAuthState)
                let fronteggError = FronteggError.authError(.failedToExtractCode)
                self.reportOAuthFailure(error: fronteggError, flow: flow)
                completion(.failure(fronteggError))
                return
            }

            let oauthState = queryItems["state"]

            if let failureDetails = self.oauthFailureDetails(from: queryItems) {
                clearRelevantPendingOAuthState(callbackState: oauthState)
                self.reportOAuthFailure(details: failureDetails, flow: flow)
                completion(.failure(failureDetails.error))
                return
            }

            guard let code = queryItems["code"] else {
                let keys = Array(queryItems.keys).sorted()
                SentryHelper.logMessage(
                    "OAuth callback missing code (hosted)",
                    level: .warning,
                    context: [
                        "oauth": [
                            "stage": "createOauthCallbackHandler",
                            "url": url.absoluteString,
                            "queryKeys": keys
                        ],
                        "error": [
                            "type": "oauth_missing_code"
                        ]
                    ]
                )
                // If this is a verification callback and there's no code, the verification might have succeeded
                // but the redirect didn't include the code. In this case, we should inform the user
                // that verification succeeded but they need to try logging in again.
                clearRelevantPendingOAuthState(callbackState: oauthState)
                let fronteggError = FronteggError.authError(.failedToExtractCode)
                self.reportOAuthFailure(error: fronteggError, flow: flow)
                completion(.failure(fronteggError))
                return
            }

            let resolution = CredentialManager.resolveCodeVerifier(
                for: oauthState,
                allowFallback: allowLastCodeVerifierFallback
            )
            guard let codeVerifier = resolution.verifier else {
                let fronteggError = FronteggError.authError(
                    self.oauthCodeVerifierError(for: oauthState, resolution: resolution)
                )
                self.reportOAuthFailure(error: fronteggError, flow: flow)
                completion(.failure(fronteggError))
                return
            }
            if resolution.source == .lastGeneratedFallback {
                self.logger.warning(
                    "Using last generated code verifier fallback for OAuth callback (state present: \(oauthState != nil))"
                )
            }

            self.handleHostedLoginCallback(
                code,
                codeVerifier,
                oauthState: oauthState,
                redirectUri: redirectUriOverride,
                flow: flow,
                completePendingFlowOnSuccess: true,
                matchedPendingOAuthState: resolution.source == .stateMatch,
                completion: completion
            )
        }

    }
    public typealias CompletionHandler = (Result<User, FronteggError>) -> Void

    public typealias AccessTokenHandler = (Result<String?, Error>) -> Void

    public typealias LogoutHandler = (Result<Bool, FronteggError>) -> Void

    public typealias ConditionCompletionHandler = (_ error: FronteggError?) -> Void
}
