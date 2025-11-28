//
//  CredentialManager.swift
//
//  Created by David Frontegg on 16/11/2022.
//

import Foundation

public enum KeychainKeys: String {
    case accessToken = "accessToken"
    case refreshToken = "refreshToken"
    case codeVerifier = "fe_codeVerifier"
    case region = "fe_region"
    case userInfo = "user_me"
    case lastActiveTenantId = "fe_lastActiveTenantId"
}


public class CredentialManager {
    
    
    public enum KeychainError: Error {
        case duplicateEntry;
        case valueDataIsNil;
        case unknown(OSStatus);
    }
    
    private let logger = getLogger("CredentialManager")
    private let serviceKey: String?
    
    init(serviceKey: String?) {
        self.serviceKey = serviceKey;
    }
    
    func save(key: String, value: String) throws {
        logger.trace("Saving \(key) in keyhcain")
        
        if let valueData = value.data(using: .utf8) {
            let query = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: serviceKey ?? "frontegg",
                kSecAttrAccount: key,
                kSecValueData: valueData,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
            ] as [CFString : Any] as CFDictionary
            
            let status = SecItemAdd(query, nil)
            
            if status == errSecDuplicateItem {
                logger.trace("Updating exising \(key)")
                let updateQuery = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: serviceKey ?? "frontegg",
                    kSecAttrAccount: key,
                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
                ] as [CFString : Any] as CFDictionary
                
                let newAttributes : CFDictionary = [
                    kSecValueData: value.data(using: .utf8)
                ] as CFDictionary
                
                let updateStatus = SecItemUpdate(updateQuery, newAttributes)
                if updateStatus != errSecSuccess {
                    throw KeychainError.unknown(updateStatus)
                }
            } else if status != errSecSuccess {
                throw KeychainError.unknown(status)
            }
            
            logger.info("\(key) saved in keyhcain")
        } else {
            
            logger.error("failed to convert value to Data, value: \(value)")
            throw KeychainError.valueDataIsNil
        }
    }
    
    func get(key:String) throws -> String? {
        logger.trace("retrieving \(key) from keyhcain")
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceKey ?? "frontegg",
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString : Any] as CFDictionary
        
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        
        if status != errSecSuccess {
            //logger.error("Unknown error occured while trying to retrieve the key: \(key) from keyhcain")
            throw KeychainError.unknown(status)
        }
        
        if let resultData = result as? Data {
            logger.trace("Value found in keychain for key: \(key)")
            return String(decoding: resultData, as: UTF8.self)
        }
        
        logger.trace("Value not found in keychain for key: \(key), returned nil")
        return nil
    }
    
    func delete(key: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceKey ?? "frontegg",
            kSecAttrAccount: key
        ] as [CFString : Any] as CFDictionary

        let status = SecItemDelete(query)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete key \(key) from keychain, errSec: \(status)")
        } else {
            logger.info("Deleted key \(key) from keychain")
        }
    }
    
    func clear() {
        logger.trace("Clearing keychain frontegg data")
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceKey ?? "frontegg"
        ] as [CFString : Any] as CFDictionary
        let status = SecItemDelete(query)
        
        if status != errSecSuccess {
            logger.error("Failed to logout from Frontegg Services, errSec: \(status)")
        }
    }
    
    static func saveCodeVerifier(_ codeVerifier: String) {
        UserDefaults.standard.set(codeVerifier, forKey: KeychainKeys.codeVerifier.rawValue)
    }
    
    static func getCodeVerifier() -> String? {
        return UserDefaults.standard.string(forKey: KeychainKeys.codeVerifier.rawValue)
    }
    
    
    static func saveSelectedRegion(_ region: String) {
        UserDefaults.standard.set(region, forKey: KeychainKeys.region.rawValue)
    }
    
    static func getSelectedRegion() -> String? {
        return UserDefaults.standard.string(forKey: KeychainKeys.region.rawValue)
    }
    
    
    
    func saveOfflineUser(user: User?) {
        let key = KeychainKeys.userInfo.rawValue
        
        guard let user = user else {
            logger.trace("Removing offline user from keychain")
            delete(key: key)
            return
        }
        
        do {
            let data = try JSONEncoder().encode(user)
            guard let json = String(data: data, encoding: .utf8) else {
                logger.error("Failed to encode User to UTF-8 string")
                return
            }
            try save(key: key, value: json)
        } catch {
            logger.error("Failed to save offline user: \(error)")
        }
    }
    func getOfflineUser() -> User? {
        
        if let userInfo = try? self.get(key: KeychainKeys.userInfo.rawValue),
           let data = userInfo.data(using: .utf8),
           let user = try? JSONDecoder().decode(User.self, from: data){
            return user
        }
        return nil
    }
    
    func saveTokenForTenant(_ token: String, tenantId: String, tokenType: KeychainKeys) throws {
        let key = "\(tokenType.rawValue)_\(tenantId)"
        try save(key: key, value: token)
    }
    
    func getTokenForTenant(tenantId: String, tokenType: KeychainKeys) throws -> String? {
        let key = "\(tokenType.rawValue)_\(tenantId)"
        return try get(key: key)
    }
    
    func deleteTokenForTenant(tenantId: String, tokenType: KeychainKeys) {
        let key = "\(tokenType.rawValue)_\(tenantId)"
        delete(key: key)
    }
    
    func deleteAllTokensForTenant(tenantId: String) {
        deleteTokenForTenant(tenantId: tenantId, tokenType: .accessToken)
        deleteTokenForTenant(tenantId: tenantId, tokenType: .refreshToken)
    }
    
    func saveLastActiveTenantId(_ tenantId: String) {
        do {
            try save(key: KeychainKeys.lastActiveTenantId.rawValue, value: tenantId)
        } catch {
            logger.warning("Failed to save last active tenant ID: \(error)")
        }
    }
    
    func getLastActiveTenantId() -> String? {
        return try? get(key: KeychainKeys.lastActiveTenantId.rawValue)
    }
    
    func deleteLastActiveTenantId() {
        delete(key: KeychainKeys.lastActiveTenantId.rawValue)
    }
}
