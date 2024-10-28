//
//  Passkeys.swift
//
//
//  Created by David Antoon on 27/10/2024.
//

import Foundation



struct GetPasskeysRequest: Codable {
    struct PublicKeyCredential: Codable {
        var timeout: Int
        var rpId: String
        var userVerification: String
        var challenge: String
    }
    var publicKey: PublicKeyCredential
}

struct CreatePasskeysRequest: Codable {
    struct PublicKeyCredential: Codable {
        struct Rp: Codable {
            let name: String
            let id: String
        }
        
        struct User: Codable {
            let id: [String: String] // Adjust as per actual data type
            let name: String
            let displayName: String
        }
        
        struct PubKeyCredParam: Codable {
            let type: String
            let alg: Int
        }
        
        struct AuthenticatorSelection: Codable {
            let userVerification: String
        }
        
        let rp: Rp
        let user: User
        let challenge: String
        let pubKeyCredParams: [PubKeyCredParam]
        let timeout: Int
        let attestation: String
        let authenticatorSelection: AuthenticatorSelection
        let excludeCredentials: [String] // Adjust as per actual data type
    }
    var publicKey: PublicKeyCredential
}
