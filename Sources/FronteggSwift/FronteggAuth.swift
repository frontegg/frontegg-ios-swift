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


extension UIWindow {
    static var key: UIWindow? {
        return UIApplication.shared.windows.filter {$0.isKeyWindow}.first
    }

    static var fronteggPresentationCandidate: UIWindow? {
        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { scene in
                scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
            }
            .flatMap(\.windows)

        return sceneWindows.first(where: \.isKeyWindow)
            ?? sceneWindows.first(where: { !$0.isHidden && $0.alpha > 0 })
            ?? UIApplication.shared.windows.first(where: \.isKeyWindow)
            ?? UIApplication.shared.windows.last
    }
}

public enum AttemptReasonType {
    case unknown
    case noNetwork
}

private enum CredentialHydrationMode {
    case authoritative              // login, tenant-switch, passkey, apple auth — fetch /me
    case refreshPreserveCachedUser  // token refresh — prefer cached user
    case preserveCachedOrDerivedUser // callback recovery — keep cached/JWT user, skip a second /me
}

private enum CredentialHydrationFailure: Error {
    case authoritativeUserLoadFailed(Error)
}

private struct StoredSessionArtifacts {
    let accessToken: String?
    let refreshToken: String?
    let offlineUser: User?
    let tenantId: String?
}

