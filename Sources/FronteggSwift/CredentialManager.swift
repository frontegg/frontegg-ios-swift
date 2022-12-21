//
//  FronteggCredentialManager.swift
//  poc
//
//  Created by David Frontegg on 16/11/2022.
//

import Foundation

class CredentialManager {
    
    enum KeychainError: Error {
        case duplicateEntry;
        case valueDataIsNil;
        case unknown(OSStatus);
    }
    
    
    let serviceKey: String?
    
    init(serviceKey: String?) {
        self.serviceKey = serviceKey;
    }
    
    func save(key:String, value: String) throws {
        print("Saving Frontegg session in keyhcain")
        
        if let valueData = value.data(using: .utf8) {
            let query = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: serviceKey ?? "frontegg",
                kSecAttrAccount: key,
                kSecValueData: valueData
            ] as CFDictionary
            
            let status = SecItemAdd(query, nil)
            
            if status == errSecDuplicateItem {
                print("Updating exising Frontegg session")
                let updateQuery = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: serviceKey ?? "frontegg",
                    kSecAttrAccount: key,
                ] as CFDictionary
                
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
            
            print("Frontegg session saved in keyhcain")
        } else {
            throw KeychainError.valueDataIsNil
        }
    }
    
    func get(key:String) throws -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceKey ?? "frontegg",
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary
        
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        
        if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
        
        if let resultData = result as? Data {
            return String(decoding: resultData, as: UTF8.self)
        }
        return nil
    }
    
    func clear() {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceKey ?? "frontegg"
        ] as CFDictionary
        let status = SecItemDelete(query)
        
        if status != errSecSuccess {
            print("Failed to logout from Frontegg Services, error \(status)")
        }
    }
}
