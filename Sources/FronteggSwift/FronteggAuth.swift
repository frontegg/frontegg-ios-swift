//
//  FronteggAuth.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import WebKit
import Combine
import AuthenticationServices
import UIKit
import SwiftUI


extension UIWindow {
    static var key: UIWindow? {
        return UIApplication.shared.windows.filter {$0.isKeyWindow}.first
    }
}

public enum AttemptReasonType {
    case unknown
    case noNetwork
}


public class FronteggAuth: FronteggState {
    
    
    public var embeddedMode: Bool
    public var isRegional: Bool
    public var regionData: [RegionConfig]
    public var baseUrl: String
    public var clientId: String
    public var applicationId: String? = nil
    public var pendingAppLink: URL? = nil
    public var loginHint: String? = nil
    public var lastAttemptReason: AttemptReasonType? = nil
    
    
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
    private var subscribers = Set<AnyCancellable>()
    private var refreshTokenDispatch: DispatchWorkItem?
    private var offlineDebounceWork: DispatchWorkItem?
    private let offlineDebounceDelay: TimeInterval = 0.6
    var loginCompletion: CompletionHandler? = nil
    
    init (
        baseUrl:String,
        clientId: String,
        applicationId: String?,
        credentialManager: CredentialManager,
        isRegional: Bool,
        regionData: [RegionConfig],
        embeddedMode: Bool,
        isLateInit: Bool? = false
    ) {
        self.isRegional = isRegional
        self.regionData = regionData
        self.credentialManager = credentialManager
        
        self.embeddedMode = embeddedMode
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.featureFlags = FeatureFlags(.init(clientId:self.clientId, api:self.api))
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
    
    
    public func manualInit(baseUrl:String, clientId:String, applicationId: String?) {
        setLateInit(false)
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.isRegional = false
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
        self.initializeSubscriptions()
    }
    
    public func manualInitRegions(regions:[RegionConfig]) {
        
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
            self.initializeSubscriptions()
        }
    }
    
    
    @objc private func applicationDidBecomeActive() {
        logger.info("application become active")
        
        if(initializing){
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
        
        let (url, _) = AuthorizeUrlGenerator().generate(remainCodeVerifier:true)
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
        
        if(self.isOfflineMode == false){
            return;
        }
        self.logger.info("Connected to the internet")
        // Cancel any pending offline transition
        offlineDebounceWork?.cancel()
        offlineDebounceWork = nil
        self.setIsOfflineMode(false)
        
        DispatchQueue.global(qos: .background).async {
            Task {
                await self.featureFlags.start();
                await SocialLoginUrlGenerator.shared.reloadConfigs()
            }
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
    
    public func initializeSubscriptions() {
        let config = try? PlistHelper.fronteggConfig()
        let enableOfflineMode = config?.enableOfflineMode ?? false

        if enableOfflineMode {
            NetworkStatusMonitor.configure(baseURLString: "\(self.baseUrl)/test")
            
            NetworkStatusMonitor.startBackgroundMonitoring(interval: 10) { reachable in
                if reachable {
                    self.reconnectedToInternet()
                } else {
                    self.disconnectedFromInternet()
                }
            }
        }
        
        self.$initializing.combineLatest(self.$isAuthenticated, self.$isLoading).sink(){ (initializingValue, isAuthenticatedValue, isLoadingValue) in
            self.setShowLoader(initializingValue || (!isAuthenticatedValue && isLoadingValue))
        }.store(in: &subscribers)
        
        let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
        
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
            } else {
                logger.info("Using LOCAL tenant ID from storage: \(tenantId!)")
            }
            
            if let tenantId = tenantId {
                refreshToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken)
                accessToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .accessToken)
            }
        } else {
            // Legacy behavior: load global tokens
            refreshToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue)
            accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue)
        }
        
        if let refreshToken = refreshToken, let accessToken = accessToken {
            setRefreshToken(refreshToken)
            setAccessToken(accessToken)
            setIsLoading(true)
            
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    if await NetworkStatusMonitor.isActive {
                        await self.featureFlags.start();
                        await SocialLoginUrlGenerator.shared.reloadConfigs()
                        self.warmingWebViewAsync()
                    }
                    await self.refreshTokenIfNeeded()
                }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    if await NetworkStatusMonitor.isActive {
                        self.setIsOfflineMode(false)
                        await self.featureFlags.start();
                        await SocialLoginUrlGenerator.shared.reloadConfigs()
                    }else {
                        self.setIsOfflineMode(true)
                    }
                    
                    await MainActor.run { [weak self] in
                        self?.setIsLoading(false)
                        self?.setInitializing(false)
                    }
                }
            }
        }
    }
    
    
    public func setCredentials(accessToken: String, refreshToken: String) async {
        self.logger.info("Setting credentials (refresh token length: \(refreshToken.count))")
        
        do {
            let config = try? PlistHelper.fronteggConfig()
            let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
            
            // Decode token to get tenantId
            let decode = try JWTHelper.decode(jwtToken: accessToken)
            guard let user = try await self.api.me(accessToken: accessToken) else {
                throw FronteggError.authError(.failedToLoadUserData("User data is nil"))
            }
            
            var tenantIdToUse: String? = nil
            
            // Store tokens per tenant if enableSessionPerTenant is enabled
            if enableSessionPerTenant {
                if let localTenantId = credentialManager.getLastActiveTenantId() {
                    tenantIdToUse = localTenantId
                    logger.info("Using LOCAL tenant ID: \(tenantIdToUse!) (ignoring server's active tenant: \(user.activeTenant.id))")
                    
                    if !user.tenants.contains(where: { $0.id == localTenantId }) {
                        logger.error("CRITICAL: Local tenant ID (\(localTenantId)) not found in user's tenants list! Available: \(user.tenants.map { $0.id }). This should not happen.")
                    }
                } else {
                    tenantIdToUse = user.activeTenant.id
                    self.credentialManager.saveLastActiveTenantId(tenantIdToUse!)
                    logger.info("No local tenant stored, using server's active tenant: \(tenantIdToUse!) (saved as local tenant)")
                }
                
                try self.credentialManager.saveTokenForTenant(refreshToken, tenantId: tenantIdToUse!, tokenType: .refreshToken)
                try self.credentialManager.saveTokenForTenant(accessToken, tenantId: tenantIdToUse!, tokenType: .accessToken)
                logger.info("Saved tokens for tenant: \(tenantIdToUse!)")
            } else {
                // Store tokens globally (legacy behavior)
            try self.credentialManager.save(key: KeychainKeys.refreshToken.rawValue, value: refreshToken)
            try self.credentialManager.save(key: KeychainKeys.accessToken.rawValue, value: accessToken)
            }
            
            var userToUse = user
            if enableSessionPerTenant, let localTenantId = tenantIdToUse {
                if let matchingTenant = user.tenants.first(where: { $0.id == localTenantId }) {
                    do {
                        var userDict = try JSONEncoder().encode(user)
                        var userJson = try JSONSerialization.jsonObject(with: userDict) as! [String: Any]
                        
                        if let matchingTenantData = try? JSONEncoder().encode(matchingTenant),
                           let matchingTenantDict = try? JSONSerialization.jsonObject(with: matchingTenantData) as? [String: Any] {
                            userJson["activeTenant"] = matchingTenantDict
                            userJson["tenantId"] = matchingTenant.tenantId
                            
                            let modifiedUserData = try JSONSerialization.data(withJSONObject: userJson)
                            userToUse = try JSONDecoder().decode(User.self, from: modifiedUserData)
                            
                            if localTenantId != user.activeTenant.id {
                                logger.info("Modified user to use local tenant (\(localTenantId)) instead of server's active tenant (\(user.activeTenant.id))")
                            } else {
                                logger.info("User already matches local tenant (\(localTenantId))")
                            }
                        }
                    } catch {
                        logger.warning("Failed to modify user for local tenant: \(error). Using server's active tenant.")
                    }
                } else {
                    logger.error("Local tenant ID (\(localTenantId)) not found in user's tenants list. This should not happen. Available tenants: \(user.tenants.map { $0.id })")
                }
            }
            
            if let config = config, config.enableOfflineMode {
                self.credentialManager.saveOfflineUser(user: userToUse)
            }
            
            await MainActor.run {
                setRefreshToken(refreshToken)
                setAccessToken(accessToken)
                setUser(userToUse)
                setIsAuthenticated(true)
                setIsOfflineMode(false)
                setAppLink(false)
                setInitializing(false)
                setAppLink(false)
                setIsStepUpAuthorization(false)
                
                // isLoading must be at the bottom
                setIsLoading(false)
                
                let offset = calculateOffset(expirationTime: decode["exp"] as! Int)
                scheduleTokenRefresh(offset: offset)
            }
            
        } catch {
            await MainActor.run {
                logger.error("Failed to load user data: \(error)")
                setRefreshToken(nil)
                setAccessToken(nil)
                setUser(nil)
                setIsAuthenticated(false)
                setInitializing(false)
                setAppLink(false)
                
                // isLoading must be at the last bottom
                setIsLoading(false)
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
            let expirationTime = decode["exp"] as! Int
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
    
    
    
    func scheduleTokenRefresh(offset: TimeInterval, attempts: Int = 0) {
        cancelScheduledTokenRefresh()
        logger.info("Schedule token refresh after, (\(offset) s) (attempt: \(attempts))")
        
        var workItem: DispatchWorkItem? = nil
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !(workItem!.isCancelled) else { return }
            Task {
                await self.refreshTokenIfNeeded(attempts: attempts)
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
    
    public func logout(clearCookie: Bool = true, _ completion: FronteggAuth.LogoutHandler? = nil) {
        Task { @MainActor in
            
            setIsLoading(true)
            defer { setIsLoading(false) }
            
            // Try to reload from keychain if in-memory token is nil
            // This ensures we can invalidate the session on the server even if the token
            // was not loaded into memory (e.g., after app restart)
            var refreshToken = self.refreshToken
            if refreshToken == nil {
                if let keychainToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                    self.logger.info("Reloaded refresh token from keychain for logout")
                    refreshToken = keychainToken
                } else {
                    self.logger.warning("No refresh token found in memory or keychain. Server session may remain active.")
                }
            }
            
            await self.api.logout(accessToken: self.accessToken, refreshToken: refreshToken)
            
            self.credentialManager.deleteLastActiveTenantId()
            self.credentialManager.clear()
            if clearCookie {
                await self.clearCookie()
            }
            
            setIsAuthenticated(false)
            setUser(nil)
            setAccessToken(nil)
            setRefreshToken(nil)
            setInitializing(false)
            setAppLink(false)
            
            completion?(.success(true))
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
            print("logged out")
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
    
    
    
    // MARK: - Offline-like handler
    
    /// Centralized handler for errors that *behave like* no connectivity.
    /// Decides the backoff offset, updates state (including offline user), and reschedules.
    private func handleOfflineLikeFailure(
        error: Error?,
        enableOfflineMode: Bool,
        attempts: Int,
        preferredOffset: TimeInterval? = nil
    ) {
        // Classify + choose offset once
        let isConn = error.map { isConnectivityError($0) } ?? true // treat nil as connectivity (e.g., no active internet path)
        let offset = preferredOffset ?? (isConn ? 2 : 1)
        
        if isConn {
            self.logger.info("Refresh rescheduled due to network error \(error?.localizedDescription ?? "(no error)")")
        } else {
            self.logger.info("Refresh rescheduled due to unknown error \(error?.localizedDescription ?? "(no error)")")
        }
        
        self.lastAttemptReason = .noNetwork
        
        if enableOfflineMode {
            let offlineUserData = self.credentialManager.getOfflineUser()
            DispatchQueue.main.async {
                self.setUser(self.user ?? offlineUserData)
                self.setInitializing(false)
                self.setIsAuthenticated(false)
                self.setIsOfflineMode(true)
                self.setIsLoading(false)
            }
        }
        
        scheduleTokenRefresh(offset: offset, attempts: attempts + 1)
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
    public func refreshTokenIfNeeded(attempts: Int = 0) async -> Bool {
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
                }
            }
        }
        
        guard let refreshToken = refreshToken else {
            self.logger.info("No refresh token found in memory or keychain")
            return false
        }
        
        // Hard no-network (quick exit path) → route through the central handler
        guard await NetworkStatusMonitor.isActive else {
            self.logger.info("Refresh rescheduled due to inactive internet")
            handleOfflineLikeFailure(
                error: nil,                      // nil → treat as connectivity
                enableOfflineMode: enableOfflineMode,
                attempts: attempts,
                preferredOffset: 2               // keep your existing offset
            )
            return false
        }
        
        if enableOfflineMode && self.lastAttemptReason == .noNetwork {
            self.logger.info("Refreshing after network reconnect, offline mode enabled")
        } else if attempts > 10 {
            self.logger.info("Refresh token attempts exceeded, logging out")
            self.credentialManager.clear()
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
        
        if self.refreshingToken {
            self.logger.info("Skip refreshing token - already in progress")
            return false
        }
        
        self.logger.info("Refreshing token")
        setRefreshingToken(true)
        defer { setRefreshingToken(false) }
        
        let preservedTenantId = enableSessionPerTenant ? credentialManager.getLastActiveTenantId() : nil
        
        do {
            if enableSessionPerTenant {
                if let preserved = preservedTenantId {
                    self.logger.info("Refreshing token with preserved tenant ID: \(preserved)")
                } else {
                    self.logger.warning("WARNING: No tenant ID stored before token refresh! This should not happen.")
                }
            }
            
            var data: AuthResponse
            
            if enableSessionPerTenant, let tenantId = currentTenantId {
                // Try tenant-specific refresh first
                // Include access token if available - it may be needed for tenant-specific refresh
                let currentAccessToken = self.accessToken
                do {
                    self.logger.info("Attempting tenant-specific refresh with tenantId: \(tenantId)")
                    data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: tenantId, accessToken: currentAccessToken)
                    self.logger.info("Tenant-specific refresh successful")
                } catch {
                    // If tenant-specific refresh fails, fall back to standard OAuth refresh
                    // This can happen if the refresh token isn't valid for the tenant-specific endpoint
                    // (e.g., after a server-side tenant switch)
                    self.logger.warning("Tenant-specific refresh failed: \(error). Falling back to standard OAuth refresh.")
                    data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
                    self.logger.info("Standard OAuth refresh successful (fallback)")
                }
            } else {
                // Standard OAuth refresh for non-per-tenant sessions
                data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
            }
            
            if enableSessionPerTenant, let preserved = preservedTenantId {
                if credentialManager.getLastActiveTenantId() != preserved {
                    self.logger.warning("CRITICAL: Tenant ID was lost during refresh! Restoring: \(preserved)")
                    credentialManager.saveLastActiveTenantId(preserved)
                }
            }
            
            await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
            self.logger.info("Token refreshed successfully")
            return true
            
        } catch let error as FronteggError {
            // Auth failure → logout (unchanged)
            if case .authError(FronteggError.Authentication.failedToRefreshToken) = error {
                // Before clearing, preserve the tenant ID if we have one
                if enableSessionPerTenant, let preserved = preservedTenantId {
                    self.logger.warning("Token refresh failed, but preserving tenant ID: \(preserved)")
                }
                self.credentialManager.clear()
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
                attempts: attempts
            )
            return false
            
        } catch {
            handleOfflineLikeFailure(
                error: error,
                enableOfflineMode: enableOfflineMode,
                attempts: attempts
            )
            return false
        }
    }
    
    
    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String, _ completion: @escaping FronteggAuth.CompletionHandler) {
        handleHostedLoginCallback(code, codeVerifier, redirectUri: nil, completion)
    }
    
    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String?, _ completion: @escaping FronteggAuth.CompletionHandler) {
        handleHostedLoginCallback(code, codeVerifier, redirectUri: nil, completion)
    }
    
    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String?, redirectUri: String?, _ completion: @escaping FronteggAuth.CompletionHandler) {
        
        // Use provided redirectUri or generate default one
        // For magic link flow, we should use the redirectUri from the callback URL
        let redirectUri = redirectUri ?? generateRedirectUri()
        setIsLoading(true)
        
        Task {
            
            logger.info("Going to exchange token with redirectUri: \(redirectUri), codeVerifier: \(codeVerifier != nil ? "provided" : "nil")")
            let (responseData, error) = await api.exchangeToken(
                code: code,
                redirectUrl: redirectUri,
                codeVerifier: codeVerifier
            )
            
            guard error == nil else {
                DispatchQueue.main.async {
                    completion(.failure(error!))
                    self.setIsLoading(false)
                }
                return
            }
            
            guard let data = responseData else {
                DispatchQueue.main.async {
                    completion(.failure(FronteggError.authError(.failedToAuthenticate)))
                    self.setIsLoading(false)
                }
                return
            }
            
            do {
                logger.info("Going to load user data")
                let user = try await self.api.me(accessToken: data.access_token)
                
                guard let user = user else {
                    DispatchQueue.main.async {
                        completion(.failure(FronteggError.authError(.failedToLoadUserData("User data is nil"))))
                        self.setIsLoading(false)
                    }
                    return
                }
                
                await setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                
                // Call completion on main thread to avoid race conditions
                // This ensures the completion handler always runs on the main thread
                DispatchQueue.main.async {
                    completion(.success(user))
                }
            } catch {
                logger.error("Failed to load user data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(FronteggError.authError(.failedToLoadUserData(error.localizedDescription))))
                    self.setIsLoading(false)
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
        
        // Try to reload from keychain if in-memory token is nil
        var refreshToken = self.refreshToken
        if refreshToken == nil {
            if enableSessionPerTenant {
                if let user = self.user {
                    let tenantId = user.activeTenant.id
                    if let tenantToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken) {
                        self.logger.info("Reloaded refresh token for tenant \(tenantId) from keychain in getOrRefreshAccessTokenAsync")
                        await MainActor.run {
                            setRefreshToken(tenantToken)
                        }
                        refreshToken = tenantToken
                    }
                } else if let offlineUser = credentialManager.getOfflineUser() {
                    let tenantId = offlineUser.activeTenant.id
                    if let tenantToken = try? credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken) {
                        self.logger.info("Reloaded refresh token for tenant \(tenantId) from keychain in getOrRefreshAccessTokenAsync")
                        await MainActor.run {
                            setRefreshToken(tenantToken)
                        }
                        refreshToken = tenantToken
                    }
                }
            } else {
                // Legacy behavior: load global token
            if let keychainToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                self.logger.info("Reloaded refresh token from keychain in getOrRefreshAccessTokenAsync")
                await MainActor.run {
                    setRefreshToken(keychainToken)
                }
                refreshToken = keychainToken
                }
            }
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
                    self.logger.warning("Access token offset: \(offset)")
                    if offset > 15 { // Ensure token has more than 15 seconds validity
                        return accessToken
                    }
                }
            } catch {
                self.logger.error("Failed to decode JWT: \(error.localizedDescription)")
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
                        // If tenant-specific refresh fails, fall back to standard OAuth refresh
                        self.logger.warning("Tenant-specific refresh failed in getOrRefreshAccessTokenAsync: \(error). Falling back to standard OAuth refresh.")
                        data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
                        self.logger.info("Standard OAuth refresh successful (fallback) in getOrRefreshAccessTokenAsync")
                    }
                } else {
                    // Standard OAuth refresh for non-per-tenant sessions
                    data = try await self.api.refreshToken(refreshToken: refreshToken, tenantId: nil)
                }
                
                await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                self.logger.info("Token refreshed successfully")
                return self.accessToken
            } catch let error as FronteggError {
                if case .authError(FronteggError.Authentication.failedToRefreshToken) = error {
                    return nil
                }
                self.logger.error("Failed to refresh token: \(error.localizedDescription), retrying... (\(attempts + 1) attempts)")
                attempts += 1
                try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep for 1 second before retrying
            } catch {
                self.logger.error("Unknown error while refreshing token: \(error.localizedDescription), retrying... (\(attempts + 1) attempts)")
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
    
    
    //   internal func setIsLoading(_ isLoading: Bool){
    //       DispatchQueue.main.async {
    //           self.isLoading = isLoading
    //       }
    //   }
    
    internal func createOauthCallbackHandler(_ completion: @escaping FronteggAuth.CompletionHandler) -> ((URL?, Error?) -> Void) {
        
        return { callbackUrl, error in
            if let error {
                completion(.failure(FronteggError.authError(.other(error))))
                return
            }
            
            guard let url = callbackUrl else {
                completion(.failure(FronteggError.authError(.unknown)))
                return
            }
            
            let parsedQueryItems = getQueryItems(url.absoluteString)
            guard let queryItems = parsedQueryItems, let code = queryItems["code"] else {
                let error = FronteggError.authError(.failedToExtractCode)
                completion(.failure(error))
                return
            }
            
            guard let codeVerifier = CredentialManager.getCodeVerifier() else {
                let error = FronteggError.authError(.codeVerifierNotFound)
                completion(.failure(error))
                return
            }
            
            if let errorMessage = queryItems["error"] {
                let error = FronteggError.authError(.oauthError(errorMessage))
                completion(.failure(error))
                return
            }
            
            self.handleHostedLoginCallback(code, codeVerifier, completion)
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
        
        let oauthCallback = createOauthCallbackHandler(completion)
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: loginHint)
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        
        WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
    }
    
    
    func saveWebCredentials(domain: String, email: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        let domainString = domain
        let account = email
        
        SecAddSharedWebCredential(domainString as CFString, account as CFString, password as CFString) { error in
            if let error = error {
                print("❌ Failed to save shared web credentials: \(error.localizedDescription)")
                completion(false, error)
            } else {
                print("✅ Shared web credentials saved successfully!")
                completion(true, nil)
            }
        }
    }
    
    
    
    public func loginWithPopup(window: UIWindow?, ephemeralSession: Bool? = true, loginHint: String? = nil, loginAction: String? = nil, _completion: FronteggAuth.CompletionHandler? = nil) {
        
        let completion = _completion ?? { res in
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: loginHint, loginAction: loginAction)
        CredentialManager.saveCodeVerifier(codeVerifier)
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
                return
            }
            
            guard let callbackURL else {
                self.logger.info("OAuth callback invoked with nil URL and no error")
                return
            }
            
            self.logger.debug("OAuth callback URL: \(callbackURL.absoluteString)")
            
            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    let finalURL = self.handleSocialLoginCallback(callbackURL)
                else { return }
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
            
            await WebAuthenticator.shared.start(
                authURL,
                ephemeralSession: false,
                completionHandler: oauthCallback
            )
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
            generatedUrl = AuthorizeUrlGenerator.shared.generate()
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        let (authorizeUrl, codeVerifier) = generatedUrl
        CredentialManager.saveCodeVerifier(codeVerifier)
        
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
                            let oauthCallback = self.createOauthCallbackHandler(completion)
                            let url = try await self.generateAppleAuthorizeUrl(config: appleConfig)
                            await WebAuthenticator.shared.start(url, ephemeralSession: true, completionHandler: oauthCallback)
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
    
    
    func createOauth2SessionState() async throws -> Data {
        let (url, codeVerifier)  = AuthorizeUrlGenerator.shared.generate()
        
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
        
        return oauthStateJson
    }
    func generateAppleAuthorizeUrl(config: SocialLoginOption) async throws -> URL {
        let sessionState = try await createOauth2SessionState()
        
        let scope = ["openid", "name", "email"] + config.additionalScopes
        let appId = FronteggAuth.shared.applicationId ?? ""
        
        let stateDict = [
            "oauthState": sessionState.base64EncodedString(),
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
        
        return finalUrl
    }
    
    func loginWithSocialLogin(socialLoginUrl: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in
            
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        
        
        let directLogin: [String: Any] = [
            "type": "direct",
            "data": socialLoginUrl,
        ]
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: true)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate()
        }
        
        let (authorizeUrl, codeVerifier) = generatedUrl
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
    }
    
    
    public func loginWithSSO(email: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: email, remainCodeVerifier: true)
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: true, window: getRootVC()?.view.window, completionHandler: oauthCallback)
    }
    
    public func loginWithCustomSSO(ssoUrl: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        
        let directLogin: [String: Any] = [
            "type": "direct",
            "data": ssoUrl,
        ]
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: true)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate()
        }
        
        let (authorizeUrl, codeVerifier) = generatedUrl
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: true, completionHandler: oauthCallback)
    }
    
    public func embeddedLogin(_ _completion: FronteggAuth.CompletionHandler? = nil, loginHint: String?) {
        
        if let rootVC = self.getRootVC() {
            self.loginHint = loginHint
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
            
        } else {
            logger.critical(FronteggError.authError(.couldNotFindRootViewController).localizedDescription)
            exit(500)
        }
    }
    public func handleOpenUrl(_ url: URL, _ useAppRootVC: Bool = false, internalHandleUrl:Bool = false) -> Bool {
        if(!url.absoluteString.hasPrefix(self.baseUrl) && !internalHandleUrl){
            setAppLink(false)
            return false
        }
        
        guard let rootVC = self.getRootVC(useAppRootVC) else {
            self.logger.error(FronteggError.authError(.couldNotFindRootViewController).localizedDescription)
            return false;
        }
        
        if let socialLoginUrl = handleSocialLoginCallback(url){
            if let webView = self.webview {
                let request = URLRequest(url: socialLoginUrl, cachePolicy: .reloadRevalidatingCacheData)
                webView.load(request)
                return true
            }else {
                self.pendingAppLink = socialLoginUrl
            }
        }else {
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
                        self.pendingAppLink = authorizeUrl
                        self.setWebLoading(true)
                        self.embeddedLogin(completion, loginHint: nil)
                        return
                    }
                    
                    let oauthCallback = self.createOauthCallbackHandler(completion ?? { _ in })
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
