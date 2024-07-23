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
    
    public var embeddedMode: Bool
    public var isRegional: Bool
    public var regionData: [RegionConfig]
    public var baseUrl: String
    public var clientId: String
    public var applicationId: String? = nil
    public var pendingAppLink: URL? = nil

    
    public static var shared: FronteggAuth {
        return FronteggApp.shared.auth
    }
    
    private let logger = getLogger("FronteggAuth")
    private let credentialManager: CredentialManager
    public var api: Api
    private var subscribers = Set<AnyCancellable>()
    var webAuthentication: WebAuthentication = WebAuthentication()
    
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
        
        if ( isRegional || isLateInit == true ) {
            initializing = false
            showLoader = false
            return;
        }
        
        
        self.initializeSubscriptions()
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
                
                let offset = Double((decode["exp"] as! Int) - Int(Date().timeIntervalSince1970))  * 0.9
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + offset) {
                    Task{
                        await self.refreshTokenIfNeeded()
                    }
                }
            }
        } catch {
            logger.error("Failed to load user data, \(error)")
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
        guard let refreshToken = self.refreshToken, let accessToken = self.accessToken else {
            return false
        }
        
        if let data = await self.api.refreshToken(accessToken: accessToken, refreshToken: refreshToken) {
            await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
            return true
        } else {
            DispatchQueue.main.sync {
                self.initializing = false
                self.isAuthenticated = false
                self.accessToken = nil
                self.refreshToken = nil
                self.credentialManager.clear()
                
                // isLoading must be at the last bottom
                self.isLoading = false
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
                completion(.failure(FronteggError.authError("Failed to authenticate with frontegg")))
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
                completion(.failure(FronteggError.authError("Failed to load user data: \(error.localizedDescription)")))
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
            
            if error != nil {
                completion(.failure(FronteggError.authError(error!.localizedDescription)))
                return
            }
            
            guard let url = callbackUrl else {
                let errorMessage = "Unknown error occurred"
                completion(.failure(FronteggError.authError(errorMessage)))
                return
            }
            
            
            self.logger.trace("handleHostedLoginCallback, url: \(url)")
            guard let queryItems = getQueryItems(url.absoluteString), let code = queryItems["code"] else {
                let error = FronteggError.authError("Failed to get extract code from hostedLoginCallback url")
                completion(.failure(error))
                return
            }
            
            guard let codeVerifier = CredentialManager.getCodeVerifier() else {
                let error = FronteggError.authError("IlligalState, codeVerifier not found")
                completion(.failure(error))
                return
            }
            
            self.handleHostedLoginCallback(code, codeVerifier, completion)
        }
        
    }
    public typealias CompletionHandler = (Result<User, FronteggError>) -> Void
    
    public func login(_ _completion: FronteggAuth.CompletionHandler? = nil) {
        
        if(self.embeddedMode){
            self.embeddedLogin(_completion)
            return
        }
        
        let completion = _completion ?? { res in
            
        }
        self.webAuthentication.webAuthSession?.cancel()
        self.webAuthentication = WebAuthentication()
        
        let oauthCallback = createOauthCallbackHandler(completion)
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate()
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        
        self.webAuthentication.start(authorizeUrl, completionHandler: oauthCallback)
        
    }
    
    
    public func loginWithPopup(window: UIWindow?, ephemeralSesion: Bool? = true, loginHint: String? = nil, loginAction: String? = nil, _completion: FronteggAuth.CompletionHandler? = nil) {
        
        self.webAuthentication.webAuthSession?.cancel()
        self.webAuthentication = WebAuthentication()
        self.webAuthentication.window = window;
        self.webAuthentication.ephemeralSesion = ephemeralSesion ?? true
        
        let completion = _completion ?? { res in
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: loginHint, loginAction: loginAction)
        CredentialManager.saveCodeVerifier(codeVerifier)
        self.webAuthentication.start(authorizeUrl, completionHandler: oauthCallback)
    }
    
    public func directLoginAction(window: UIWindow?, type: String, data: String, ephemeralSesion: Bool? = true, _completion: FronteggAuth.CompletionHandler? = nil) {
        
        self.webAuthentication.webAuthSession?.cancel()
        self.webAuthentication = WebAuthentication()
        self.webAuthentication.window = window ?? getRootVC()?.view.window;
        self.webAuthentication.ephemeralSesion = ephemeralSesion ?? true
        
        let completion = _completion ?? { res in
            
        }
        
        let directLogin = [
            "type": type,
            "data": data,
            "additionalQueryParams": [
                "prompt": "consent"
            ]
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
        self.webAuthentication.start(authorizeUrl, completionHandler: oauthCallback)
        
        
        
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
        let completion = _completion ?? { res in
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        self.webAuthentication.webAuthSession?.cancel()
        self.webAuthentication = WebAuthentication()
        self.webAuthentication.ephemeralSesion = true
        self.webAuthentication.window = getRootVC()?.view.window
        
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: email, remainCodeVerifier: true)
        CredentialManager.saveCodeVerifier(codeVerifier)
        
        self.webAuthentication.start(authorizeUrl, completionHandler: oauthCallback)
    }
    
    func loginWithSocialLogin(socialLoginUrl: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? { res in
            
        }
        
        let oauthCallback = createOauthCallbackHandler(completion)
        self.webAuthentication.webAuthSession?.cancel()
        self.webAuthentication = WebAuthentication()
        self.webAuthentication.window = getRootVC()?.view.window
        
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
        
        self.webAuthentication.start(authorizeUrl, completionHandler: oauthCallback)
    }
    
    public func embeddedLogin(_ _completion: FronteggAuth.CompletionHandler? = nil) {
        
        if let rootVC = self.getRootVC() {
            let loginModal = EmbeddedLoginModal(parentVC: rootVC)
            let hostingController = UIHostingController(rootView: loginModal)
            hostingController.modalPresentationStyle = .fullScreen
            
            if(rootVC.presentedViewController?.classForCoder == hostingController.classForCoder){
                rootVC.presentedViewController?.dismiss(animated: false)
            }
            
            rootVC.present(hostingController, animated: false, completion: nil)
            
        } else {
            logger.critical(FronteggError.authError("Unable to find root viewController").localizedDescription)
            exit(500)
        }
    }
    public func handleOpenUrl(_ url: URL, _ useAppRootVC: Bool = false) -> Bool {
        
        if(!url.absoluteString.hasPrefix(self.baseUrl)){
            self.appLink = false
            return false
        }
        
        guard let rootVC = self.getRootVC(useAppRootVC) else {
            logger.error(FronteggError.authError("Unable to find root viewController").localizedDescription)
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
        
        self.webAuthentication.webAuthSession?.cancel()
        self.webAuthentication = WebAuthentication()
        let oauthCallback = createOauthCallbackHandler() { res in
            
            switch (res) {
            case .success(let user) :
                self.logger.trace("User \(user.id)")
            case .failure(let error) :
                self.logger.trace("Error \(error)")
            }
        }
        self.webAuthentication.start(url, completionHandler: oauthCallback)
        
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
                    completion?(.failure(FronteggError.authError("Failed to swift tenant")))
                }
                
            }
        }
        
        
    }
    
}


