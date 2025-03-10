//
//  Passkeys.swift
//
//
//  Created by David Antoon on 27/10/2024.
//

import Foundation



struct GetPasskeysRequest: Codable, Equatable {
    struct PublicKeyCredential: Codable, Equatable {
        var timeout: Int
        var rpId: String
        var userVerification: String
        var challenge: String
        
        static func == (lhs: PublicKeyCredential, rhs: PublicKeyCredential) -> Bool {
            return lhs.timeout == rhs.timeout &&
                lhs.rpId == rhs.rpId &&
                lhs.userVerification == rhs.userVerification &&
                lhs.challenge == rhs.challenge
        }
    }
    
    var publicKey: PublicKeyCredential
    
    static func == (lhs: GetPasskeysRequest, rhs: GetPasskeysRequest) -> Bool {
        return lhs.publicKey == rhs.publicKey
    }
}

struct CreatePasskeysRequest: Codable, Equatable {
    struct PublicKeyCredential: Codable, Equatable {
        
        struct Rp: Codable, Equatable {
            let name: String
            let id: String
            
            static func == (lhs: Rp, rhs: Rp) -> Bool {
                return lhs.name == rhs.name && lhs.id == rhs.id
            }
        }
        
        struct User: Codable, Equatable {
            let id: [String: String]
            let name: String
            let displayName: String
            
            static func == (lhs: User, rhs: User) -> Bool {
                return lhs.id == rhs.id && lhs.name == rhs.name && lhs.displayName == rhs.displayName
            }
        }
        
        struct PubKeyCredParam: Codable, Equatable {
            let type: String
            let alg: Int
            
            static func == (lhs: PubKeyCredParam, rhs: PubKeyCredParam) -> Bool {
                return lhs.type == rhs.type && lhs.alg == rhs.alg
            }
        }
        
        struct AuthenticatorSelection: Codable, Equatable {
            let userVerification: String
            
            static func == (lhs: AuthenticatorSelection, rhs: AuthenticatorSelection) -> Bool {
                return lhs.userVerification == rhs.userVerification
            }
        }
        
        let rp: Rp
        let user: User
        let challenge: String
        let pubKeyCredParams: [PubKeyCredParam]
        let timeout: Int
        let attestation: String
        let authenticatorSelection: AuthenticatorSelection
        let excludeCredentials: [String] // Adjust as per actual data type
        
        static func == (lhs: PublicKeyCredential, rhs: PublicKeyCredential) -> Bool {
            return lhs.rp == rhs.rp &&
                lhs.user == rhs.user &&
                lhs.challenge == rhs.challenge &&
                lhs.pubKeyCredParams == rhs.pubKeyCredParams &&
                lhs.timeout == rhs.timeout &&
                lhs.attestation == rhs.attestation &&
                lhs.authenticatorSelection == rhs.authenticatorSelection &&
                lhs.excludeCredentials == rhs.excludeCredentials
        }
    }
    
    var publicKey: PublicKeyCredential
    
    static func == (lhs: CreatePasskeysRequest, rhs: CreatePasskeysRequest) -> Bool {
        return lhs.publicKey == rhs.publicKey
    }
}
