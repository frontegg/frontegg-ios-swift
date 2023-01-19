//
//  FronteggAuth.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import WebKit
import Combine


enum FronteggError: Error {
    case configError(String)
}

public class FronteggAuth: ObservableObject {
    @Published public var accessToken: String?
    @Published public var refreshToken: String?
    @Published public var user: User?
    @Published public var isAuthenticated = false
    @Published public var isLoading = true
    @Published public var initializing = true
    @Published public var showLoader = true
    @Published public var pendingAppLink: URL?
    @Published public var externalLink = false
    public var baseUrl = ""
    public var clientId = ""
    public var codeVerifier = ""
    
    enum KeychainKeys: String {
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
    }
    
    public static var shared: FronteggAuth {
        return FronteggApp.shared.auth
    }
    
    private let credentialManager: CredentialManager
    public let api: Api
    private var subscribers = Set<AnyCancellable>()
    
    init (baseUrl:String, clientId: String, api:Api, credentialManager: CredentialManager) {
        
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.credentialManager = credentialManager
        self.api = api
        
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
    
    public func logout(){
        self.isLoading = true
        
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
    
    
    private static func plistValues(bundle: Bundle) throws -> (clientId: String, baseUrl: String, keychainService: String?) {
        guard let path = bundle.path(forResource: "Frontegg", ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            let errorMessage = "Missing Frontegg.plist file with 'clientId' and 'baseUrl' entries in main bundle!"
            print(errorMessage)
            throw FronteggError.configError(errorMessage)
        }
        
        guard let clientId = values["clientId"] as? String, let baseUrl = values["baseUrl"] as? String else {
            let errorMessage = "Frontegg.plist file at \(path) is missing 'clientId' and/or 'baseUrl' entries!"
            print(errorMessage)
            throw FronteggError.configError(errorMessage)
        }
        
        return (clientId: clientId, baseUrl: baseUrl, keychainService: values["keychainService"] as? String)
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
    
}


