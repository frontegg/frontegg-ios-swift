//
//  FronteggApp.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation


public class FronteggApp {
    
    public static let shared = FronteggApp()
    
    public let auth: FronteggAuth
    public let baseUrl: String
    public let clientId: String
    let api: Api
    let credentialManager: CredentialManager
    
    init() {
        guard let data = try? PlistHelper.fronteggConfig() else {
            exit(1)
        }
            
        
        self.baseUrl = data.baseUrl
        self.clientId = data.clientId
        self.credentialManager = CredentialManager(serviceKey: data.keychainService)
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, credentialManager: self.credentialManager)
        
        self.auth = FronteggAuth(
            baseUrl: self.baseUrl,
            clientId: self.clientId,
            api: self.api,
            credentialManager: self.credentialManager
        )
    }
 
    public func didFinishLaunchingWithOptions(){
        self.auth.pendingAppLink = nil
    }
    
    
}