struct OAuthFailureDetails {
    let error: FronteggError
    let errorCode: String?
    let errorDescription: String?
}


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
    
    private let logger = getLogger("FronteggAuth")
    public let credentialManager: CredentialManager
    private var multiFactorAuthenticator: MultiFactorAuthenticator
    private var stepUpAuthenticator: StepUpAuthenticator
    public var api: Api
    public var featureFlags: FeatureFlags
    public var entitlements: Entitlements
    private var subscribers = Set<AnyCancellable>()
    private var refreshTokenDispatch: DispatchWorkItem?
    private var offlineDebounceWork: DispatchWorkItem?
    private let offlineDebounceDelay: TimeInterval = 0.6
    private let unauthenticatedStartupOfflineCommitWindow: TimeInterval = 4.5
    private let unauthenticatedStartupProbeDelay: TimeInterval = 0.5
    private let unauthenticatedStartupProbeTimeout: TimeInterval = 1.0
    var loginCompletion: CompletionHandler? = nil
    private var networkMonitoringToken: NetworkStatusMonitor.OnChangeToken?
    private var isInitializingWithTokens: Bool = false
    private var isLoginInProgress: Bool = false
    private let entitlementsLoadLock = NSLock()
    private var entitlementsLoadInProgress: Bool = false
    private var entitlementsLoadPendingCompletions: [((Bool) -> Void)] = []
    private var entitlementsLoadForceRefreshPending: Bool = false

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
    
    
    public func manualInit(baseUrl:String, clientId:String, applicationId: String?, entitlementsEnabled: Bool = false) {
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
    
    public func manualInitRegions(regions:[RegionConfig], entitlementsEnabled: Bool = false) {
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

    /// Resets entitlements load state when entitlements instance is replaced (e.g. manualInit, region switch).
    /// Invokes any pending completions with false to indicate the load was aborted.
    private func resetEntitlementsLoadState() {
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

    private func resolveAccessTokenForCurrentUser() -> String? {
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

    private enum EntitlementsLoadNextStep {
        case reload
        case invoke([((Bool) -> Void)])
    }

    private func finishEntitlementsLoadCycle() -> EntitlementsLoadNextStep {
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

    private func performEntitlementsLoad() {
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

    @objc private func applicationDidBecomeActive() {
        logger.info("application become active")

        if initializing || isLoginInProgress {
            return
        }
        refreshTokenWhenNeeded()
    }
    
    @objc private func applicationDidEnterBackground(){
        logger.info("application enter background")
    }

    public func reinitWithRegion(config:RegionConfig) {
        self.baseUrl = config.baseUrl
        self.clientId = config.clientId
        self.applicationId = config.applicationId
        setSelectedRegion(config)
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
        self.entitlements = Entitlements(.init(api: self.api, enabled: FronteggApp.shared.entitlementsEnabled))
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


    private func resolveBestEffortUser(accessToken: String, includeInMemory: Bool = true) -> User? {
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

    private func logPreservedSessionAfterAuthoritativeUserLoadFailure(_ error: Error, stage: String) {
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

    private func setCredentialsInternal(accessToken: String, refreshToken: String, user: User? = nil, hydrationMode: CredentialHydrationMode) async {
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
            await MainActor.run {
                setRefreshToken(refreshTokenToSet)
                setAccessToken(accessTokenToSet)
                setUser(userToSet)
                setIsAuthenticated(true)
                setIsOfflineMode(false)
                setAppLink(false)
                setInitializing(false)
                setIsStepUpAuthorization(false)

                // isLoading must be at the bottom
                setIsLoading(false)

                if let refreshOffset {
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
            // Policy is intentionally broad for /me and /me/tenants: once token exchange or refresh
            // succeeds, preserve the session for any authoritative user-load failure and make the
            // connectivity distinction visible through diagnostics rather than auth state changes.
            if let userLoadFailure = authoritativeUserLoadFailure(from: error),
               enableOfflineMode,
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

    @MainActor
    func resetForTesting(baseUrlOverride: String? = nil) async {
        cancelScheduledTokenRefresh()
        offlineDebounceWork?.cancel()
        offlineDebounceWork = nil

        NetworkStatusMonitor.stopBackgroundMonitoring()
        if let token = networkMonitoringToken {
            NetworkStatusMonitor.removeOnChange(token)
            networkMonitoringToken = nil
        }

        if let activeSession = WebAuthenticator.shared.session {
            activeSession.cancel()
            WebAuthenticator.shared.session = nil
        }
        WebAuthenticator.shared.window = nil

        isInitializingWithTokens = false
        isLoginInProgress = false
        pendingAppLink = nil
        activeEmbeddedOAuthFlow = .login
        loginHint = nil
        loginCompletion = nil
        lastAttemptReason = nil
        webview = nil
#if DEBUG
        Self.testNetworkPathAvailabilityOverride = nil
#endif

        credentialManager.deleteLastActiveTenantId()
        credentialManager.clear()
        CredentialManager.clearPendingOAuthFlows()
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)

        setIsAuthenticated(false)
        setUser(nil)
        setAccessToken(nil)
        setRefreshToken(nil)
        setInitializing(false)
        setShowLoader(false)
        setAppLink(false)
        setWebLoading(false)
        setLoginBoxLoading(false)
        setIsLoading(false)
        setIsOfflineMode(false)
        setRefreshingToken(false)
        setIsStepUpAuthorization(false)
        entitlements.clear()
        resetEntitlementsLoadState()

        await clearWebsiteDataForTesting(baseUrlOverride: baseUrlOverride)
        URLCache.shared.removeAllCachedResponses()
    }

#if DEBUG
    func setTestNetworkPathAvailabilityOverride(_ available: Bool?) {
        Self.testNetworkPathAvailabilityOverride = available
    }
#endif

    @MainActor
    private func clearWebsiteDataForTesting(baseUrlOverride: String?) async {
        let store = WKWebsiteDataStore.default()
        let allWebsiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        guard let host = Self.resolvedTestingResetHost(
            baseUrlOverride: baseUrlOverride,
            currentBaseUrl: baseUrl,
            appBaseUrl: FronteggApp.shared.baseUrl
        ) else {
            logger.warning("resetForTesting could not resolve a scoped host, falling back to global WebKit data cleanup")
            await removeAllWebsiteData(store: store, websiteDataTypes: allWebsiteDataTypes)
            clearSharedCookiesForTesting(host: nil)
            return
        }

        let websiteDataTypes = Self.testingResetWebsiteDataTypes()
        logger.info("resetForTesting clearing scoped web data for host: \(host)")

        let records = await fetchWebsiteDataRecords(store: store, websiteDataTypes: websiteDataTypes)
        let matchingRecords = records.filter {
            Self.shouldRemoveTestingWebsiteDataRecord(named: $0.displayName, forHost: host)
        }

        if !matchingRecords.isEmpty {
            await removeWebsiteData(store: store, websiteDataTypes: websiteDataTypes, records: matchingRecords)
        }

        let storeCookies = await getAllCookies(store: store)
        for cookie in storeCookies where cookieDomain(cookie.domain, matches: host) {
            await deleteCookie(store: store, cookie: cookie)
        }

        clearSharedCookiesForTesting(host: host)
    }

    @MainActor
    private func fetchWebsiteDataRecords(
        store: WKWebsiteDataStore,
        websiteDataTypes: Set<String>
    ) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[WKWebsiteDataRecord], Never>) in
            store.fetchDataRecords(ofTypes: websiteDataTypes) { records in
                continuation.resume(returning: records)
            }
        }
    }

    @MainActor
    private func removeWebsiteData(
        store: WKWebsiteDataStore,
        websiteDataTypes: Set<String>,
        records: [WKWebsiteDataRecord]
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: websiteDataTypes, for: records) {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func removeAllWebsiteData(
        store: WKWebsiteDataStore,
        websiteDataTypes: Set<String>
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: websiteDataTypes, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func getAllCookies(store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    @MainActor
    private func deleteCookie(store: WKWebsiteDataStore, cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.httpCookieStore.delete(cookie) {
                continuation.resume()
            }
        }
    }

    private func clearSharedCookiesForTesting(host: String?) {
        let cookiesToDelete: [HTTPCookie]
        if let host, !host.isEmpty {
            cookiesToDelete = (HTTPCookieStorage.shared.cookies ?? []).filter {
                cookieDomain($0.domain, matches: host)
            }
        } else {
            cookiesToDelete = HTTPCookieStorage.shared.cookies ?? []
        }

        for cookie in cookiesToDelete {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    internal static func resolvedTestingResetHost(
        baseUrlOverride: String?,
        currentBaseUrl: String,
        appBaseUrl: String
    ) -> String? {
        for candidate in [baseUrlOverride, currentBaseUrl, appBaseUrl] {
            guard let candidate,
                  let host = URL(string: candidate)?.host?.lowercased(),
                  !host.isEmpty,
                  host != "late-init.invalid" else {
                continue
            }
            return host
        }
        return nil
    }

    internal static func shouldRemoveTestingWebsiteDataRecord(named displayName: String, forHost host: String) -> Bool {
        let normalizedDisplayName = displayName.lowercased()
        let normalizedHost = host.lowercased()

        return normalizedDisplayName == normalizedHost ||
               normalizedDisplayName.hasSuffix("." + normalizedHost) ||
               normalizedHost.hasSuffix("." + normalizedDisplayName)
    }

    internal static func testingResetWebsiteDataTypes() -> Set<String> {
        var dataTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
            WKWebsiteDataTypeOfflineWebApplicationCache,
        ]

        if #available(iOS 11.3, *) {
            dataTypes.insert(WKWebsiteDataTypeFetchCache)
            dataTypes.insert(WKWebsiteDataTypeServiceWorkerRegistrations)
        }

        if #available(iOS 16.0, *) {
            dataTypes.insert(WKWebsiteDataTypeFileSystem)
        }

        return dataTypes
    }

    public func logout(clearCookie: Bool = true, _ completion: FronteggAuth.LogoutHandler? = nil) {
        Task { @MainActor in
            
            setIsLoading(true)
            
            // Try to reload from keychain if in-memory token is nil
            // This ensures we can invalidate the session on the server even if the token
            // was not loaded into memory (e.g., after app restart)
            let accessTokenForServerLogout = self.accessToken
            var refreshTokenForServerLogout = self.refreshToken
            if refreshTokenForServerLogout == nil {
                if let keychainToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                    self.logger.info("Reloaded refresh token from keychain for logout")
                    refreshTokenForServerLogout = keychainToken
                } else {
                    self.logger.warning("No refresh token found in memory or keychain. Server session may remain active.")
                }
            }

            // Preserve lastActiveTenantId when enableSessionPerTenant is enabled
            // This ensures each device maintains its own tenant context even after logout
            let config = try? PlistHelper.fronteggConfig()
            let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
            
            if enableSessionPerTenant {
                let preservedTenantId = credentialManager.getLastActiveTenantId()
                self.logger.info("🔵 [SessionPerTenant] Preserving lastActiveTenantId (\(preservedTenantId ?? "nil")) for per-tenant session isolation")
                // Clear all items except lastActiveTenantId
                self.credentialManager.clear(excludingKeys: [KeychainKeys.lastActiveTenantId.rawValue])
                self.logger.info("🔵 [SessionPerTenant] Cleared keychain while preserving lastActiveTenantId")
            } else {
                self.credentialManager.deleteLastActiveTenantId()
                self.credentialManager.clear()
            }
            CredentialManager.clearPendingOAuthFlows()

            if clearCookie {
                await self.clearCookie()
            }
            
            setIsAuthenticated(false)
            setUser(nil)
            setAccessToken(nil)
            setRefreshToken(nil)
            setInitializing(false)
            setAppLink(false)
            setIsOfflineMode(false)
            setRefreshingToken(false)
            setIsStepUpAuthorization(false)
            self.lastAttemptReason = nil
            entitlements.clear()

            // Cancel scheduled tasks and stop monitoring
            cancelScheduledTokenRefresh()
            offlineDebounceWork?.cancel()
            offlineDebounceWork = nil
            NetworkStatusMonitor.stopBackgroundMonitoring()
            if let token = self.networkMonitoringToken {
                NetworkStatusMonitor.removeOnChange(token)
                self.networkMonitoringToken = nil
            }

            setIsLoading(false)
            completion?(.success(true))

            Task {
                await self.api.logout(accessToken: accessTokenForServerLogout, refreshToken: refreshTokenForServerLogout)
            }
        }

    }
    
    /// Returns true if `domain` matches `host`, supporting leading dot and subdomains.
    @inline(__always)
    func cookieDomain(_ domain: String, matches host: String) -> Bool {
        let cd = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == cd || host.hasSuffix("." + cd)
    }
    /// Builds a regex-based name matcher using `self.cookieRegex`.
    /// Falls back to `^fe_refresh` if empty or invalid.
    func makeCookieNameMatcher() -> (String) -> Bool {
        let fallback = "^fe_refresh"
        
        var cookieRegex: String?
        if let config = try? PlistHelper.fronteggConfig() {
            cookieRegex = config.cookieRegex
        }
        
        let pattern = (cookieRegex != nil && cookieRegex?.isEmpty == false) ? cookieRegex! : fallback
        do {
            let re = try NSRegularExpression(pattern: pattern)
            return { name in
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                return re.firstMatch(in: name, range: range) != nil
            }
        } catch {
            self.logger.warning("Invalid cookie regex '\(pattern)'. Using fallback '\(fallback)'. Error: \(error.localizedDescription)")
            let re = try! NSRegularExpression(pattern: fallback)
            return { name in
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                return re.firstMatch(in: name, range: range) != nil
            }
        }
    }
    
    
    /// Deletes cookies that match the configured name regex and (optionally) the current host.
    /// - Behavior:
    ///   - If `deleteCookieForHostOnly == true`, restricts deletion to cookies whose domain matches `baseUrl`'s host.
    ///   - If `deleteCookieForHostOnly == false`, deletes any cookie whose name matches the regex (domain-agnostic).
    /// - Awaited to guarantee that deletion completes before continuing logout flow.
    @MainActor
    func clearCookie() async {
        
        var deleteCookieForHostOnly: Bool = true
        var cookieRegex: String?
        if let config = try? PlistHelper.fronteggConfig() {
            deleteCookieForHostOnly = config.deleteCookieForHostOnly
            cookieRegex = config.cookieRegex
        }
        
        let restrictToHost = deleteCookieForHostOnly
        
        // Resolve host only when needed
        let host: String? = {
            guard restrictToHost else { return nil }
            guard let h = URL(string: baseUrl)?.host else {
                logger.warning("Invalid baseUrl; cannot resolve host. Proceeding without domain restriction.")
                return nil
            }
            return h
        }()
        
        let store = WKWebsiteDataStore.default().httpCookieStore
        
        // Fetch all cookies
        let cookies: [HTTPCookie] = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        
        // Deduplicate defensively (name+domain+path is the natural identity)
        let uniqueCookies: [HTTPCookie] = {
            var seen = Set<String>()
            return cookies.filter { c in
                let key = "\(c.name)|\(c.domain)|\(c.path)"
                return seen.insert(key).inserted
            }
        }()
        
        let nameMatches = makeCookieNameMatcher()
        
        // Compose predicate
        let shouldDelete: (HTTPCookie) -> Bool = { cookie in
            guard nameMatches(cookie.name) else { return false }
            guard let h = host else { return true } // no domain restriction
            let match = self.cookieDomain(cookie.domain, matches: h)
            if !match {
                self.logger.debug("Skipping cookie due to domain mismatch: \(cookie.name) @ \(cookie.domain) (host: \(h))")
            }
            return match
        }
        
        let targets = uniqueCookies.filter(shouldDelete)
        
        guard targets.isEmpty == false else {
            self.logger.debug("No cookies matched for deletion. regex: \(cookieRegex ?? "^fe_refresh"), restrictToHost: \(restrictToHost), host: \(host ?? "n/a")")
            return
        }
        
        // Delete sequentially (deterministic, avoids overloading store). If you prefer parallel, see comment below.
        var deleted = 0
        let start = Date()
        
        for cookie in targets {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.delete(cookie) {
                    deleted += 1
                    self.logger.info("Deleted cookie [\(deleted)/\(targets.count)]: \(cookie.name) @ \(cookie.domain)\(cookie.path)")
                    cont.resume()
                }
            }
        }
        
        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        self.logger.info("Cookie cleanup completed. Deleted \(deleted)/\(targets.count) cookies in \(elapsed).")
    }
    
    public func logout() {
        logout { res in
            self.logger.info("Logged out")
        }
    }
    
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
    private func checkNetworkPath(timeout: UInt64 = 500_000_000) async -> Bool {
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
    private func resolveStoredSessionArtifacts(enableSessionPerTenant: Bool) -> StoredSessionArtifacts {
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

    /// Shared state update for connectivity loss. Used by handleOfflineLikeFailure() and getOrRefreshAccessTokenAsync()
    /// so both paths update auth/offline state consistently. Does NOT enqueue retries — only scheduled refresh paths do that.
    private func applyConnectivityLossState(enableOfflineMode: Bool) async {
        let hasTokens = (self.refreshToken != nil || self.accessToken != nil)
        guard hasTokens else { return }

        if enableOfflineMode {
            let offlineUser = self.credentialManager.getOfflineUser()
            await MainActor.run {
                self.setUser(self.user ?? offlineUser)
                self.setInitializing(false)
                self.setIsAuthenticated(true)
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
    private func ensureOfflineMonitoringActive(intervalOverride: TimeInterval? = nil, emitInitialState: Bool = true) {
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
        
        if self.isLoginInProgress {
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
            
            await self.setCredentialsInternal(accessToken: data.access_token, refreshToken: data.refresh_token, hydrationMode: .refreshPreserveCachedUser)
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

    private func normalizedOAuthMessageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalizedValue = value
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedValue.isEmpty else {
            return nil
        }

        return normalizedValue
    }

    private func oauthDisplayMessage(
        errorCode: String?,
        errorDescription: String?,
        fallbackMessage: String? = nil
    ) -> String {
        let normalizedCode = normalizedOAuthMessageComponent(errorCode)
        let normalizedDescription = normalizedOAuthMessageComponent(errorDescription)
        let normalizedFallback = normalizedOAuthMessageComponent(fallbackMessage)

        if let normalizedCode, let normalizedDescription {
            return "\(normalizedCode): \(normalizedDescription)"
        }

        if let normalizedDescription {
            return normalizedDescription
        }

        if let normalizedCode {
            return normalizedCode
        }

        if let normalizedFallback {
            return normalizedFallback
        }

        return FronteggError.authError(.unknown).localizedDescription
    }

    func oauthFailureDetails(
        errorCode: String?,
        errorDescription: String?,
        fallbackError: FronteggError? = nil
    ) -> OAuthFailureDetails {
        let normalizedCode = normalizedOAuthMessageComponent(errorCode)
        let normalizedDescription = normalizedOAuthMessageComponent(errorDescription)
        let message = oauthDisplayMessage(
            errorCode: normalizedCode,
            errorDescription: normalizedDescription,
            fallbackMessage: fallbackError?.localizedDescription
        )

        if normalizedCode != nil || normalizedDescription != nil {
            return OAuthFailureDetails(
                error: FronteggError.authError(.oauthError(message)),
                errorCode: normalizedCode,
                errorDescription: normalizedDescription
            )
        }

        return OAuthFailureDetails(
            error: fallbackError ?? FronteggError.authError(.oauthError(message)),
            errorCode: nil,
            errorDescription: nil
        )
    }

    func oauthFailureDetails(from queryItems: [String: String]) -> OAuthFailureDetails? {
        let errorCode = normalizedOAuthMessageComponent(queryItems["error"])
        let errorDescription = normalizedOAuthMessageComponent(queryItems["error_description"])

        guard errorCode != nil || errorDescription != nil else {
            return nil
        }

        return oauthFailureDetails(
            errorCode: errorCode,
            errorDescription: errorDescription
        )
    }

    private func shouldSuppressOAuthErrorPresentation(for error: FronteggError) -> Bool {
        switch error {
        case .authError(let authError):
            switch authError {
            case .operationCanceled:
                return true
            case .other(let underlyingError):
                return Self.isUserCancelledOAuthFlow(underlyingError)
            default:
                return false
            }
        default:
            return false
        }
    }

    internal func reportOAuthFailure(
        error: FronteggError,
        flow: FronteggOAuthFlow,
        errorCode: String? = nil,
        errorDescription: String? = nil,
        embeddedMode: Bool? = nil
    ) {
        guard !shouldSuppressOAuthErrorPresentation(for: error) else {
            return
        }

        let context = FronteggOAuthErrorContext(
            displayMessage: oauthDisplayMessage(
                errorCode: errorCode,
                errorDescription: errorDescription,
                fallbackMessage: error.localizedDescription
            ),
            errorCode: normalizedOAuthMessageComponent(errorCode),
            errorDescription: normalizedOAuthMessageComponent(errorDescription),
            error: error,
            flow: flow,
            embeddedMode: embeddedMode ?? self.embeddedMode
        )

        Task { @MainActor in
            switch FronteggOAuthErrorRuntimeSettings.presentation {
            case .toast:
                let window = self.resolveOAuthErrorPresentationWindow()
                if window == nil {
                    self.logger.warning("OAuth failure toast could not find a presentation window")
                }
                FronteggOAuthToastPresenter.shared.show(message: context.displayMessage, in: window)
            case .delegate:
                FronteggOAuthErrorRuntimeSettings.delegateBox.value?.fronteggSDK(didReceiveOAuthError: context)
            }
        }
    }

    @MainActor
    private func resolveOAuthErrorPresentationWindow() -> UIWindow? {
        if let window = self.webview?.window {
            return window
        }

        if let window = VCHolder.shared.vc?.presentedViewController?.view.window {
            return window
        }

        if let window = VCHolder.shared.vc?.view.window {
            return window
        }

        if let window = self.getRootVC(true)?.view.window {
            return window
        }

        if let window = self.getRootVC()?.view.window {
            return window
        }

        return UIWindow.fronteggPresentationCandidate
    }

    private func completePendingOAuthFlowIfNeeded(
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

    private func clearMatchedPendingOAuthFlowIfNeeded(
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

    private func oauthCodeVerifierError(
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

        // Use provided redirectUri or generate default one
        // For magic link flow, we should use the redirectUri from the callback URL
        let redirectUri = redirectUri ?? generateRedirectUri()
        setIsLoading(true)
        self.isLoginInProgress = true

        logger.info("Handling hosted login callback (redirectUri: \(redirectUri), hasCodeVerifier: \(codeVerifier != nil))")
        
        Task {
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

                if enableOfflineMode {
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
                    guard self.isAuthenticated, let resolvedUser = self.user else {
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

        // If offline, return cached access token (even if near expiry) — no backend call can succeed
        if enableOfflineMode {
            let isNetworkAvailable = await checkNetworkPath(timeout: 300_000_000)
            if !isNetworkAvailable {
                self.logger.info("getOrRefreshAccessTokenAsync: offline, returning cached token if available")
                await applyConnectivityLossState(enableOfflineMode: enableOfflineMode)
                if let cachedToken = self.accessToken {
                    self.logger.info("Returning cached access token while offline (token source: in-memory)")
                    return cachedToken
                }
                self.logger.info("No cached access token available offline, returning nil (not throwing)")
                return nil
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
                    self.logger.info("Connectivity error in getOrRefreshAccessTokenAsync, returning cached token")
                    await applyConnectivityLossState(enableOfflineMode: enableOfflineMode)
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
    private func pendingOAuthState(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?.first(where: { item in
            item.name == "state" && !(item.value?.isEmpty ?? true)
        })?.value
    }

    private func matchesGeneratedRedirectUri(_ url: URL) -> Bool {
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
                self.reportOAuthFailure(
                    error: failureDetails.error,
                    flow: flow,
                    errorCode: failureDetails.errorCode,
                    errorDescription: failureDetails.errorDescription
                )
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
    
    public func login(_ _completion: FronteggAuth.CompletionHandler? = nil, loginHint: String? = nil) {
        
        if(self.embeddedMode){
            self.embeddedLogin(_completion, loginHint: loginHint)
            return
        }
        
        let completion = _completion ?? { res in
            
        }
        
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: loginHint)
        CredentialManager.saveCodeVerifier(codeVerifier)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .login
        )
        
        
        WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
    }
    
    
    func saveWebCredentials(domain: String, email: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        let domainString = domain
        let account = email
        
        SecAddSharedWebCredential(domainString as CFString, account as CFString, password as CFString) { error in
            if let error = error {
                self.logger.error("Failed to save shared web credentials: \(error.localizedDescription)")
                completion(false, error)
            } else {
                self.logger.info("Shared web credentials saved successfully")
                completion(true, nil)
            }
        }
    }
    
    
    
    public func loginWithPopup(window: UIWindow?, ephemeralSession: Bool? = true, loginHint: String? = nil, loginAction: String? = nil, _completion: FronteggAuth.CompletionHandler? = nil) {
        
        let completion = _completion ?? { res in
            
        }
        
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: loginHint, loginAction: loginAction)
        CredentialManager.saveCodeVerifier(codeVerifier)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: loginAction != nil,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .login
        )
        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: ephemeralSession ?? true, window:window,  completionHandler: oauthCallback)
    }
    
    
    /// Starts a social login flow.
    ///
    /// - Parameters:
    ///   - providerString: The social provider raw value (e.g., "google", "facebook", "apple").
    ///   - action: The social login action to perform (default: `.login`).
    ///   - completion: Optional completion handler. A no-op is used if nil.
    public func handleSocialLogin(
        providerString: String,
        custom:Bool,
        action: SocialLoginAction = .login,
        completion: FronteggAuth.CompletionHandler? = nil
    ) {
        FronteggRuntime.testingLog(
            "E2E handleSocialLogin start provider=\(providerString) custom=\(custom) action=\(action.rawValue)"
        )
        let done = completion ?? { _ in }
        
        // Special-case Apple to keep branching explicit and fast.
        if providerString == "apple" {
            loginWithApple(done)
            return
        }
        
        let oauthCallback: (URL?, Error?) -> Void = { [weak self] callbackURL, error in
            guard let self else { return }
            
            if let error {
                self.logger.error("OAuth error: \(String(describing: error))")
                let fronteggError = FronteggError.authError(.other(error))
                self.activeEmbeddedOAuthFlow = .login
                self.reportOAuthFailure(error: fronteggError, flow: .socialLogin)
                return
            }
            
            guard let callbackURL else {
                self.logger.info("OAuth callback invoked with nil URL and no error")
                self.activeEmbeddedOAuthFlow = .login
                self.reportOAuthFailure(
                    error: FronteggError.authError(.unknown),
                    flow: .socialLogin
                )
                return
            }
            
            self.logger.debug("OAuth callback URL: \(callbackURL.absoluteString)")

            if let queryItems = getQueryItems(callbackURL.absoluteString),
               let failureDetails = self.oauthFailureDetails(from: queryItems) {
                self.activeEmbeddedOAuthFlow = .login
                self.reportOAuthFailure(
                    error: failureDetails.error,
                    flow: .socialLogin,
                    errorCode: failureDetails.errorCode,
                    errorDescription: failureDetails.errorDescription
                )
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                guard let finalURL = self.handleSocialLoginCallback(callbackURL) else {
                    SentryHelper.logMessage(
                        "Social login callback could not be parsed (hosted)",
                        level: .warning,
                        context: [
                            "social_login": [
                                "provider": providerString,
                                "callbackUrl": callbackURL.absoluteString,
                                "baseUrl": FronteggAuth.shared.baseUrl
                            ],
                            "error": [
                                "type": "social_login_callback_unhandled"
                            ]
                        ]
                    )
                    self.activeEmbeddedOAuthFlow = .login
                    self.reportOAuthFailure(
                        error: FronteggError.authError(.failedToExtractCode),
                        flow: .socialLogin
                    )
                    return
                }
                self.loadInWebView(finalURL)
            }
        }
        
        Task { [weak self] in
            guard let self else { return }
            
            let generatedAuthUrl: URL? = if(custom){
                try? await SocialLoginUrlGenerator.shared
                    .authorizeURL(forCustomProvider: providerString, action: action)
            } else if let provider = SocialLoginProvider(rawValue: providerString) {
                try? await SocialLoginUrlGenerator.shared
                    .authorizeURL(for: provider, action: action)
            }else {
                nil
            }
            FronteggRuntime.testingLog(
                "E2E handleSocialLogin generatedAuthUrl provider=\(providerString) url=\(generatedAuthUrl?.absoluteString ?? "nil")"
            )

            // Check if we need to use legacy flow
            if generatedAuthUrl == nil && !custom {
                if let provider = SocialLoginProvider(rawValue: providerString),
                   let legacyUrl = try? await SocialLoginUrlGenerator.shared.legacyAuthorizeURL(for: provider, action: action) {
                    logger.debug("Using legacy social login flow for provider: \(providerString)")
                    self.loginWithSocialLogin(socialLoginUrl: legacyUrl, done)
                    return
                }
            }
            
            guard let authURL = generatedAuthUrl else {
                self.logger.error("Failed to generate auth URL for \(providerString)")
                return
            }
            
            self.logger.debug("Auth URL: \(authURL.absoluteString)")
           
             let window: UIWindow? = await MainActor.run {
                return self.getRootVC()?.view.window
            }
            
            let useEphemeral = false
            
            await MainActor.run {
                FronteggRuntime.testingLog(
                    "E2E handleSocialLogin starting WebAuthenticator url=\(authURL.absoluteString)"
                )
                WebAuthenticator.shared.start(
                    authURL,
                    ephemeralSession: useEphemeral,
                    window: window,
                    completionHandler: oauthCallback
                )
            }
        }
    }
    
    private func loadInWebView(_ url: URL) {
        guard let webView = webview else { return }
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
        webView.load(request)
    }
    
    public func directLoginAction(
        window: UIWindow?,
        type: String,
        data: String,
        ephemeralSession: Bool? = true,
        _completion: FronteggAuth.CompletionHandler? = nil,
        additionalQueryParams: [String: Any]? = nil,
        remainCodeVerifier: Bool = false,
        action: SocialLoginAction = SocialLoginAction.login
    ) {
        
        let completion = _completion ?? { res in
            
        }
        
        if(type == "social-login" && data == "apple") {
            self.loginWithApple(completion)
            return
        }
        
        
        var directLogin = [
            "type": type,
            "data": data,
            
        ] as [String : Any]
        
        if let queryParams = additionalQueryParams {
            directLogin["additionalQueryParams"] = queryParams
        }
        
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: remainCodeVerifier)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: remainCodeVerifier)
        }
        
        let (authorizeUrl, codeVerifier) = generatedUrl
        CredentialManager.saveCodeVerifier(codeVerifier)
        let oauthFlow: FronteggOAuthFlow
        switch type {
        case "social-login", "custom-social-login":
            oauthFlow = .socialLogin
        case "direct" where data.contains("/user/sso/") || data.contains("appleid.apple.com"):
            oauthFlow = .socialLogin
        default:
            oauthFlow = .login
        }
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: oauthFlow
        )
        
        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: ephemeralSession ?? true, window: window ?? getRootVC()?.view.window, completionHandler: oauthCallback)
    }
    
    
    internal func getRootVC(_ useAppRootVC: Bool = false) -> UIViewController? {
        
        
        if let appDelegate = UIApplication.shared.delegate,
           let window = appDelegate.window,
           let rootVC = window?.rootViewController {
            
            if(useAppRootVC){
                return rootVC
            }else {
                if let presented = rootVC.presentedViewController {
                    return presented
                }else {
                    return rootVC
                }
            }
        }
        
        if let rootVC = UIWindow.key?.rootViewController {
            return rootVC
        }
        if let lastWindow = UIApplication.shared.windows.last,
           let rootVC = lastWindow.rootViewController {
            return rootVC
        }
        
        
        return nil
    }
    
    
    
    internal func loginWithApple(_ _completion: @escaping FronteggAuth.CompletionHandler)  {
        let completion = handleMfaRequired(_completion)
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do{
                    let config = try PlistHelper.fronteggConfig()
                    let socialConfig =  try await self.api.getSocialLoginConfig()
                    
                    if let appleConfig = socialConfig.apple, appleConfig.active {
                        if #available(iOS 15.0, *), appleConfig.customised, !config.useAsWebAuthenticationForAppleLogin {
                            await AppleAuthenticator.shared.start(completionHandler: completion)
                        }else {
                            let generatedAuth = try await self.generateAppleAuthorizeUrl(config: appleConfig)
                            let oauthCallback = self.createOauthCallbackHandler(
                                completion,
                                allowLastCodeVerifierFallback: true,
                                pendingOAuthState: generatedAuth.pendingOAuthState,
                                flow: .apple
                            )
                            await WebAuthenticator.shared.start(generatedAuth.url, ephemeralSession: true, completionHandler: oauthCallback)
                        }
                    } else {
                        throw FronteggError.configError(.socialLoginMissing("Apple"))
                    }
                } catch {
                    if error is FronteggError {
                        completion(.failure(error as! FronteggError))
                    }else {
                        self.logger.error(error.localizedDescription)
                        completion(.failure(FronteggError.authError(.unknown)))
                    }
                    
                }
            }
            
        }
    }
    
    
    private struct OAuth2SessionStateContext {
        let encodedState: Data
        let pendingOAuthState: String?
    }

    private func createOauth2SessionState() async throws -> OAuth2SessionStateContext {
        let (url, codeVerifier)  = AuthorizeUrlGenerator.shared.generate()
        let pendingOAuthState = pendingOAuthState(from: url)
        
        let (_, authorizeResponse) = try await FronteggAuth.shared.api.getRequest(path: url.absoluteString, accessToken: nil, additionalHeaders: ["Accept":"text/html"])
        
        guard let authorizeResponseUrl = authorizeResponse.url,
              let authorizeComponent = URLComponents(string: authorizeResponseUrl.absoluteString),
              let sessionState = authorizeComponent.queryItems?.first(where: { q in
                  q.name == "state"
              })?.value else {
            throw FronteggError.authError(.failedToAuthenticate)
        }
        
        let redirectUri = generateRedirectUri()
        
        let oauthStateDic = [
            "FRONTEGG_OAUTH_REDIRECT_AFTER_LOGIN": redirectUri,
            "FRONTEGG_OAUTH_STATE_AFTER_LOGIN": sessionState,
        ]
        
        guard let oauthStateJson = try? JSONSerialization.data(withJSONObject: oauthStateDic, options: .withoutEscapingSlashes) else {
            throw FronteggError.authError(.failedToAuthenticate)
        }
        
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        return OAuth2SessionStateContext(
            encodedState: oauthStateJson,
            pendingOAuthState: pendingOAuthState
        )
    }
    func generateAppleAuthorizeUrl(config: SocialLoginOption) async throws -> (url: URL, pendingOAuthState: String?) {
        let sessionState = try await createOauth2SessionState()
        
        let scope = ["openid", "name", "email"] + config.additionalScopes
        let appId = FronteggAuth.shared.applicationId ?? ""
        
        let stateDict = [
            "oauthState": sessionState.encodedState.base64EncodedString(),
            "appId": appId,
            "provider": "apple",
            "action": "login",
        ]
        
        guard let stateJson = try? JSONSerialization.data(withJSONObject: stateDict, options: .withoutEscapingSlashes),
              let state = String(data: stateJson, encoding: .utf8) else {
            throw FronteggError.authError(.failedToAuthenticate)
        }
        
        var urlComponent = URLComponents(string: "https://appleid.apple.com/auth/authorize")!
        urlComponent.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "response_mode", value: "form_post"),
            URLQueryItem(name: "redirect_uri", value: config.backendRedirectUrl),
            URLQueryItem(name: "scope", value: scope.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "client_id", value: config.clientId)
        ]
        
        let finalUrl = urlComponent.url!
        
        return (finalUrl, sessionState.pendingOAuthState)
    }
    
    func loginWithSocialLogin(socialLoginUrl: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in
            
            
        }
        
        // Log social login initiation
        let isMicrosoft = socialLoginUrl.contains("microsoft") || socialLoginUrl.contains("login.microsoftonline.com")
        // Use shared session (non-ephemeral) for all providers to show saved accounts
        let useEphemeral = false
        
        SentryHelper.addBreadcrumb(
            "Social login initiated (loginWithSocialLogin)",
            category: "social_login",
            level: .info,
            data: [
                "socialLoginUrl": socialLoginUrl,
                "isMicrosoft": isMicrosoft,
                "useEphemeral": useEphemeral,
                "embeddedMode": self.embeddedMode,
                "baseUrl": self.baseUrl
            ]
        )
        
        let directLogin: [String: Any] = [
            "type": "direct",
            "data": socialLoginUrl,
        ]
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: true)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: true)
        }
        
        let (authorizeUrl, codeVerifier) = generatedUrl
        CredentialManager.saveCodeVerifier(codeVerifier)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .socialLogin
        )
        
        logger.info("🔵 [Social Login] Starting social login flow")
        logger.info("🔵 [Social Login] Authorize URL: \(authorizeUrl.absoluteString)")
        logger.info("🔵 [Social Login] Use ephemeral session: \(useEphemeral)")
        
       let window: UIWindow?
        if Thread.isMainThread {
            window = getRootVC()?.view.window
        } else {
            var mainWindow: UIWindow?
            DispatchQueue.main.sync {
                mainWindow = getRootVC()?.view.window
            }
            window = mainWindow
        }
        
         if Thread.isMainThread {
            WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: useEphemeral, window: window, completionHandler: oauthCallback)
        } else {
            DispatchQueue.main.async {
                WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: useEphemeral, window: window, completionHandler: oauthCallback)
            }
        }
    }
    
    
    public func loginWithSSO(email: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in
            
        }
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: email, remainCodeVerifier: true)
        CredentialManager.saveCodeVerifier(codeVerifier)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .sso
        )
        
        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: true, window: getRootVC()?.view.window, completionHandler: oauthCallback)
    }
    
    public func loginWithCustomSSO(ssoUrl: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in
            
        }
        
        let directLogin: [String: Any] = [
            "type": "direct",
            "data": ssoUrl,
        ]
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: true)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: true)
        }
        
        let (authorizeUrl, codeVerifier) = generatedUrl
        CredentialManager.saveCodeVerifier(codeVerifier)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .customSSO
        )
        FronteggRuntime.testingLog("loginWithCustomSSO authorizeUrl: \(authorizeUrl.absoluteString)")

        WebAuthenticator.shared.start(
            authorizeUrl,
            ephemeralSession: true,
            window: getRootVC()?.view.window,
            completionHandler: oauthCallback
        )
    }
    
    public func embeddedLogin(_ _completion: FronteggAuth.CompletionHandler? = nil, loginHint: String?) {
        
        if let rootVC = self.getRootVC() {
            FronteggRuntime.testingLog(
                "E2E embeddedLogin rootVC=\(type(of: rootVC)) presented=\(String(describing: rootVC.presentedViewController)) embeddedMode=\(self.embeddedMode)"
            )
            self.loginHint = loginHint
            if self.pendingAppLink == nil {
                self.activeEmbeddedOAuthFlow = .login
            }
            if self.loginCompletion != nil {
                logger.info("Login request ignored, Embedded login already in progress.")
                return
            }
            self.loginCompletion = { result in
                _completion?(result)
                self.loginCompletion = nil
            }
            let loginModal = EmbeddedLoginModal(parentVC: rootVC)
            let hostingController = UIHostingController(rootView: loginModal)
            hostingController.modalPresentationStyle = .fullScreen
            
            if(rootVC.presentedViewController?.classForCoder == hostingController.classForCoder){
                rootVC.presentedViewController?.dismiss(animated: false)
            }
            
            rootVC.present(hostingController, animated: false, completion: nil)
            FronteggRuntime.testingLog("E2E embeddedLogin present called")

        } else {
            logger.critical(FronteggError.authError(.couldNotFindRootViewController).localizedDescription)
            exit(500)
        }
    }
    public func handleOpenUrl(_ url: URL, _ useAppRootVC: Bool = false, internalHandleUrl:Bool = false) -> Bool {
        logger.info("🔵 [handleOpenUrl] Received URL: \(url.absoluteString)")
        logger.info("🔵 [handleOpenUrl] Base URL: \(self.baseUrl)")
        logger.info("🔵 [handleOpenUrl] URL has prefix baseUrl: \(url.absoluteString.hasPrefix(self.baseUrl))")
        logger.info("🔵 [handleOpenUrl] internalHandleUrl: \(internalHandleUrl)")
        let matchesGeneratedRedirectCallback = matchesGeneratedRedirectUri(url)
        let parsedQueryItems = getQueryItems(url.absoluteString)

        // Log app redirect handling
        SentryHelper.addBreadcrumb(
            "App redirect received (handleOpenUrl)",
            category: "app_redirect",
            level: .info,
            data: [
                "url": url.absoluteString,
                "scheme": url.scheme ?? "nil",
                "host": url.host ?? "nil",
                "path": url.path,
                "query": url.query ?? "nil",
                "baseUrl": self.baseUrl,
                "matchesBaseUrl": url.absoluteString.hasPrefix(self.baseUrl),
                "matchesGeneratedRedirectUri": matchesGeneratedRedirectCallback,
                "internalHandleUrl": internalHandleUrl,
                "embeddedMode": self.embeddedMode
            ]
        )

        if matchesGeneratedRedirectCallback,
           let parsedQueryItems,
           let failureDetails = self.oauthFailureDetails(from: parsedQueryItems) {
            logger.info("✅ [handleOpenUrl] Detected generated redirect URI OAuth error callback")
            self.reportOAuthFailure(
                error: failureDetails.error,
                flow: self.activeEmbeddedOAuthFlow == .login ? .login : self.activeEmbeddedOAuthFlow,
                errorCode: failureDetails.errorCode,
                errorDescription: failureDetails.errorDescription
            )

            if let webView = self.webview {
                let (newUrl, codeVerifier) = AuthorizeUrlGenerator().generate(remainCodeVerifier: true)
                CredentialManager.saveCodeVerifier(codeVerifier)
                webView.load(URLRequest(url: newUrl, cachePolicy: .reloadRevalidatingCacheData))
            }

            self.activeEmbeddedOAuthFlow = .login
            setAppLink(false)
            return true
        }
        
        if(!url.absoluteString.hasPrefix(self.baseUrl) && !internalHandleUrl && !matchesGeneratedRedirectCallback){
            logger.warning("⚠️ [handleOpenUrl] URL doesn't match baseUrl and internalHandleUrl is false, returning false")
            SentryHelper.logMessage(
                "App redirect URL rejected - doesn't match baseUrl",
                level: .warning,
                context: [
                    "app_redirect": [
                        "url": url.absoluteString,
                        "baseUrl": self.baseUrl,
                        "internalHandleUrl": internalHandleUrl,
                        "matchesGeneratedRedirectUri": matchesGeneratedRedirectCallback,
                        "scheme": url.scheme ?? "nil",
                        "host": url.host ?? "nil"
                    ],
                    "error": [
                        "type": "redirect_url_mismatch"
                    ]
                ]
            )
            setAppLink(false)
            return false
        }
        
        if url.path.contains("/postlogin/verify") {
            logger.info("✅ [handleOpenUrl] Detected /postlogin/verify URL, processing verification")
            SentryHelper.addBreadcrumb(
                "Processing /postlogin/verify URL",
                category: "app_redirect",
                level: .info,
                data: [
                    "url": url.absoluteString,
                    "hasToken": url.query?.contains("token") ?? false
                ]
            )
            var verificationUrl = url
            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var queryItems = urlComponents.queryItems ?? []
                
                let redirectUri = generateRedirectUri()
                if !queryItems.contains(where: { $0.name == "redirect_uri" }) {
                    queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectUri))
                }
                
                if let codeVerifier = CredentialManager.getCodeVerifier() {
                     if !queryItems.contains(where: { $0.name == "code_verifier_pkce" }) {
                        queryItems.append(URLQueryItem(name: "code_verifier_pkce", value: codeVerifier))
                        logger.info("Added code_verifier_pkce to verification URL")
                    }
                } else {
                    logger.warning("No code verifier found for verification URL - this may cause verification to fail")
                }
                
                urlComponents.queryItems = queryItems
                if let updatedUrl = urlComponents.url {
                    verificationUrl = updatedUrl
                }
            }
            
            let completion: FronteggAuth.CompletionHandler
            if let existingCompletion = self.loginCompletion {
                completion = existingCompletion
            } else {
                completion = { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let user):
                        self.logger.info("✅ Email verification completed successfully. User logged in: \(user.email)")
                        // Login is complete, no need to do anything else
                    case .failure(let error):
                        self.logger.error("❌ Email verification failed: \(error.localizedDescription)")
                    }
                }
            }
            
            let oauthCallback = createOauthCallbackHandler(
                completion,
                allowLastCodeVerifierFallback: true,
                pendingOAuthState: pendingOAuthState(from: verificationUrl),
                flow: .verification
            )
            
            var callbackReceived = false
            var sessionRef: ASWebAuthenticationSession? = nil
            
            let wrappedCallback: (URL?, Error?) -> Void = { [weak self] callbackUrl, error in
                guard let self = self else { return }
                callbackReceived = true
                
                // Cancel the session immediately to prevent showing localhost
                if let session = sessionRef {
                    session.cancel()
                    sessionRef = nil
                }
                
                if let url = callbackUrl, let host = url.host, (host.contains("localhost") || host.contains("127.0.0.1")) {
                    self.logger.warning("⚠️ Detected localhost redirect in verification callback, retrying social login immediately")
                    // Retry immediately without delay
                    if let urlComponents = URLComponents(url: verificationUrl, resolvingAgainstBaseURL: false),
                       let queryItems = urlComponents.queryItems,
                       let type = queryItems.first(where: { $0.name == "type" })?.value {
                        self.handleSocialLogin(providerString: type, custom: false, action: .login) { result in
                            switch result {
                            case .success(let user):
                                completion(.success(user))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    } else {
                        completion(.failure(FronteggError.authError(.unknown)))
                    }
                    return
                }
                
                
                oauthCallback(callbackUrl, error)
            }
            
            // Reduce timeout to 3 seconds to minimize localhost visibility
            // If verification takes longer, it likely redirected to localhost
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, !callbackReceived else { return }
                
                // Cancel the session to stop showing localhost
                if let session = sessionRef {
                    session.cancel()
                    sessionRef = nil
                }
                
                self.logger.info("🔄 Verification timeout - retrying social login to avoid localhost redirect")
                if let urlComponents = URLComponents(url: verificationUrl, resolvingAgainstBaseURL: false),
                   let queryItems = urlComponents.queryItems,
                   let type = queryItems.first(where: { $0.name == "type" })?.value {
                    self.handleSocialLogin(providerString: type, custom: false, action: .login) { result in
                        switch result {
                        case .success(let user):
                            self.logger.info("✅ Login completed successfully after verification timeout")
                            completion(.success(user))
                        case .failure(let error):
                            self.logger.error("❌ Login failed after verification timeout: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    }
                } else {
                    completion(.failure(FronteggError.authError(.unknown)))
                }
            }
            
            let window: UIWindow?
            if Thread.isMainThread {
                window = getRootVC(useAppRootVC)?.view.window
            } else {
                var mainWindow: UIWindow?
                DispatchQueue.main.sync {
                    mainWindow = getRootVC(useAppRootVC)?.view.window
                }
                window = mainWindow
            }
            
            if Thread.isMainThread {
                WebAuthenticator.shared.start(verificationUrl, ephemeralSession: false, window: window, completionHandler: wrappedCallback)
                sessionRef = WebAuthenticator.shared.session
            } else {
                DispatchQueue.main.async {
                    WebAuthenticator.shared.start(verificationUrl, ephemeralSession: false, window: window, completionHandler: wrappedCallback)
                    sessionRef = WebAuthenticator.shared.session
                }
            }
            return true
        }
        
        guard let rootVC = self.getRootVC(useAppRootVC) else {
            self.logger.error(FronteggError.authError(.couldNotFindRootViewController).localizedDescription)
            return false;
        }
        
        if let socialLoginUrl = handleSocialLoginCallback(url){
            self.activeEmbeddedOAuthFlow = .socialLogin
            if let webView = self.webview {
                let request = URLRequest(url: socialLoginUrl, cachePolicy: .reloadRevalidatingCacheData)
                webView.load(request)
                return true
            }else {
                self.pendingAppLink = socialLoginUrl
            }
        }else {
            self.activeEmbeddedOAuthFlow = .login
            self.pendingAppLink = url
        }
        setWebLoading(true)
        
        // Cancel any active ASWebAuthenticationSession before presenting EmbeddedLoginModal
        // This prevents the magic link deep link from opening Internal WebView on top of Custom Tab
        // which would break the session context
        if let activeSession = WebAuthenticator.shared.session {
            activeSession.cancel()
            WebAuthenticator.shared.session = nil
        }
        
        let loginModal = EmbeddedLoginModal(parentVC: rootVC)
        let hostingController = UIHostingController(rootView: loginModal)
        hostingController.modalPresentationStyle = .fullScreen
        
        let presented = rootVC.presentedViewController
        if presented is UIHostingController<EmbeddedLoginModal> {
            rootVC.presentedViewController?.dismiss(animated: false)
        }
        rootVC.present(hostingController, animated: false, completion: nil)
        
        return true
    }
    
    public func  switchTenant(tenantId:String,_ completion: FronteggAuth.CompletionHandler? = nil) {
        
        self.logger.info("Switching tenant to: \(tenantId)")
        if let currentUser = self.user {
            self.logger.info("Current tenant: \(currentUser.activeTenant.name) (ID: \(currentUser.activeTenant.id), tenantId: \(currentUser.activeTenant.tenantId))")
        }
        
        self.setIsLoading(true)
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                let config = try? PlistHelper.fronteggConfig()
                let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
                
                
                if enableSessionPerTenant {
                    self.credentialManager.saveLastActiveTenantId(tenantId)
                    self.logger.info("Saved new tenant ID (\(tenantId)) as last active tenant before switching")
                    
                    if let currentUser = self.user {
                        let currentTenantId = currentUser.activeTenant.id
                        if let currentRefreshToken = self.refreshToken,
                           let currentAccessToken = self.accessToken {
                            do {
                                try self.credentialManager.saveTokenForTenant(currentRefreshToken, tenantId: currentTenantId, tokenType: .refreshToken)
                                try self.credentialManager.saveTokenForTenant(currentAccessToken, tenantId: currentTenantId, tokenType: .accessToken)
                                self.logger.info("Saved tokens for tenant \(currentTenantId) before switching")
                            } catch {
                                self.logger.warning("Failed to save tokens for tenant \(currentTenantId): \(error)")
                            }
                        }
                    }
                    if let newRefreshToken = try? self.credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken),
                       let newAccessToken = try? self.credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .accessToken) {
                        // Load existing tokens for the new tenant
                        await MainActor.run {
                            self.setRefreshToken(newRefreshToken)
                            self.setAccessToken(newAccessToken)
                        }
                        self.logger.info("Loaded existing tokens for tenant \(tenantId) from local storage")
                        
                        do {
                            let data = try await self.api.refreshToken(
                                refreshToken: newRefreshToken,
                                tenantId: tenantId
                            )
                            await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                            
                            if let user = self.user {
                                self.logger.info("Tenant switch completed using existing tokens (no server-side API call). New active tenant: \(user.activeTenant.name) (ID: \(user.activeTenant.id))")
                                await MainActor.run {
                                    self.setIsLoading(false)
                                }
                    completion?(.success(user))
                                return
                            }
                        } catch {
                            self.logger.warning("Refresh with tenantId failed, trying standard OAuth refresh: \(error)")
                            do {
                                let data = try await self.api.refreshToken(
                                    refreshToken: newRefreshToken,
                                    tenantId: nil
                                )
                                await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                                
                                if let user = self.user {
                                    if user.activeTenant.id == tenantId {
                                        self.logger.info("Tenant switch completed using existing tokens (standard OAuth refresh). New active tenant: \(user.activeTenant.name) (ID: \(user.activeTenant.id))")
                                        await MainActor.run {
                                            self.setIsLoading(false)
                                        }
                                        completion?(.success(user))
                                        return
                } else {
                                        self.logger.warning("Standard OAuth refresh returned wrong tenant (\(user.activeTenant.id) instead of \(tenantId)), will use server-side API")
                                    }
                                }
                            } catch {
                                self.logger.warning("Both refresh methods failed for tenant \(tenantId), will create new tokens: \(error)")
                            }
                        }
                    } else {
                        self.logger.info("No existing tokens found for tenant \(tenantId) in local storage")
                    }
                    self.logger.info("No existing tokens found for tenant \(tenantId), creating new tokens via server-side API")
                }
                
                guard let currentAccessToken = self.accessToken else {
                    self.logger.error("No access token available for tenant switch")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    return
                }
                
                self.logger.info("Calling server-side API to switch tenant to: \(tenantId) (access token length: \(currentAccessToken.count))")
                
                do {
                    try await self.api.switchTenant(tenantId: tenantId, accessToken: currentAccessToken)
                    self.logger.info("Successfully switched tenant via API to: \(tenantId)")
                } catch {
                    self.logger.error("Failed to switch tenant via API: \(error)")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    return
                }
                
                guard let refreshToken = self.refreshToken else {
                    self.logger.error("No refresh token available for tenant switch")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    return
                }
                
                self.logger.info("Using refresh token for tenant switch (token length: \(refreshToken.count))")
                
                // Refresh tokens to get updated user data with new tenant
                do {
                    self.logger.info("Refreshing token after tenant switch to: \(tenantId)")
                    var data: AuthResponse
                    
                    if enableSessionPerTenant {
                        // After a server-side tenant switch, we MUST use standard OAuth refresh first
                        // to get a new refresh token that's valid for the new tenant.
                        // The old refresh token is still associated with the old tenant, so
                        // tenant-specific refresh will fail until we get new tokens.
                        self.logger.info("Using standard OAuth refresh after server-side tenant switch to get new tokens for tenant: \(tenantId)")
                        data = try await self.api.refreshToken(
                            refreshToken: refreshToken,
                            tenantId: nil
                        )
                        self.logger.info("Standard OAuth refresh successful after tenant switch. New tokens will be saved with tenant ID: \(tenantId)")
                    } else {
                        data = try await self.api.refreshToken(
                            refreshToken: refreshToken,
                            tenantId: nil
                        )
                    }
                    
                    self.logger.info("Token refresh successful, updating credentials")
                    await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                    if let user = self.user {
                        let newTenantId = user.activeTenant.id
                        if newTenantId != tenantId {
                            self.logger.warning("Tenant switch returned different tenant ID (\(newTenantId)) than expected (\(tenantId)). Updating stored tenant ID.")
                            self.credentialManager.saveLastActiveTenantId(newTenantId)
                        }
                        self.logger.info("Tenant switch completed. New active tenant: \(user.activeTenant.name) (ID: \(newTenantId), tenantId: \(user.activeTenant.tenantId))")
                        
                        if newTenantId != tenantId && user.activeTenant.tenantId != tenantId {
                            self.logger.warning("Tenant switch may have failed - expected \(tenantId) but got \(newTenantId)")
                        }
                        
                        await MainActor.run {
                            self.setIsLoading(false)
                        }
                        completion?(.success(user))
                    } else {
                        self.logger.error("User is nil after tenant switch and refresh")
                        await MainActor.run {
                            self.setIsLoading(false)
                        }
                        completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    }
                } catch {
                    self.logger.error("Failed to refresh token after tenant switch: \(error)")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                }
                
            }
        }
    }
    
    public func loginWithPasskeys (_ _completion: FronteggAuth.CompletionHandler? = nil){
        
        if #available(iOS 15.0, *) {
            Task {
                let completion = handleMfaRequired(_completion)
                await PasskeysAuthenticator.shared.loginWithPasskeys(completion)
            }
        } else {
            // Fallback on earlier versions
        }
    }
    public func registerPasskeys(_ completion: FronteggAuth.ConditionCompletionHandler? = nil) {
        
        if #available(iOS 15.0, *) {
            PasskeysAuthenticator.shared.startWebAuthn(completion)
        } else {
            // Fallback on earlier versions
        }
    }
    
    
    public func handleSocialLoginCallback(_ url: URL) -> URL? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        // 1) Host must match Frontegg base URL host
        guard let allowedHost = URL(string: FronteggAuth.shared.baseUrl)?.host else {
            return nil
        }
        
        guard comps.host == allowedHost else {
            return nil
        }
        
        // 2) Path: /oauth/account/redirect/ios/{bundleId}/{provider}
        let prefix = "/oauth/account/redirect/ios/"
        let path = comps.path
        guard path.hasPrefix(prefix) || path.hasPrefix("/ios/oauth/callback") else {
            return nil
        }
        
        let bundleId = FronteggApp.shared.bundleIdentifier
        guard !bundleId.isEmpty else {
            return nil
        }
        
        // Helpers
        let items = comps.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if q("error") != nil || q("error_description") != nil {
            return nil
        }
        
        // Extract supported params
        var queryParams: [String: String] = [:]
        
        if let code = q("code"), !code.isEmpty {
            queryParams["code"] = code
        }
        
        if let idToken = q("id_token"), !idToken.isEmpty {
            queryParams["id_token"] = idToken
        }
        
        let redirectUri = SocialLoginUrlGenerator.shared.defaultRedirectUri()
        queryParams["redirectUri"] = redirectUri.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        
        // Process state
        if let state = q("state"), !state.isEmpty {
            if let data = state.data(using: .utf8),
               var dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                dict.removeValue(forKey: "platform")
                dict.removeValue(forKey: "bundleId")
                if let newData = try? JSONSerialization.data(withJSONObject: dict, options: []),
                   let newState = String(data: newData, encoding: .utf8) {
                    queryParams["state"] = newState.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
                }
            } else {
                // fallback if state is not valid JSON
                queryParams["state"] = state
            }
        }
        
        if let s = WebAuthenticator.shared.session {
            s.cancel()
        }
        
        // Build query string safely
        var compsOut = URLComponents()
        compsOut.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        let finalUrl = URL(string: "\(FronteggAuth.shared.baseUrl)/oauth/account/social/success?\(compsOut.query ?? "")")
        
        return finalUrl
    }
    
    
    
    /// Authorizes the session using a refresh token (and optional device token cookie).
    /// The refresh token must come from identity-server APIs, e.g. sign-up:
    /// `POST /frontegg/identity/resources/users/v1/signUp`.
    public func requestAuthorizeAsync(refreshToken: String, deviceTokenCookie: String? = nil) async throws -> User {
        FronteggAuth.shared.setIsLoading(true)
        
        self.logger.info("Requesting authorize with refresh and device tokens")
        
        do {
            let authResponse = try await self.api.authroizeWithTokens(refreshToken: refreshToken, deviceTokenCookie: deviceTokenCookie)
            await FronteggAuth.shared.setCredentials(accessToken: authResponse.access_token, refreshToken: authResponse.refresh_token)
            
            if let user = self.user {
                return user
            }
            
            throw FronteggError.authError(.failedToAuthenticate)
        } catch {
            self.logger.error("Authorization request failed: \(error.localizedDescription)")
            FronteggAuth.shared.setIsLoading(false)
            throw error
        }
    }
    
    /// Callback-based variant of `requestAuthorizeAsync`. Use with tokens from identity-server APIs
    /// (e.g. `POST /frontegg/identity/resources/users/v1/signUp`).
    public func requestAuthorize(refreshToken: String, deviceTokenCookie: String? = nil, _ completion: @escaping FronteggAuth.CompletionHandler) {
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let user = try await self.requestAuthorizeAsync(refreshToken: refreshToken, deviceTokenCookie: deviceTokenCookie)
                    await MainActor.run {
                        completion(.success(user)) // Assuming success is represented by empty parentheses
                    }
                } catch let error as FronteggError {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                } catch {
                    self.logger.error("Failed to authenticate: \(error.localizedDescription)")
                    await MainActor.run {
                        completion(.failure(.authError(.failedToAuthenticate)))
                    }
                }
            }
        }
    }
    
    /// Checks if the user has been stepped up (re-authenticated with stronger authentication).
    ///
    /// - Parameter maxAge: Optional parameter to specify the maximum age of the authentication.
    /// - Returns: `true` if the user has been stepped up, otherwise `false`.
    public func isSteppedUp(maxAge: TimeInterval? = nil) -> Bool {
        return self.stepUpAuthenticator.isSteppedUp(maxAge: maxAge)
    }
    
    /// Initiates a step-up authentication process.
    ///
    /// This function triggers a step-up authentication process, which requires the user to re-authenticate with stronger authentication mechanisms.
    ///
    /// - Parameters:
    ///   - maxAge: Optional parameter to specify the maximum age of the authentication.
    ///   - _completion: Optional completion handler that is executed once the step-up process is complete.
    public func stepUp(
        maxAge: TimeInterval? = nil,
        _ _completion: FronteggAuth.CompletionHandler? = nil
    ) async {
        return self.stepUpAuthenticator.stepUp(maxAge: maxAge, completion: _completion)
    }
    
    internal func handleMfaRequired(_ _completion: FronteggAuth.CompletionHandler? = nil) -> FronteggAuth.CompletionHandler {
        let completion: FronteggAuth.CompletionHandler =  { (result) in
            
            switch (result) {
            case .success(_):
                DispatchQueue.main.async {
                    FronteggAuth.shared.setIsLoading(false)
                    _completion?(result)
                }
                
            case .failure(let fronteggError):
                
                switch fronteggError {
                case .authError(let authError):
                    if case let .mfaRequired(jsonResponse, refreshToken) = authError {
                        // Handle the MFA-required logic here with the jsonResponse
                        self.logger.info("MFA required with JSON response: \(jsonResponse)")
                        self.startMultiFactorAuthenticator(
                            mfaRequestData: jsonResponse,
                            refreshToken:refreshToken,
                            completion: _completion
                        )
                        
                        return
                    } else {
                        self.logger.info("authentication error: \(authError.localizedDescription)")
                    }
                case .configError(let configError):
                    self.logger.info("config error: \(configError.localizedDescription)")
                case .networkError(let error):
                    self.logger.info("network error: \(error.localizedDescription)")
                }
                
                DispatchQueue.main.async {
                    FronteggAuth.shared.setIsLoading(false)
                    _completion?(result)
                }
            }
        }
        return completion
    }
    
    
    internal func startMultiFactorAuthenticator(
        mfaRequestData: [String: Any]? = nil,
        mfaRequestJson: String? = nil,
        refreshToken: String? = nil,
        completion: FronteggAuth.CompletionHandler? = nil
    ) {
        Task {
            do {
                let (authorizeUrl, codeVerifier): (URL, String)
                
                if let requestData = mfaRequestData {
                    (authorizeUrl, codeVerifier) = try await multiFactorAuthenticator.start(mfaRequestData: requestData, refreshToken: refreshToken)
                } else if let requestJson = mfaRequestJson {
                    (authorizeUrl, codeVerifier) = try multiFactorAuthenticator.start(mfaRequestJson: requestJson)
                } else {
                    return
                }
                
                CredentialManager.saveCodeVerifier(codeVerifier)
                
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.setIsLoading(false)
                    
                    if self.embeddedMode {
                        self.activeEmbeddedOAuthFlow = .mfa
                        self.pendingAppLink = authorizeUrl
                        self.setWebLoading(true)
                        self.embeddedLogin(completion, loginHint: nil)
                        return
                    }
                    
                    let oauthCallback = self.createOauthCallbackHandler(
                        completion ?? { _ in },
                        pendingOAuthState: self.pendingOAuthState(from: authorizeUrl),
                        flow: .mfa
                    )
                    WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
                }
            } catch let error as FronteggError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.setIsLoading(false)
                }
                completion?(.failure(error))
            }
        }
    }
    
}
