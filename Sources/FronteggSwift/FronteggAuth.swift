//
//  FronteggAuth.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import Dispatch
import WebKit
import Combine
import AuthenticationServices
import UIKit
import SwiftUI
import Network



public class FronteggAuth: FronteggState {
    
#if DEBUG
    static var testNetworkPathAvailabilityOverride: Bool? = nil
#endif

    public var embeddedMode: Bool
    public var isRegional: Bool
    public var regionData: [RegionConfig]
    public var baseUrl: String
    public var clientId: String
    public var applicationId: String? = nil
    public var pendingAppLink: URL? = nil
    public var loginHint: String? = nil
    public var lastAttemptReason: AttemptReasonType? = nil
    var activeEmbeddedOAuthFlow: FronteggOAuthFlow = .login
    
    
    weak var webview: CustomWebView? = nil
    
    
    
    public static var shared: FronteggAuth {
        return FronteggApp.shared.auth
    }
    
    let logger = getLogger("FronteggAuth")
    public let credentialManager: CredentialManager
    // internal for extension access (FronteggAuth+AdvancedAuth.swift)
    var multiFactorAuthenticator: MultiFactorAuthenticator
    var stepUpAuthenticator: StepUpAuthenticator
    public var api: Api
    public var featureFlags: FeatureFlags
    public var entitlements: Entitlements
    private var subscribers = Set<AnyCancellable>()
    // internal for extension access (Refresh, Testing, Connectivity)
    var refreshTokenDispatch: DispatchWorkItem?
    var offlineDebounceWork: DispatchWorkItem?
    private let offlineDebounceDelay: TimeInterval = 0.6
    private let unauthenticatedStartupOfflineCommitWindow: TimeInterval = 4.5
    private let unauthenticatedStartupProbeDelay: TimeInterval = 0.5
    private let unauthenticatedStartupProbeTimeout: TimeInterval = 1.0
    var loginCompletion: CompletionHandler? = nil
    // internal for extension access (Connectivity, Testing, SessionRestore)
    var networkMonitoringToken: NetworkStatusMonitor.OnChangeToken?
    // internal for extension access (FronteggAuth+OAuthErrors.swift)
    var pendingOAuthErrorContext: FronteggOAuthErrorContext?
    var pendingOAuthErrorPresentationWorkItem: DispatchWorkItem?
    var pendingEmbeddedOAuthErrorFallbackWorkItem: DispatchWorkItem?
    let oauthErrorPresentationDelay: TimeInterval = 0.35
    let embeddedOAuthErrorRecoveryFallbackDelay: TimeInterval = 1.25
    // internal for extension access (SessionRestore, Testing, Refresh, HostedFlows)
    var isInitializingWithTokens: Bool = false
    @MainActor var isLoginInProgress: Bool = false
    // internal for extension access (FronteggAuth+Entitlements.swift)
    let entitlementsLoadLock = NSLock()
    var entitlementsLoadInProgress: Bool = false
    var entitlementsLoadPendingCompletions: [((Bool) -> Void)] = []
    var entitlementsLoadForceRefreshPending: Bool = false

    internal static func isUserCancelledOAuthFlow(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return true
        }

        if let authError = error as? ASAuthorizationError,
           authError.code == .canceled {
            return true
        }

