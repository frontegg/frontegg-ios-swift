//
//  FronteggAuth.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import WebKit
import Combine
import AuthenticationServices


public class FronteggAuth: ObservableObject {
    @Published public var accessToken: String?
    @Published public var refreshToken: String?
    @Published public var user: User?
    @Published public var isAuthenticated = false
    @Published public var isLoading = true
    @Published public var initializing = true
    @Published public var showLoader = true
    @Published public var pendingAppLink: URL?
    @Published public var appLink: URL?
    @Published public var externalLink = false
    public var baseUrl = ""
    public var clientId = ""
    public var codeVerifier: String? = nil
    
    
    
    public static var shared: FronteggAuth {
        return FronteggApp.shared.auth
    }
    
    private let logger = getLogger("FronteggAuth")
    private let credentialManager: CredentialManager
    public let api: Api
    private var subscribers = Set<AnyCancellable>()
    private var webAuthentication: WebAuthentication? = nil
    
    init (baseUrl:String, clientId: String, api:Api, credentialManager: CredentialManager) {
        
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.credentialManager = credentialManager
        self.api = api
        
        self.$initializing.combineLatest(self.$isAuthenticated, self.$isLoading).sink(){ (initializingValue, isAuthenticatedValue, isLoadingValue) in
            self.showLoader = initializingValue || (!isAuthenticatedValue && isLoadingValue)
        }.store(in: &subscribers)
        
        
        self.$pendingAppLink.sink() { pendingAppLinkValue in
            if(pendingAppLinkValue != nil){
                DispatchQueue.main.async {
                    self.appLink = pendingAppLinkValue
                    self.pendingAppLink = nil
                }
            }
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
        }else {
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
                self.pendingAppLink = nil
                self.appLink = nil
                
                let offset = Double((decode["exp"] as! Int) - Int(Date().timeIntervalSince1970))  * 0.9
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + offset) {
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
            }
        }
        
        DispatchQueue.main.sync {
            self.isLoading = false
            self.initializing = false
        }
    }
    
    public func logout() {
        self.isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                await self.api.logout(accessToken: self.accessToken, refreshToken: self.refreshToken)
                
                DispatchQueue.main.sync {
                    let dataStore = WKWebsiteDataStore.default()
                    dataStore.fetchDataRecords(ofTypes: [WKWebsiteDataTypeCookies]) { records in
                        dataStore.removeData(
                            ofTypes: [WKWebsiteDataTypeCookies],
                            for: records.filter { _ in true }) {
                                self.credentialManager.clear()
                                
                                DispatchQueue.main.async {
                                    self.isAuthenticated = false
                                    self.isLoading = false
                                    self.user = nil
                                    self.accessToken = nil
                                    self.refreshToken = nil
                                    self.initializing = false
                                }
                            }
                    }
                }
            }
            
        }
        
    }
    
    func refreshTokenIfNeeded() async {
        guard let refreshToken = self.refreshToken, let accessToken = self.accessToken else {
            return
        }
        
        if let data = await self.api.refreshToken(accessToken: accessToken, refreshToken: refreshToken) {
            await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
        } else {
            DispatchQueue.main.sync {
                self.initializing = false
                self.isLoading = false
                self.isAuthenticated = false
            }
        }
    }
    
    func handleHostedLoginCallback(_ code: String, _ codeVerifier: String, _ completion: @escaping FronteggAuth.CompletionHandler) {
        
        let redirectUri = generateRedirectUri()
        
        Task {
            
            let (responseData, error) = await api.exchangeToken(
                code: code,
                redirectUrl: redirectUri,
                codeVerifier: codeVerifier
            )
            
            guard error == nil else {
                completion(.failure(error!))
                return
            }
            
            guard let data = responseData else {
                completion(.failure(FronteggError.authError("Failed to authenticate with frontegg")))
                return
            }
            
            
            
            do {
                let user = try await self.api.me(accessToken: data.access_token)
                await setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                
                completion(.success(user!))
            } catch {
                completion(.failure(FronteggError.authError("Failed to load user data: \(error.localizedDescription)")))
                return
            }
            
        }
        
    }
    
    
    func createCompletionHandler(message: String) -> ((Bool) -> Void) {
        return { (isSuccess: Bool) in
            if isSuccess {
                print("\(message) - Task completed successfully.")
            } else {
                print("\(message) - Task failed.")
            }
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

            guard let codeVerifier = self.codeVerifier else {
                let error = FronteggError.authError("IlligalState, codeVerifier not found")
                completion(.failure(error))
                return
            }
            print("code: \(code), codeVerifier: \(self.codeVerifier)")
            
            self.handleHostedLoginCallback(code, codeVerifier, completion)
        }
        
    }
    public typealias CompletionHandler = (Result<User, FronteggError>) -> Void
    
    public func login( completion: @escaping FronteggAuth.CompletionHandler) {
        
        self.webAuthentication?.webAuthSession?.cancel()
        self.webAuthentication = WebAuthentication()
        
        let oauthCallback = createOauthCallbackHandler(completion)
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate()
        
        self.codeVerifier = codeVerifier
        self.webAuthentication!.start(authorizeUrl, completionHandler: oauthCallback)
        
        
        // check if no error
        // check if callbackUrl is magic link
        //  - display magic link message
        //  option 2:
        //    - user close the popup
        //    - app opened from email link
        //    - open another time the login popup with the magic link
        //    NOTE: require adding support to force relogin in authorize parameter
        // check if callbackUrl is success login
        //  - display loader
        //  - exchange token
        
    }
    
}


