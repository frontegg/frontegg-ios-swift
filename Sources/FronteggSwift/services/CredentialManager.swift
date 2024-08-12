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
            logger.error("Unknown error occured while trying to retrieve the key: \(key) from keyhcain")
            throw KeychainError.unknown(status)
        }
        
        if let resultData = result as? Data {
            logger.trace("Value found in keychain for key: \(key)")
            return String(decoding: resultData, as: UTF8.self)
        }
        
        logger.trace("Value not found in keychain for key: \(key), returned nil")
        return nil
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
}