        return false
    }
    
    init (
        baseUrl:String,
        clientId: String,
        applicationId: String?,
        credentialManager: CredentialManager,
        isRegional: Bool,
        regionData: [RegionConfig],
        embeddedMode: Bool,
        isLateInit: Bool? = false,
        entitlementsEnabled: Bool = false
    ) {
        self.isRegional = isRegional
        self.regionData = regionData
        self.credentialManager = credentialManager

        self.embeddedMode = embeddedMode
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
        self.entitlements = Entitlements(.init(api: self.api, enabled: entitlementsEnabled))
        self.multiFactorAuthenticator = MultiFactorAuthenticator(api: api, baseUrl: baseUrl)
        self.stepUpAuthenticator = StepUpAuthenticator(credentialManager: credentialManager)
        
        super.init()
        setLateInit(isLateInit ?? false)
        setSelectedRegion(self.getSelectedRegion())
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        if ( isRegional || isLateInit == true ) {
            setInitializing(false)
            setShowLoader(false)
            return;
        }
        
        
        self.initializeSubscriptions()
    }
    
    
    deinit {
        // Remove the observer when the instance is deallocated
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    
    // MARK: Region Management — see FronteggAuth+RegionManagement.swift
    // MARK: Entitlements — see FronteggAuth+Entitlements.swift

    @MainActor
    @objc private func applicationDidBecomeActive() {
        logger.info("application become active")

        self.flushPendingOAuthErrorPresentationIfNeeded(delayIfNeeded: true)

        if initializing || isLoginInProgress {
            return
        }
        refreshTokenWhenNeeded()
    }
    
    @objc private func applicationDidEnterBackground(){
        logger.info("application enter background")
    }

    
    private func warmingWebViewAsync() {
        DispatchQueue.main.async {
            self.warmingWebView()
        }
    }
    private func warmingWebView() {
        
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
    
    public func reconnectedToInternet() {
        // Always cancel a pending debounced offline transition first.
        // Quick reconnects during startup can otherwise leave a stale work item
        // that flips `isOfflineMode` to true after reachability has already recovered.
        offlineDebounceWork?.cancel()
        offlineDebounceWork = nil

        if(self.isOfflineMode == false){
            return;
        }
        self.logger.info("Connected to the internet")
        self.setIsOfflineMode(false)

        // Keep monitoring active — don't stop it here.
        // If refreshTokenIfNeeded() succeeds, $accessToken subscription stops monitoring.
        // If it fails, monitoring stays active to detect the next reconnection.

        Task {
            // Refresh tokens to get fresh tokens + re-fetch /me user data
            _ = await self.refreshTokenIfNeeded()
            await self.startPostConnectivityServices()
        }
    }
    public func disconnectedFromInternet() {
        
        self.logger.info("Disconnected from the internet (debounced)")
        // Debounce setting offline to avoid brief flicker on quick reconnects
        offlineDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Only set offline if still disconnected (best effort via lastAttemptReason or state)
            // We rely on reconnectedToInternet() to cancel this when path is back.
            self.setIsOfflineMode(true)
        }
        offlineDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + offlineDebounceDelay, execute: work)
    }

    @discardableResult
    func settleUnauthenticatedStartupConnectivity(
        initialNetworkAvailable: Bool,
        debounceDelay: TimeInterval? = nil,
        recoveryProbeCount: Int = 2,
        connectivityProbe: @escaping () async -> Bool
    ) async -> Bool {
        if initialNetworkAvailable {
            self.setIsOfflineMode(false)
            return true
        }

        let delay = debounceDelay ?? offlineDebounceDelay
        let attempts = max(recoveryProbeCount, 1)

        for _ in 0..<attempts {
            if delay > 0 {
                let nanos = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }

            let recovered = await connectivityProbe()
            if recovered {
                offlineDebounceWork?.cancel()
                offlineDebounceWork = nil
                self.setIsOfflineMode(false)
                return true
            }
        }

        self.setIsOfflineMode(true)
        return false
    }

    @discardableResult
    func completeUnauthenticatedStartupInitialization(
        monitoringInterval: TimeInterval,
        startupProbeTimeout: TimeInterval? = nil,
        offlineCommitWindow: TimeInterval? = nil,
        probeDelay: TimeInterval? = nil,
        connectivityProbe: ((TimeInterval) async -> Bool)? = nil,
        postConnectivityServices: (() async -> Void)? = nil
    ) async -> Bool {
        let probeTimeout = startupProbeTimeout ?? unauthenticatedStartupProbeTimeout
        let commitWindow = offlineCommitWindow ?? unauthenticatedStartupOfflineCommitWindow
        let retryDelay = probeDelay ?? unauthenticatedStartupProbeDelay
        let probe = connectivityProbe ?? { timeout in
            await NetworkStatusMonitor.probeConfiguredReachability(timeout: timeout)
        }
        let runPostConnectivityServices = postConnectivityServices ?? {
            await self.startPostConnectivityServices()
        }

        logger.info(
            "Starting unauthenticated startup connectivity race (window: \(commitWindow)s, probeTimeout: \(probeTimeout)s, retryDelay: \(retryDelay)s)"
        )

        offlineDebounceWork?.cancel()
        offlineDebounceWork = nil
        await MainActor.run {
            self.setIsOfflineMode(false)
        }

        let raceStart = Date()
        var probeCount = 0

        func performProbe() async -> Bool {
            probeCount += 1
            return await probe(probeTimeout)
        }

        var settledOnline = await performProbe()

        while !settledOnline {
            let remaining = commitWindow - Date().timeIntervalSince(raceStart)
            if remaining <= 0 {
                break
            }

            if retryDelay > 0 {
                let sleepSeconds = min(retryDelay, remaining)
                if sleepSeconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                }
            }

            let remainingAfterDelay = commitWindow - Date().timeIntervalSince(raceStart)
            if remainingAfterDelay <= 0 {
                break
            }

            settledOnline = await performProbe()
        }

        logger.info(
            "Unauthenticated startup connectivity settled \(settledOnline ? "online" : "offline") after \(probeCount) probe(s)"
        )

        if settledOnline {
            await MainActor.run {
                self.setIsOfflineMode(false)
            }
            await runPostConnectivityServices()
        } else {
            await MainActor.run {
                self.setIsOfflineMode(true)
            }
        }

        ensureOfflineMonitoringActive(intervalOverride: monitoringInterval, emitInitialState: false)

        await MainActor.run {
            self.setIsLoading(false)
            self.setInitializing(false)
        }

        return settledOnline
    }

    private func startPostConnectivityServices() async {
        await self.featureFlags.start()
        SentryHelper.setSentryEnabledFromFeatureFlag(self.featureFlags.isOn(FeatureFlags.mobileEnableLoggingKey))
        await SocialLoginUrlGenerator.shared.reloadConfigs()
        self.warmingWebViewAsync()
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
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self = self else { return }
                        
                        // After initialization, handle normal token changes
                        if accessToken != nil {
                            // Token was set - ensure monitoring is stopped
                            NetworkStatusMonitor.stopBackgroundMonitoring()
                            if let token = self.networkMonitoringToken {
                                NetworkStatusMonitor.removeOnChange(token)
                                self.networkMonitoringToken = nil
                            }
                        } else {
                            // Token was cleared - start monitoring
                            NetworkStatusMonitor.stopBackgroundMonitoring()
                            if let token = self.networkMonitoringToken {
                                NetworkStatusMonitor.removeOnChange(token)
                                self.networkMonitoringToken = nil
                            }
                            
                            let token = NetworkStatusMonitor.addOnChangeReturningToken { [weak self] reachable in
                                guard let self = self else { return }
                                if reachable {
                                    self.reconnectedToInternet()
                                } else {
                                    self.disconnectedFromInternet()
                                }
                            }
                            self.networkMonitoringToken = token
                            NetworkStatusMonitor.startBackgroundMonitoring(interval: monitoringInterval, onChange: nil)
                        }
                    }
                }.store(in: &subscribers)
            
            if hasTokensInKeychain {
                NetworkStatusMonitor.stopBackgroundMonitoring()
                if let token = self.networkMonitoringToken {
                    NetworkStatusMonitor.removeOnChange(token)
                    self.networkMonitoringToken = nil
                }
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
            NetworkStatusMonitor.stopBackgroundMonitoring()
            if let token = self.networkMonitoringToken {
                NetworkStatusMonitor.removeOnChange(token)
                self.networkMonitoringToken = nil
            }

            // Set whichever tokens we have
            if let rt = refreshToken { setRefreshToken(rt) }
            if let at = accessToken { setAccessToken(at) }

            // Clear initialization flag after tokens are set
            self.isInitializingWithTokens = false

            // For offline mode, check network path status without making /test calls
            if enableOfflineMode {
                Task { [accessTokenSnapshot, canRestoreOfflineAuthenticatedState, refreshTokenSnapshot] in
                    let isNetworkAvailable = await self.checkNetworkPath(timeout: 500_000_000)

                    if !isNetworkAvailable {
                        self.cancelScheduledTokenRefresh()
                        let offlineUser = self.credentialManager.getOfflineUser()

                        if canRestoreOfflineAuthenticatedState {
                            // Log which restore branch was taken
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
                            // refresh-token-only, no offlineUser — preserve artifacts for reconnect
                            // but do NOT show logged-in UI (not enough cached state for meaningful offline access)
                            // Note: this is the only remaining case since we're inside `if hasAnySessionArtifacts`
                            self.logger.warning("Offline: refresh-token only, no offlineUser. Preserving artifacts, not offline-authenticated.")

                            // Restart monitoring so reconnectedToInternet() can trigger a refresh when network returns.
                            // Monitoring was stopped earlier because hasAnySessionArtifacts was true.
                            let token = NetworkStatusMonitor.addOnChangeReturningToken { [weak self] reachable in
                                guard let self = self else { return }
                                if reachable {
                                    self.reconnectedToInternet()
                                } else {
                                    self.disconnectedFromInternet()
                                }
                            }
                            self.networkMonitoringToken = token
                            let interval = (try? PlistHelper.fronteggConfig())?.networkMonitoringInterval ?? 10
                            NetworkStatusMonitor.startBackgroundMonitoring(interval: interval, onChange: nil)

                            await MainActor.run {
                                self.setIsAuthenticated(false)
                                self.setIsOfflineMode(true)
                                self.setIsLoading(false)
                                self.setInitializing(false)
                            }
                        }
                    } else {
                        // Network available — stabilize auth first, then run optional tasks
                        await MainActor.run {
                            self.setIsLoading(true)
                        }

                        let refreshed = await self.refreshTokenIfNeeded()

                        // If refresh returned early (e.g., no refresh token), ensure loading/initializing are reset
                        if !refreshed {
                            await MainActor.run {
                                if self.isLoading { self.setIsLoading(false) }
                                if self.initializing { self.setInitializing(false) }
                            }
                        }

                        // Then run optional network tasks (non-blocking for auth)
                        await self.startPostConnectivityServices()
                    }
                }
            } else {
                // Offline mode not enabled - proceed with normal initialization
                setIsLoading(true)

                Task {
                    if await NetworkStatusMonitor.isActive {
                        await self.startPostConnectivityServices()
                    }
                    let refreshed = await self.refreshTokenIfNeeded()

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
            // No tokens found - keep the loader visible while startup connectivity races the offline timeout.
            Task {
                let interval = (try? PlistHelper.fronteggConfig())?.networkMonitoringInterval ?? 10
                _ = await self.completeUnauthenticatedStartupInitialization(
                    monitoringInterval: interval
                )
            }
        }
    }
    
    
    public func setCredentials(accessToken: String, refreshToken: String, user: User? = nil) async {
        await setCredentialsInternal(accessToken: accessToken, refreshToken: refreshToken, user: user, hydrationMode: .authoritative)
    }

    private func hydrationModeDescription(_ hydrationMode: CredentialHydrationMode) -> String {
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

    private func authoritativeUserLoadFailure(from error: Error) -> Error? {
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

    private func clearAuthStateAfterHydrationFailure(error: Error, hydrationMode: CredentialHydrationMode) async {
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
    
    /// Calculates the optimal delay for refreshing the token based on the expiration time.
    /// - Parameter expirationTime: The expiration time of the token in seconds since the Unix epoch.
    /// - Returns: The calculated offset in seconds before the token should be refreshed. If the remaining time is less than 20 seconds, it returns 0 for immediate refresh.
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

    // MARK: Testing — see FronteggAuth+Testing.swift

    // MARK: Logout — see FronteggAuth+Logout.swift
    
    private func unwrapURLError(_ error: Error) -> URLError? {
        // Walk underlying errors to find a URLError
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code))
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            if underlying.domain == NSURLErrorDomain {
                return URLError(URLError.Code(rawValue: underlying.code))
            }
            // One more level just in case the network error is double-wrapped
            if let deeper = underlying.userInfo[NSUnderlyingErrorKey] as? NSError, deeper.domain == NSURLErrorDomain {
                return URLError(URLError.Code(rawValue: deeper.code))
            }
        }
        return nil
    }
    
    
    
    // MARK: - Offline helpers

    /// Checks network path availability using NWPathMonitor with a timeout.
    /// Path checks are advisory only in restricted-network environments (e.g., aircraft with whitelisted domains).
    /// Actual HTTP request failures remain the authoritative source of truth.
    func checkNetworkPath(timeout: UInt64 = 500_000_000) async -> Bool {
#if DEBUG
        if let override = Self.testNetworkPathAvailabilityOverride {
            return override
        }
#endif
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "NetworkPathCheck.\(UUID().uuidString)")
            final class ResumeState: @unchecked Sendable {
                private let lock = NSLock()
                private var hasResumed = false
                func tryResume() -> Bool {
                    return lock.withLock {
                        guard !hasResumed else { return false }
                        hasResumed = true
                        return true
                    }
                }
            }
            let resumeState = ResumeState()

            monitor.pathUpdateHandler = { path in
                guard resumeState.tryResume() else { return }
                let available = (path.status == .satisfied)
                monitor.cancel()
                continuation.resume(returning: available)
            }
            monitor.start(queue: queue)

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout)
                guard resumeState.tryResume() else { return }
                monitor.cancel()
                self?.logger.info("NWPathMonitor timed out after \(timeout / 1_000_000)ms — treating as offline (advisory)")
                continuation.resume(returning: false)
            }
        }
    }

    /// Resolves stored session artifacts (tokens, offline user, tenant) using consistent precedence:
    /// lastActiveTenantId → user.activeTenant → offlineUser.activeTenant → legacy global tokens.
    func resolveStoredSessionArtifacts(enableSessionPerTenant: Bool) -> StoredSessionArtifacts {
        var refreshToken: String? = nil
        var accessToken: String? = nil
        var tenantId: String? = nil

        if enableSessionPerTenant {
            tenantId = credentialManager.getLastActiveTenantId()
            if tenantId == nil, let user = self.user {
                tenantId = user.activeTenant.id
            }
            if tenantId == nil {
                if let offlineUser = credentialManager.getOfflineUser() {
                    tenantId = offlineUser.activeTenant.id
                }
            }

            if let tid = tenantId {
                refreshToken = try? credentialManager.getTokenForTenant(tenantId: tid, tokenType: .refreshToken)
                accessToken = try? credentialManager.getTokenForTenant(tenantId: tid, tokenType: .accessToken)
            }

            // Fallback to legacy tokens if both tenant-specific tokens are nil
            // Require BOTH legacy tokens to exist (matching initializeSubscriptions behavior)
            if refreshToken == nil && accessToken == nil {
                if let legacyRefresh = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue),
                   let legacyAccess = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
                    refreshToken = legacyRefresh
                    accessToken = legacyAccess
                }
            }
        } else {
            refreshToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue)
            accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue)
        }

        let offlineUser = credentialManager.getOfflineUser()
        return StoredSessionArtifacts(accessToken: accessToken, refreshToken: refreshToken, offlineUser: offlineUser, tenantId: tenantId)
    }

    /// Shared state update for connectivity loss on manual refresh paths.
    /// Does NOT enqueue retries — scheduled refresh paths handle their own retry/backoff logic.
    func applyConnectivityLossState(enableOfflineMode: Bool) async {
        let hasTokens = (self.refreshToken != nil || self.accessToken != nil)
        guard hasTokens else { return }

        if enableOfflineMode {
            let resolvedUser = self.accessToken.flatMap { self.resolveBestEffortUser(accessToken: $0) }
                ?? self.user
                ?? self.credentialManager.getOfflineUser()
            if let resolvedUser, self.credentialManager.getOfflineUser() == nil {
                self.credentialManager.saveOfflineUser(user: resolvedUser)
            }
            await MainActor.run {
                self.setUser(resolvedUser)
                self.setInitializing(false)
                self.setIsAuthenticated(hasTokens)
                self.setIsOfflineMode(true)
                self.setIsLoading(false)
            }
        } else {
            await MainActor.run {
                self.setInitializing(false)
                self.setIsLoading(false)
                // Keep isOfflineMode=false — app didn't opt into offline UX
            }
        }
    }

    /// Manual refresh failures should preserve the cached session and rely on reconnect monitoring
    /// instead of spinning scheduled refresh retries against a disconnected or blocked network.
    func startOfflineMonitoringAfterManualConnectivityFailure(enableOfflineMode: Bool) {
        guard enableOfflineMode else { return }

        let hasTokens = (self.refreshToken != nil || self.accessToken != nil)
        guard hasTokens else { return }

        self.lastAttemptReason = .noNetwork
        self.logger.info("Manual refresh connectivity failure - canceling scheduled token refreshes and starting offline monitoring")
        self.cancelScheduledTokenRefresh()
        self.ensureOfflineMonitoringActive()
    }

    // MARK: - Offline-like handler

    /// Centralized handler for errors that *behave like* no connectivity.
    /// Decides the backoff offset, updates state (including offline user), and reschedules.
    private func handleOfflineLikeFailure(
        error: Error?,
        enableOfflineMode: Bool,
        attempts: Int,
        skipNetworkCheck: Bool = false
    ) {
        // Classify error type
        let isConn = error.map { isConnectivityError($0) } ?? true // treat nil as connectivity (e.g., no active internet path)
        
        if isConn {
            self.logger.info("Refresh rescheduled due to network error \(error?.localizedDescription ?? "(no error)")")
        } else {
            self.logger.info("Refresh rescheduled due to unknown error \(error?.localizedDescription ?? "(no error)")")
        }
        
        // Classify lastAttemptReason based on actual error type
        self.lastAttemptReason = isConn ? .noNetwork : .unknown

        let hasTokens = (self.refreshToken != nil || self.accessToken != nil)
        self.logger.info("handleOfflineLikeFailure: isConn=\(isConn), enableOfflineMode=\(enableOfflineMode), hasTokens=\(hasTokens), attempts=\(attempts), lastAttemptReason=\(isConn ? ".noNetwork" : ".unknown")")

        if enableOfflineMode {
            let resolvedUser = self.accessToken.flatMap { self.resolveBestEffortUser(accessToken: $0) }
                ?? self.user
                ?? self.credentialManager.getOfflineUser()
            if let resolvedUser, self.credentialManager.getOfflineUser() == nil {
                self.credentialManager.saveOfflineUser(user: resolvedUser)
            }
            DispatchQueue.main.async {
                self.setUser(resolvedUser)
                self.setInitializing(false)
                self.setIsAuthenticated(hasTokens)
                self.setIsOfflineMode(true)
                self.setIsLoading(false)
            }

            // If we have tokens and we're offline, DON'T schedule token refreshes
            // This prevents repeated network calls when offline
            if hasTokens {
                self.logger.info("Offline with tokens - canceling scheduled token refreshes to avoid network abuse")
                self.cancelScheduledTokenRefresh()
                // Start monitoring so reconnectedToInternet() fires when network returns
                self.ensureOfflineMonitoringActive()
                return // Don't schedule another refresh — monitoring will handle reconnection
            }
        } else if isConn {
            // enableOfflineMode=false but this is a connectivity error with valid tokens.
            // Preserve isAuthenticated; keep isOfflineMode=false (app didn't opt into offline UX).
            if hasTokens {
                self.logger.info("Connectivity error with valid tokens (offline mode not enabled). Preserving auth state, keeping isOfflineMode=false.")
                DispatchQueue.main.async {
                    self.setInitializing(false)
                    self.setIsLoading(false)
                }
            }
        }

        // When skipNetworkCheck is true and we have tokens, don't schedule refreshes
        // This prevents scheduled refreshes from calling isActive (which triggers /test calls)
        if skipNetworkCheck && hasTokens {
            self.logger.info("Skipping token refresh scheduling to avoid /test calls (offline with tokens)")
            return
        }

        // Exponential backoff for connectivity errors instead of fixed 2s intervals
        let retryOffset: TimeInterval
        if isConn {
            retryOffset = min(TimeInterval(pow(2.0, Double(min(attempts + 2, 6)))), 60)
        } else {
            retryOffset = 1 // non-connectivity errors retry quickly
        }
        self.logger.info("Scheduling retry in \(retryOffset)s (attempt \(attempts + 1), isConn: \(isConn))")
        scheduleTokenRefresh(offset: retryOffset, attempts: attempts + 1, skipNetworkCheck: skipNetworkCheck)
    }
    
    /// Starts network monitoring so that `reconnectedToInternet()` fires when connectivity returns.
    /// Safe to call multiple times — stops existing monitoring first to avoid duplicates.
    func ensureOfflineMonitoringActive(intervalOverride: TimeInterval? = nil, emitInitialState: Bool = true) {
        let config = try? PlistHelper.fronteggConfig()
        let monitoringInterval = intervalOverride ?? config?.networkMonitoringInterval ?? 10

        // Stop existing monitoring to avoid duplicates
        NetworkStatusMonitor.stopBackgroundMonitoring()
        if let token = self.networkMonitoringToken {
            NetworkStatusMonitor.removeOnChange(token)
            self.networkMonitoringToken = nil
        }

        let token = NetworkStatusMonitor.addOnChangeReturningToken { [weak self] reachable in
            guard let self = self else { return }
            if reachable {
                self.reconnectedToInternet()
            } else {
                self.disconnectedFromInternet()
            }
        }
        self.networkMonitoringToken = token
        NetworkStatusMonitor.startBackgroundMonitoring(
            interval: monitoringInterval,
            emitInitialState: emitInitialState,
            onChange: nil
        )
        self.logger.info(
            "Started offline network monitoring (interval: \(monitoringInterval)s, emitInitialState: \(emitInitialState))"
        )
    }

    public func recheckConnection() {
        
        DispatchQueue.global(qos: .background).async {
            
            Task {
                guard await NetworkStatusMonitor.isActive else {
                    self.logger.info("No network connection")
                    return
                }
                self.logger.info("Netowrk is back, refreshing...")
                _ = await self.refreshTokenIfNeeded()
            }
        }
    }
    
    @discardableResult
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
        
        // Hard no-network (quick exit path) — advisory only; actual request errors remain authoritative
        if enableOfflineMode {
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
    
    
    // MARK: OAuth Callbacks — see FronteggAuth+OAuthCallbacks.swift

    
    // MARK: Hosted Flows — see FronteggAuth+HostedFlows.swift
    // MARK: Social Flows — see FronteggAuth+SocialFlows.swift
    // MARK: Embedded & DeepLink — see FronteggAuth+EmbeddedAndDeepLink.swift
    // MARK: Advanced Auth — see FronteggAuth+AdvancedAuth.swift

}
