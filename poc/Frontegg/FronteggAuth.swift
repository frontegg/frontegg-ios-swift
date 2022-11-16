//
//  FronteggAuth.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import WebKit



enum FronteggError: Error {
    case configError(String)
}

class FronteggAuth: ObservableObject {
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var user: FronteggUser?
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var initializing = true
    
    
    enum KeychainKeys: String {
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
    }
    
    
    private let credentialManager: FronteggCredentialManager
    private let api: FronteggApi
    
    init() throws {
        let data = try FronteggAuth.plistValues(bundle: Bundle.main)
        
        self.credentialManager = FronteggCredentialManager(serviceKey: data.keychainService)
        self.api = FronteggApi(baseUrl: data.baseUrl, clientId: data.clientId, credentialManager: self.credentialManager)
        
        
        if let refreshToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue),
           let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            
            self.refreshToken = refreshToken
            self.accessToken = accessToken
            self.isLoading = true
            
            self.initialize()
        }
    }
    
    
    public func setCredentials(accessToken: String, refreshToken: String) {
        
        do {
            try self.credentialManager.save(key: KeychainKeys.refreshToken.rawValue, value: refreshToken)
            try self.credentialManager.save(key: KeychainKeys.accessToken.rawValue, value: accessToken)
            
            let data = try self.decode(jwtToken: accessToken)
            let user = try FronteggUser( dictionary: data)
            
            self.refreshToken = refreshToken
            self.accessToken = accessToken
            self.user = user
            self.isAuthenticated = true
        } catch {
            print(error)
            self.refreshToken = nil
            self.accessToken = nil
            self.user = nil
            self.isAuthenticated = false
        }
        self.isLoading = false
        self.initializing = false
    }
    
    public func initialize() {
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                print(self.accessToken)
                await self.refreshTokenIfNeeded()
                print(self.accessToken)
                await self.loadUserData()
//                await loadTenants()
            }
        }
    }
    
    public func logout(){
        self.isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let dataStore = WKWebsiteDataStore.default()
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                dataStore.removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    for: records.filter { $0.displayName.contains("frontegg") }) {
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
    
    
    public func decode(jwtToken jwt: String) throws -> [String: Any] {
        
        enum DecodeErrors: Error {
            case badToken
            case other
        }
        
        func base64Decode(_ base64: String) throws -> Data {
            let base64 = base64
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let padded = base64.padding(toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
            guard let decoded = Data(base64Encoded: padded) else {
                throw DecodeErrors.badToken
            }
            return decoded
        }
        
        func decodeJWTPart(_ value: String) throws -> [String: Any] {
            let bodyData = try base64Decode(value)
            let json = try JSONSerialization.jsonObject(with: bodyData, options: [])
            guard let payload = json as? [String: Any] else {
                throw DecodeErrors.other
            }
            return payload
        }
        
        let segments = jwt.components(separatedBy: ".")
        return try decodeJWTPart(segments[1])
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
    
    private func refreshTokenIfNeeded() async {
        guard let refreshToken = self.refreshToken, let accessToken = self.accessToken else {
            return
        }
        
        if let data = await self.api.refreshToken(accessToken: accessToken, refreshToken: refreshToken) {
            DispatchQueue.main.sync {
                self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
            }
        } else {
            DispatchQueue.main.sync {
                self.initializing = false
                self.isLoading = false
                self.isAuthenticated = false
            }
        }
    }
    private func loadUserData() async {
        guard let accessToken = self.accessToken else {
            return
        }
        
        if let data = await self.api.me(accessToken: accessToken) {
            print(data)
        }
    }
    
}


