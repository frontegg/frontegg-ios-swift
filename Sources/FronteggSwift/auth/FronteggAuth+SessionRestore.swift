//
//  FronteggAuth+SessionRestore.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import WebKit
import Combine

private let authenticatedStartupNetworkAssessmentTimeout: UInt64 = 500_000_000

extension FronteggAuth {

    @MainActor
    @objc func applicationDidBecomeActive() {
        logger.info("application become active")

        self.flushPendingOAuthErrorPresentationIfNeeded(delayIfNeeded: true)

        if initializing || isLoginInProgress {
            return
        }
        refreshTokenWhenNeeded()
    }
    
    @objc func applicationDidEnterBackground(){
        logger.info("application enter background")
    }

    
    func warmingWebViewAsync() {
        DispatchQueue.main.async {
            self.warmingWebView()
        }
    }
    func warmingWebView() {
        
        self.setIsOfflineMode(false)
        let cfg = WKWebViewConfiguration()
        // use your shared processPool below
        cfg.processPool = WebViewShared.processPool
        // you can even use nonPersistent() if you don't need cookies
        cfg.websiteDataStore = .default()
        let wv = CustomWebView(frame: .zero, configuration: cfg)
        // load a trivial blank page & eval a no-op JS
        
        wv.navigationDelegate = wv;
        wv.uiDelegate = wv;
        
        let (url, _) = AuthorizeUrlGenerator().generate(remainCodeVerifier: true, registerPendingFlow: false)
        wv.load(URLRequest(url: url))
        wv.evaluateJavaScript("void(0)", completionHandler: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Stop any in-flight work
            wv.stopLoading()

            // Drop delegates (they're weak, but do it anyway)
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            wv.scrollView.delegate = nil
            
            // Clear scripts / message handlers if you added any
            wv.configuration.userContentController.removeAllUserScripts()
            if #available(iOS 14.0, *) {
                wv.configuration.userContentController.removeAllScriptMessageHandlers()
            }
            
            // Optionally load about:blank to flush page state (not strictly required)
            wv.loadHTMLString("", baseURL: nil)
            
            // Detach from view hierarchy and release
            wv.removeFromSuperview()
        }
    }
    
    // MARK: Connectivity — see FronteggAuth+Connectivity.swift

    func completeAuthenticatedStartupSessionRestore(
        accessTokenSnapshot: String?,
        refreshTokenSnapshot: String?,
        canRestoreOfflineAuthenticatedState: Bool,
        assessmentProvider: ((UInt64) async -> AuthenticatedStartupNetworkPathAssessment)? = nil,
        postConnectivityServices: (() async -> Void)? = nil
    ) async {
        let assessment: AuthenticatedStartupNetworkPathAssessment
        if let assessmentProvider {
            assessment = await assessmentProvider(authenticatedStartupNetworkAssessmentTimeout)
        } else {
            assessment = await self.assessAuthenticatedStartupNetworkPath(
                timeout: authenticatedStartupNetworkAssessmentTimeout
            )
        }

        let runPostConnectivityServices = postConnectivityServices ?? {
            await self.startPostConnectivityServices()
        }

        self.logger.info(
            "Authenticated startup network assessment: \(assessment.rawValue) (hasRefreshToken: \(refreshTokenSnapshot != nil))"
        )

        switch assessment {
        case .available:
            await performAuthenticatedStartupRefresh(
                skipNetworkCheck: false,
                runPostConnectivityServicesOnFailure: true,
                postConnectivityServices: runPostConnectivityServices
            )
        case .advisoryUnavailable where refreshTokenSnapshot != nil:
            self.logger.info(
                "Authenticated startup path is only advisory-unavailable; attempting refresh with network gate bypassed"
            )
            await performAuthenticatedStartupRefresh(
                skipNetworkCheck: true,
                runPostConnectivityServicesOnFailure: false,
                postConnectivityServices: runPostConnectivityServices
            )
        case .advisoryUnavailable:
            self.logger.info(
                "Authenticated startup path is advisory-unavailable and no refresh token is available; restoring offline state"
            )
            await restoreAuthenticatedStartupOfflineState(
                accessTokenSnapshot: accessTokenSnapshot,
                refreshTokenSnapshot: refreshTokenSnapshot,
                canRestoreOfflineAuthenticatedState: canRestoreOfflineAuthenticatedState
            )
        case .forcedUnavailable:
            self.logger.info("Authenticated startup path is explicitly forced offline; restoring offline state")
            await restoreAuthenticatedStartupOfflineState(
                accessTokenSnapshot: accessTokenSnapshot,
                refreshTokenSnapshot: refreshTokenSnapshot,
                canRestoreOfflineAuthenticatedState: canRestoreOfflineAuthenticatedState
            )
        }
    }

    private func performAuthenticatedStartupRefresh(
        skipNetworkCheck: Bool,
        runPostConnectivityServicesOnFailure: Bool,
        postConnectivityServices: () async -> Void
    ) async {
        await MainActor.run {
            self.setIsLoading(true)
        }

        let refreshed = await self.refreshTokenIfNeededInternal(
            source: .internalAuto,
            skipNetworkCheck: skipNetworkCheck
        )

        if !refreshed {
            await MainActor.run {
                if self.isLoading { self.setIsLoading(false) }
                if self.initializing { self.setInitializing(false) }
            }
        }

        if refreshed || runPostConnectivityServicesOnFailure {
            await postConnectivityServices()
        }
    }

    private func restoreAuthenticatedStartupOfflineState(
        accessTokenSnapshot: String?,
        refreshTokenSnapshot: String?,
        canRestoreOfflineAuthenticatedState: Bool
    ) async {
        self.cancelScheduledTokenRefresh()
        self.ensureOfflineMonitoringActive(emitInitialState: false)

        let offlineUser = self.credentialManager.getOfflineUser()

        if canRestoreOfflineAuthenticatedState {
            if refreshTokenSnapshot != nil && accessTokenSnapshot != nil {
                self.logger.info("Offline restore: full token pair")
            } else if accessTokenSnapshot != nil {
                self.logger.info("Offline restore: access-token-only (no refresh capability)")
            } else {
                self.logger.info("Offline restore: refresh-token + offlineUser")
            }

            await MainActor.run {
                self.setUser(self.user ?? offlineUser)
                self.setIsAuthenticated(true)
                self.setIsOfflineMode(true)
                self.setIsLoading(false)
                self.setInitializing(false)
            }
        } else {
            self.logger.warning("Offline: refresh-token only, no offlineUser. Preserving artifacts, not offline-authenticated.")

            await MainActor.run {
                self.setIsAuthenticated(false)
                self.setIsOfflineMode(true)
                self.setIsLoading(false)
                self.setInitializing(false)
            }
        }
    }


    public func initializeSubscriptions() {
        let config = try? PlistHelper.fronteggConfig()
        let enableOfflineMode = config?.enableOfflineMode ?? false
        let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
        
        self.$initializing.combineLatest(self.$isAuthenticated, self.$isLoading).sink(){ (initializingValue, isAuthenticatedValue, isLoadingValue) in
            self.setShowLoader(initializingValue || (!isAuthenticatedValue && isLoadingValue))
        }.store(in: &subscribers)
        
        var refreshToken: String? = nil
        var accessToken: String? = nil
        
        if enableSessionPerTenant {
            var tenantId: String? = credentialManager.getLastActiveTenantId()
            
            if tenantId == nil {
                if let offlineUser = credentialManager.getOfflineUser() {
                    tenantId = offlineUser.activeTenant.id
                    if let tid = tenantId {
                        credentialManager.saveLastActiveTenantId(tid)
                        logger.info("No local tenant stored, using offline user's tenant: \(tid) (saved as local tenant)")
                    }
                } else {
                    logger.info("No local tenant stored and no offline user available")
                }
            } else if let tenantId = tenantId {
                logger.info("Using LOCAL tenant ID from storage: \(tenantId)")
            }
            
            if let tenantId = tenantId {
                refreshToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken)
                accessToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .accessToken)
            }
            
            // Only fall back to legacy tokens if BOTH tenant-specific tokens are nil
            // This prevents discarding valid tenant-specific tokens during partial migration scenarios
            if refreshToken == nil && accessToken == nil {
                if let legacyRefreshToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue),
                   let legacyAccessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
                    logger.warning("No tenant-specific tokens found, falling back to legacy tokens (migration scenario)")
                    refreshToken = legacyRefreshToken
                    accessToken = legacyAccessToken
                }
            }
        } else {
            // Legacy behavior: load global tokens
            refreshToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue)
            accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue)
        }
        
        // Explicit state categories for startup restore
        let hasAnySessionArtifacts = (refreshToken != nil || accessToken != nil)
        let canRestoreOfflineAuthenticatedState = (accessToken != nil) ||
            (refreshToken != nil && credentialManager.getOfflineUser() != nil)
        // Legacy alias for monitoring setup compatibility
        let hasTokensInKeychain = hasAnySessionArtifacts
        
        if enableOfflineMode {
            NetworkStatusMonitor.configure(baseURLString: "\(self.baseUrl)/test")
            
            let monitoringInterval = config?.networkMonitoringInterval ?? 10
            
            // Track that we're initializing with tokens to prevent subscription from starting monitoring
            if hasTokensInKeychain {
                self.isInitializingWithTokens = true
            }
            
            // Set up subscription to handle future accessToken changes
            // dropCount = 1 (initial nil emission) + 1 if we're about to call setAccessToken
            // Only accessToken changes produce $accessToken emissions; setRefreshToken doesn't.
            let dropCount = (accessToken != nil) ? 2 : 1
            self.$accessToken
                .removeDuplicates()
                .dropFirst(dropCount)
                .sink { [weak self] accessToken in
                    guard let self = self else { return }
                    // Capture generation before async dispatch so we can detect stale
                    // callbacks (e.g. logout advancing the generation while this dispatch
                    // is still queued).
                    let capturedGeneration = self.connectivityGenerationLock.withLock { self.connectivityGeneration }
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self = self else { return }

                        // After initialization, handle normal token changes
                        if accessToken != nil {
                            // If the generation changed since we captured it, another
                            // transition already owns the connectivity state — skip.
                            guard self.isConnectivityGenerationCurrent(capturedGeneration) else {
                                return
                            }
                            // Token was set - ensure monitoring is stopped
                            self.clearTransientConnectivityStateAfterAuthenticatedSuccess()
                        } else {
                            let logoutInProgress = self.logoutTransitionLock.withLock { self.logoutInProgress }
                            if logoutInProgress {
                                return
                            }

                            // If the generation changed since we captured it, another
                            // transition (e.g. logout) already set up monitoring — skip.
                            guard self.isConnectivityGenerationCurrent(capturedGeneration) else {
                                return
                            }

                            // Token was cleared - start monitoring
                            self.stopOfflineMonitoring()
                            self.cancelPendingOfflineDebounce()
                            let generation = self.advanceConnectivityGeneration()
                            
                            let token = NetworkStatusMonitor.addOnChangeReturningToken { [weak self] reachable in
                                guard let self = self else { return }
                                if reachable {
                                    self.reconnectedToInternet(expectedGeneration: generation)
                                } else {
                                    self.disconnectedFromInternet(expectedGeneration: generation)
                                }
                            }
                            self.networkMonitoringToken = token
                            NetworkStatusMonitor.startBackgroundMonitoring(interval: monitoringInterval, onChange: nil)
                        }
                    }
                }.store(in: &subscribers)
            
            if hasTokensInKeychain {
                self.stopOfflineMonitoring()
            }
            
            if let _ = refreshToken, let _ = accessToken {
                // Clear initialization flag - tokens will be set after this block
                self.isInitializingWithTokens = true
            } else {
                // Clear flag if no tokens (initialization complete even without tokens)
                self.isInitializingWithTokens = false
            }
        } else {
            // Clear flag (initialization complete)
            self.isInitializingWithTokens = false
        }

        let refreshTokenSnapshot = refreshToken
        let accessTokenSnapshot = accessToken

        if hasAnySessionArtifacts {
            // Explicitly stop any existing monitoring before setting tokens
            self.clearTransientConnectivityStateAfterAuthenticatedSuccess()

            // Set whichever tokens we have
            if let rt = refreshToken { setRefreshToken(rt) }
            if let at = accessToken { setAccessToken(at) }

            // Clear initialization flag after tokens are set
            self.isInitializingWithTokens = false

            // For offline mode, check network path status without making /test calls
            if enableOfflineMode {
                Task { [accessTokenSnapshot, canRestoreOfflineAuthenticatedState, refreshTokenSnapshot] in
                    await self.completeAuthenticatedStartupSessionRestore(
                        accessTokenSnapshot: accessTokenSnapshot,
                        refreshTokenSnapshot: refreshTokenSnapshot,
                        canRestoreOfflineAuthenticatedState: canRestoreOfflineAuthenticatedState
                    )
                }
            } else {
                // Offline mode not enabled - proceed with normal initialization
                setIsLoading(true)

                Task {
                    if await NetworkStatusMonitor.isActive {
                        await self.startPostConnectivityServices()
                    }
                    let refreshed = await self.refreshTokenIfNeededInternal(source: .internalAuto)

                    // If refresh returned early (e.g., no refresh token), ensure loading/initializing are reset
                    if !refreshed {
                        await MainActor.run {
                            if self.isLoading { self.setIsLoading(false) }
                            if self.initializing { self.setInitializing(false) }
                        }
                    }
                }
            }
        } else {
            if enableOfflineMode {
                // Offline mode: run connectivity race and start monitoring
                Task {
                    let interval = (try? PlistHelper.fronteggConfig())?.networkMonitoringInterval ?? 10
                    _ = await self.completeUnauthenticatedStartupInitialization(
                        monitoringInterval: interval
                    )
                }
            } else {
                // No offline mode, no tokens: load startup services then finalize
                Task {
                    if await NetworkStatusMonitor.isActive {
                        await self.startPostConnectivityServices()
                    }
                    await MainActor.run {
                        self.setIsLoading(false)
                        self.setInitializing(false)
                    }
                }
            }
        }
    }

}
