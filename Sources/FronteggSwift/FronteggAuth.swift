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
    public var api: Api
    private var subscribers = Set<AnyCancellable>()
    private var refreshTokenDispatch: DispatchWorkItem?
    var loginCompletion: CompletionHandler? = nil
    
    init (baseUrl:String,
          clientId: String,
          applicationId: String?,
          credentialManager: CredentialManager,
          isRegional: Bool,
          regionData: [RegionConfig],
          embeddedMode: Bool,
          isLateInit: Bool? = false) {
        self.isRegional = isRegional
        self.regionData = regionData
        self.lateInit = isLateInit ?? false
        self.credentialManager = credentialManager
        
        self.embeddedMode = embeddedMode
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
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
    
    
    
    func scheduleTokenRefresh(offset: TimeInterval) {
        cancelScheduledTokenRefresh()
        logger.info("Schedule token refresh after, (\(offset) s)")
        
        var workItem: DispatchWorkItem? = nil
        workItem = DispatchWorkItem {
            if !(workItem!.isCancelled) {
                Task {
                    await self.refreshTokenIfNeeded()
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
            DispatchQueue.main.async {
                
                self.credentialManager.clear()
                
                DispatchQueue.main.async {
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
    }
    public func logout() {
        logout { res in
            print("logged out")
        }
    }
    
    public func refreshTokenIfNeeded() async -> Bool {
        
        guard await NetworkStatusMonitor.isActive else {
            self.logger.info("Refresh rescheduled due to inactive internet")
            
            scheduleTokenRefresh(offset: 10)
            return false
        }
        
        guard let refreshToken = self.refreshToken else {
            self.logger.info("No refresh token found")
            return false
        }
        
        self.logger.info("Refreshing token")
        
        if(self.refreshingToken){
            self.logger.info("Skip refreshing token - already in progress")
            return false
        }
        
        DispatchQueue.main.sync {
            self.refreshingToken=true
        }
        
        defer {
            // cleanup scope
            DispatchQueue.main.sync {
                self.refreshingToken = false
            }
        }
        
        
        do {
            if let data = try await self.api.refreshToken(refreshToken: refreshToken) {
                await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                self.logger.info("Token refreshed successfully")
                return true
            } else {
                self.logger.info("Refresh rescheduled due to unknown error")
                scheduleTokenRefresh(offset: 10)
            }
        }catch {
            if let err = error as? FronteggError, err.failureReason == "failedToRefreshToken" {
                DispatchQueue.main.sync {
                    self.initializing = false
                    self.isAuthenticated = false
                    self.accessToken = nil
                    self.refreshToken = nil
                    self.credentialManager.clear()
                    // isLoading must be at the last bottom
                    self.isLoading = false
                }
            }else {
                self.logger.info("Refresh rescheduled due to unknown error")
                scheduleTokenRefresh(offset: 10)
            }
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
    
    public func directLoginAction(window: UIWindow?, type: String, data: String, ephemeralSession: Bool? = true, _completion: FronteggAuth.CompletionHandler? = nil) {
        
        
        let completion = _completion ?? { res in
            
        }
        
        if(type == "social-login" && data == "apple") {
            self.loginWithApple(completion)
            return
        }
        
        let directLogin = [
            "type": type,
            "data": data,
        ] as [String : Any]
        
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString)
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
                        Task {
                            await self.startMultiFactorAuthenticator(jsonResponse, refreshToken:refreshToken, completion: _completion)
                        }
                        return
                    } else {
                        self.logger.info("authentication error: \(authError.localizedDescription)")
                    }
                case .configError(let configError):
                    self.logger.info("config error: \(configError.localizedDescription)")
                }
                
                DispatchQueue.main.async {
                    FronteggAuth.shared.isLoading = false
                    _completion?(result)
                }
            }
        }
        return completion
    }
    
    
    internal func startMultiFactorAuthenticator(_ errorResponse: [String: Any], refreshToken:String? = nil, completion: FronteggAuth.CompletionHandler? = nil) async {
        
        
        var jsonResponse = errorResponse;
        
        if let refreshTokenCookie = refreshToken {
            guard let requestMfaDict = await self.api.refreshTokenForMfa(refreshTokenCookie: refreshTokenCookie) else {
                print("Failed get mfaRequired data after refreshToken")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                completion?(.failure(.authError(.failedToAuthenticate)))
                return
            }
            jsonResponse = requestMfaDict
            
        }
        // Convert the JSON dictionary to Data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonResponse, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to serialize JSON response.")
            DispatchQueue.main.async {
                self.isLoading = false
            }
            completion?(.failure(.authError(.failedToAuthenticate)))
            return
        }
        
        // Encode the JSON string as Base64
        let base64EncodedState = Data(jsonString.utf8).base64EncodedString()
        
        let directLogin = [
            "type": "direct",
            "data": "\(self.baseUrl)/oauth/account/mfa-mobile-authenticator?state=\(base64EncodedState)",
        ] as [String : Any]
        
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate()
        }
        
        let (authorizeUrl, codeVerifier) = generatedUrl
        
        CredentialManager.saveCodeVerifier(codeVerifier)
        DispatchQueue.main.async {
            self.pendingAppLink = authorizeUrl
            self.webLoading = true
            self.login(completion)
            self.isLoading = false
        }
    }
    
}


