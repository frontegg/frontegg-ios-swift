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


public class FronteggAuth: ObservableObject {
    @Published public var accessToken: String?
    @Published public var refreshToken: String?
    @Published public var user: User?
    @Published public var isAuthenticated = false
    @Published public var isLoading = true
    @Published public var webLoading = true
    @Published public var initializing = true
    @Published public var showLoader = true
    @Published public var appLink: Bool = false
    @Published public var externalLink: Bool = false
    public var embeddedMode: Bool = false
    
    public var baseUrl = ""
    public var clientId = ""
    public var pendingAppLink: URL? = nil
    
    
    
    public static var shared: FronteggAuth {
        return FronteggApp.shared.auth
    }
    
    private let logger = getLogger("FronteggAuth")
    private let credentialManager: CredentialManager
    public let api: Api
    private var subscribers = Set<AnyCancellable>()
    var webAuthentication: WebAuthentication = WebAuthentication()
    
    init (baseUrl:String, clientId: String, api:Api, credentialManager: CredentialManager) {
        
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.credentialManager = credentialManager
        self.api = api
        self.embeddedMode = PlistHelper.isEmbeddedMode()
        
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
            print(error)
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
    
    public func logout() {
        self.isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                await self.api.logout(accessToken: self.accessToken, refreshToken: self.refreshToken)
            }
            DispatchQueue.main.async {
                
                let dataTypesToRemove: Set<String> = [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage]


                let dateFrom = Date(timeIntervalSince1970: 0)
                WKWebsiteDataStore.default().removeData(ofTypes: dataTypesToRemove, modifiedSince: dateFrom) {
                    print("cookie removed")
                }
                
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
                }
            }
        }
        
    }
    
    public func refreshTokenIfNeeded() async {
        guard let refreshToken = self.refreshToken, let accessToken = self.accessToken else {
            return
        }
        
        if let data = await self.api.refreshToken(accessToken: accessToken, refreshToken: refreshToken) {
            await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
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
    }
    
    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String, _ completion: @escaping FronteggAuth.CompletionHandler) {
        
        let redirectUri = generateRedirectUri()
        setIsLoading(true)
        
        Task {
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
                let user = try await self.api.me(accessToken: data.access_token)
                await setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                
                completion(.success(user!))
            } catch {
                print("Failed to load user data: \(error.localizedDescription)")
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
        try! credentialManager.save(key: KeychainKeys.codeVerifier.rawValue, value: codeVerifier)
        
        self.webAuthentication.start(authorizeUrl, completionHandler: oauthCallback)
        
    }
    
    
    internal func getRootVC() -> UIViewController? {
        
        if let appDelegate = UIApplication.shared.delegate,
            let window = appDelegate.window,
            let rootVC = window?.rootViewController {
                    return rootVC
        }
        
        if let lastWindow = UIApplication.shared.windows.last,
           let rootVC = lastWindow.rootViewController {
            return rootVC
        }
        
        return nil
    }
    
    
    public func embeddedLogin(_ _completion: FronteggAuth.CompletionHandler? = nil) {
        
        if let rootVC = self.getRootVC() {
            let loginModal = EmbeddedLoginModal(parentVC: rootVC)
            let hostingController = UIHostingController(rootView: loginModal)
            hostingController.modalPresentationStyle = .fullScreen
            
            rootVC.present(hostingController, animated: false, completion: nil)
            
        } else {
            print(FronteggError.authError("Unable to find root viewController"))
            exit(500)
        }
    }
    public func handleOpenUrl(_ url: URL) -> Bool {
        
        if(!url.absoluteString.hasPrefix(self.baseUrl)){
            self.appLink = false
            return false
        }
        
        if(self.embeddedMode){
            self.pendingAppLink = url
            self.webLoading = true
            guard let rootVC = self.getRootVC() else {
                print(FronteggError.authError("Unable to find root viewController"))
                return false;
            }
            
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
                print("User \(user.id)")
            case .failure(let error) :
                print("Error \(error)")
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
                await self.refreshTokenIfNeeded()
                
                if(completion != nil){
                    if let user = self.user {
                        completion?(.success(user))
                    }else {
                        completion?(.failure(FronteggError.authError("Failed to swift tenant")))
                    }
                }
            }
        }
        
        
    }
    
}


