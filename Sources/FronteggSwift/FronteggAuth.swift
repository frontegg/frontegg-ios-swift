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

public class FronteggAuth: ObservableObject {
    @Published public var accessToken: String?
    @Published public var refreshToken: String?
    @Published public var user: User?
    @Published public var isAuthenticated = false
    @Published public var isStepUpAuthorization = false
    @Published public var isReAuthorization = false
    @Published public var isLoading = true
    @Published public var webLoading = true
    @Published public var initializing = true
    @Published public var lateInit = false
    @Published public var showLoader = true
    @Published public var appLink: Bool = false
    @Published public var externalLink: Bool = false
    @Published public var selectedRegion: RegionConfig? = nil
    @Published public var refreshingToken: Bool = false
    
    public var embeddedMode: Bool
    public var isRegional: Bool
    public var regionData: [RegionConfig]
    public var baseUrl: String
    public var clientId: String
    public var applicationId: String? = nil
    public var pendingAppLink: URL? = nil
    public var loginHint: String? = nil

    
    
    public static var shared: FronteggAuth {
        return FronteggApp.shared.auth
    }
    
    private let logger = getLogger("FronteggAuth")
    private let credentialManager: CredentialManager
    private var multiFactorAuthenticator: MultiFactorAuthenticator
    private var stepUpAuthenticator: StepUpAuthenticator
    public var api: Api
    private var subscribers = Set<AnyCancellable>()
    private var refreshTokenDispatch: DispatchWorkItem?
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
        self.lateInit = isLateInit ?? false
        self.credentialManager = credentialManager
        
        self.embeddedMode = embeddedMode
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.multiFactorAuthenticator = MultiFactorAuthenticator(api: api, baseUrl: baseUrl)
        self.stepUpAuthenticator = StepUpAuthenticator(credentialManager: credentialManager)
        
        self.selectedRegion = self.getSelectedRegion()

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
            initializing = false
            showLoader = false
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
        self.lateInit = false
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.isRegional = false
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.initializeSubscriptions()
    }
    
    public func manualInitRegions(regions:[RegionConfig]) {
        
        self.lateInit = false
        self.isRegional = true
        self.regionData = regions
        self.selectedRegion = self.getSelectedRegion()
        
        if let config = self.selectedRegion {
            self.baseUrl = config.baseUrl
            self.clientId = config.clientId
            self.applicationId = config.applicationId
            self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
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
        self.selectedRegion = config
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        
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
    
    public func initializeSubscriptions() {
        self.$initializing.combineLatest(self.$isAuthenticated, self.$isLoading).sink(){ (initializingValue, isAuthenticatedValue, isLoadingValue) in
            self.showLoader = initializingValue || (!isAuthenticatedValue && isLoadingValue)
        }.store(in: &subscribers)
        
        if let refreshToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue),
           let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            
            self.refreshToken = refreshToken
            self.accessToken = accessToken
            self.isLoading = true
            
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    await self.refreshTokenIfNeeded()
                }
            }
        } else {
            self.isLoading = false
            self.initializing = false
        }
    }
    
    
    public func setCredentials(accessToken: String, refreshToken: String) async {
        
        do {
            try self.credentialManager.save(key: KeychainKeys.refreshToken.rawValue, value: refreshToken)
            try self.credentialManager.save(key: KeychainKeys.accessToken.rawValue, value: accessToken)
            
            let decode = try JWTHelper.decode(jwtToken: accessToken)
            let user = try await self.api.me(accessToken: accessToken)
            
            
            DispatchQueue.main.sync {
                self.refreshToken = refreshToken
                self.accessToken = accessToken
                self.user = user
                self.isAuthenticated = true
                self.appLink = false
                self.initializing = false
                self.appLink = false
                self.isStepUpAuthorization = false
                self.isReAuthorization = false
                
                // isLoading must be at the bottom
                self.isLoading = false
                
                
                let offset = calculateOffset(expirationTime: decode["exp"] as! Int)
                
                scheduleTokenRefresh(offset: offset)
                
            }
        } catch {
            logger.error("Failed to load user data: \(error)")
            DispatchQueue.main.sync {
                self.refreshToken = nil
                self.accessToken = nil
                self.user = nil
                self.isAuthenticated = false
                self.initializing = false
                self.appLink = false
                
                // isLoading must be at the last bottom
                self.isLoading = false
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
            
            // Check if the refresh token is available
            guard let _ = self.refreshToken else {
                logger.debug("No refresh token available. Exiting...")
                return
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
        workItem = DispatchWorkItem {
            if !(workItem!.isCancelled) {
                Task {
                    await self.refreshTokenIfNeeded(attempts: attempts)
                }
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
    
    public func logout(_ completion: @escaping (Result<Bool, FronteggError>) -> Void) {
        self.isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                await self.api.logout(accessToken: self.accessToken, refreshToken: self.refreshToken)
            }
            DispatchQueue.main.sync {
                self.credentialManager.clear()
                self.isAuthenticated = false
                self.user = nil
                self.accessToken = nil
                self.refreshToken = nil
                self.initializing = false
                self.appLink = false
                
                // isLoading must be at the last bottom
                self.isLoading = false
                completion(.success(true));
            }
        }
    }
    public func logout() {
        logout { res in
            print("logged out")
        }
    }
    
    public func refreshTokenIfNeeded(attempts: Int = 0) async -> Bool {
        
        guard let refreshToken = self.refreshToken else {
            self.logger.info("No refresh token found")
            return false
        }
        
        
        guard await NetworkStatusMonitor.isActive else {
            self.logger.info("Refresh rescheduled due to inactive internet")
            
            
            if(attempts > 5){
                DispatchQueue.main.sync {
                    self.initializing = false
                    self.isAuthenticated = false
                    self.refreshingToken = false
                    // isLoading must be at the last bottom
                    self.isLoading = false
                }
                scheduleTokenRefresh(offset: 10, attempts: attempts + 1)
            }else {
                // attempt = 0 to prevent abandon refresh token due to network errors
                scheduleTokenRefresh(offset: 2, attempts: attempts + 1)
            }
            return false
        }
        
        if (attempts > 10) {
            self.logger.info("refresh token attemps exceeded, logging out")
            self.credentialManager.clear()
            DispatchQueue.main.sync {
                self.initializing = false
                self.isAuthenticated = false
                self.accessToken = nil
                self.refreshToken = nil
                self.refreshingToken = false
                // isLoading must be at the last bottom
                self.isLoading = false
            }
            return false
        }
        
        
        
        if(self.refreshingToken){
            self.logger.info("Skip refreshing token - already in progress")
            return false
        }
        
        self.logger.info("Refreshing token")
        
        
        DispatchQueue.main.sync {
            self.refreshingToken = true
        }
        
        defer {
            // cleanup scope
            DispatchQueue.main.sync {
                self.refreshingToken = false
            }
        }
        
        
        do {
            let data = try await self.api.refreshToken(refreshToken: refreshToken)
            await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
            self.logger.info("Token refreshed successfully")
            return true
            
        } catch let error as FronteggError {
            switch error {
            case .authError(FronteggError.Authentication.failedToRefreshToken):
                DispatchQueue.main.sync {
                    self.initializing = false
                    self.isAuthenticated = false
                    self.accessToken = nil
                    self.refreshToken = nil
                    self.credentialManager.clear()
                    // isLoading must be at the last bottom
                    self.isLoading = false
                }
            default:
                self.logger.info("Refresh rescheduled due to unknown error \(error.localizedDescription)")
                scheduleTokenRefresh(offset: 1, attempts: attempts + 1)
            }
        } catch {
            self.logger.info("Refresh rescheduled due to unknown error \(error.localizedDescription)")
            scheduleTokenRefresh(offset: 1, attempts: attempts + 1)
        }
        return false
        
    }
    
    
    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String, _ completion: @escaping FronteggAuth.CompletionHandler) {
        
        let redirectUri = generateRedirectUri()
        setIsLoading(true)
        
        Task {
            
            logger.info("Going to exchange token")
            let (responseData, error) = await api.exchangeToken(
                code: code,
                redirectUrl: redirectUri,
                codeVerifier: codeVerifier
            )
            
            guard error == nil else {
                completion(.failure(error!))
                setIsLoading(false)
                return
            }
            
            guard let data = responseData else {
                completion(.failure(FronteggError.authError(.failedToAuthenticate)))
                setIsLoading(false)
                return
            }
            
            do {
                logger.info("Going to load user data")
                let user = try await self.api.me(accessToken: data.access_token)
                await setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                
                completion(.success(user!))
            } catch {
                logger.error("Failed to load user data: \(error.localizedDescription)")
                completion(.failure(FronteggError.authError(.failedToLoadUserData(error.localizedDescription))))
                setIsLoading(false)
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
        
        guard let refreshToken = self.refreshToken else {
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
        
        self.refreshingToken = true
        defer {
            self.refreshingToken = false
        }
        
        var attempts = 0
        while attempts < 5 {
            do {
                let data = try await self.api.refreshToken(refreshToken: refreshToken)
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
    
    
    internal func setIsLoading(_ isLoading: Bool){
        DispatchQueue.main.async {
            self.isLoading = isLoading
        }
    }
    
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
            
            
            self.logger.trace("handleHostedLoginCallback, url: \(url)")
            guard let queryItems = getQueryItems(url.absoluteString), let code = queryItems["code"] else {
                let error = FronteggError.authError(.failedToExtractCode)
                completion(.failure(error))
                return
            }
            
            guard let codeVerifier = CredentialManager.getCodeVerifier() else {
                let error = FronteggError.authError(.codeVerifierNotFound)
                completion(.failure(error))
                return
            }
            
            self.handleHostedLoginCallback(code, codeVerifier, completion)
        }
        
    }
    public typealias CompletionHandler = (Result<User, FronteggError>) -> Void
    
    public typealias AccessTokenHandler = (Result<String?, Error>) -> Void
    
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
    
    public func directLoginAction(
        window: UIWindow?, 
        type: String, 
        data: String, 
        ephemeralSession: Bool? = true, 
        _completion: FronteggAuth.CompletionHandler? = nil, 
        additionalQueryParams: [String: Any]? = nil, 
        remainCodeVerifier: Bool = false) {
        
        
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
    
    
    public func loginWithSSO(email: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: email, remainCodeVerifier: true)
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: true, window: getRootVC()?.view.window, completionHandler: oauthCallback)
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
                            AppleAuthenticator.shared.start(completionHandler: completion)
                        }else {
                            let oauthCallback = self.createOauthCallbackHandler(completion)
                            let url = try await self.generateAppleAuthorizeUrl(config: appleConfig)
                            WebAuthenticator.shared.start(url, ephemeralSession: true, completionHandler: oauthCallback)
                            
                        }
                    } else {
                        self.logger.error("No active apple configuration, for more info please visit https://docs.frontegg.com/docs/apple-login")
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
            self.logger.error("Failed to generate oauth2 session response: \(authorizeResponse)")
            throw FronteggError.authError(.failedToAuthenticate)
        }
        
        let oauthStateDic = [
            "FRONTEGG_OAUTH_REDIRECT_AFTER_LOGIN": generateRedirectUri(),
            "FRONTEGG_OAUTH_STATE_AFTER_LOGIN": sessionState,
        ]
        
        guard let oauthStateJson = try? JSONSerialization.data(withJSONObject: oauthStateDic, options: .withoutEscapingSlashes) else {
            self.logger.error("Failed to generate post login state, oauthState: \(oauthStateDic)")
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
            
            self.logger.error("Failed to generate apple authorization url")
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
        
        return urlComponent.url!
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
            self.appLink = false
            return false
        }
        
        guard let rootVC = self.getRootVC(useAppRootVC) else {
            logger.error(FronteggError.authError(.couldNotFindRootViewController).localizedDescription)
            return false;
        }
        
        if(self.embeddedMode){
            self.pendingAppLink = url
            self.webLoading = true
            
            
            let loginModal = EmbeddedLoginModal(parentVC: rootVC)
            let hostingController = UIHostingController(rootView: loginModal)
            hostingController.modalPresentationStyle = .fullScreen
            
            let presented = rootVC.presentedViewController
            if presented is UIHostingController<EmbeddedLoginModal> {
                rootVC.presentedViewController?.dismiss(animated: false)
            }
            rootVC.present(hostingController, animated: false, completion: nil)
            return true;
        }
        
        self.appLink = true
        
        
        let oauthCallback = createOauthCallbackHandler() { res in
            
            switch (res) {
            case .success(let user) :
                self.logger.trace("User \(user.id)")
            case .failure(let error) :
                self.logger.trace("Error \(error)")
            }
        }
        WebAuthenticator.shared.start(url, completionHandler: oauthCallback)
        
        return true
    }
    
    public func  switchTenant(tenantId:String,_ completion: FronteggAuth.CompletionHandler? = nil) {
        
        self.setIsLoading(true)
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                try? await self.api.switchTenant(tenantId: tenantId)
                
                if let user = self.user, await self.refreshTokenIfNeeded() && completion != nil {
                    completion?(.success(user))
                } else {
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
    
    
    
    public func requestAuthorizeAsync(refreshToken: String, deviceTokenCookie: String? = nil) async throws -> User {
        DispatchQueue.main.async {
            FronteggAuth.shared.isLoading = true
        }
        
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
            DispatchQueue.main.async {
                FronteggAuth.shared.isLoading = false
            }
            throw error
        }
    }
    
    public func requestAuthorize(refreshToken: String, deviceTokenCookie: String? = nil, _ completion: @escaping FronteggAuth.CompletionHandler) {
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let user = try await self.requestAuthorizeAsync(refreshToken: refreshToken, deviceTokenCookie: deviceTokenCookie)
                    DispatchQueue.main.async {
                        completion(.success(user)) // Assuming success is represented by empty parentheses
                    }
                } catch let error as FronteggError {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                } catch {
                    self.logger.error("Failed to authenticate: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(.failure(.authError(.failedToAuthenticate)))
                    }
                }
            }
        }
    }
    
    public func isSteppedUp(maxAge: TimeInterval? = nil) -> Bool {
        return self.stepUpAuthenticator.isSteppedUp(maxAge: maxAge)
    }
    
    public func stepUp(
        maxAge: TimeInterval? = nil,
        _ _completion: FronteggAuth.CompletionHandler? = nil
    ) async {
        return await stepUpAction(maxAge: maxAge, completion: _completion)
    }
    
    private func stepUpAction(
        maxAge: TimeInterval? = nil,
        completion: FronteggAuth.CompletionHandler? = nil,
        isAttempt: Bool = false
    ) async {
        let updatedCompletion: FronteggAuth.CompletionHandler = { (result) in
            DispatchQueue.main.async {
                self.isReAuthorization = false
                self.isStepUpAuthorization = false
                completion?(result)
            }
        }
        
        let loginCompletion: FronteggAuth.CompletionHandler = { result in
            switch result {
            case .success:
                if (self.stepUpAuthenticator.isSteppedUp()) {
                    return
                }
                
                Task {
                    await self.stepUpAction(maxAge: maxAge, completion: completion, isAttempt: true)
                }
            case .failure(let fronteggError):
                completion?(.failure(fronteggError))
            }
        }
        
        do {
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            if isAttempt {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            
            if let mfaRequestJson = try await self.api.generateStepUp(maxAge: maxAge) {
                DispatchQueue.main.async {
                    self.isStepUpAuthorization = true
                }
                self.startMultiFactorAuthenticator(
                    mfaRequestJson: mfaRequestJson,
                    refreshToken: nil,
                    completion: updatedCompletion
                )
            } else {
                if isAttempt {
                    completion?(.failure(FronteggError.authError(.notAuthenticated)))
                    return
                }
                
                DispatchQueue.main.async {
                    self.isReAuthorization = true
                    self.login(loginCompletion)
                }
            }
        } catch FronteggError.authError(.notAuthenticated) {
            if isAttempt {
                completion?(.failure(FronteggError.authError(.notAuthenticated)))
                return
            }
            
            DispatchQueue.main.async {
                self.isReAuthorization = true
                self.login(loginCompletion)
            }
        } catch {
            completion?(.failure(FronteggError.authError(.failedToMFA)))
        }
    }
    
    internal func handleMfaRequired(_ _completion: FronteggAuth.CompletionHandler? = nil) -> FronteggAuth.CompletionHandler {
        let completion: FronteggAuth.CompletionHandler =  { (result) in
            
            switch (result) {
            case .success(_):
                DispatchQueue.main.async {
                    FronteggAuth.shared.isLoading = false
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
                    FronteggAuth.shared.isLoading = false
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
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if self.embeddedMode {
                        self.pendingAppLink = authorizeUrl
                        self.webLoading = true
                        self.embeddedLogin(completion, loginHint: nil)
                        return
                    }
                    
                    let oauthCallback = self.createOauthCallbackHandler(completion ?? { _ in })
                    WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
                }
            } catch let error as FronteggError {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                completion?(.failure(error))
            }
        }
    }
    
}


