//
//  CredentialAssertion.swift
//  
//
//  Created by David Frontegg on 15/09/2023.
//

import Foundation



public struct PKCredentialRP: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    public var id: String
    public var name: String
}


public struct PKCredentialUser: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    public var id: String
    public var name: String
    public var displayName: String
}

public struct PKPublicKeyCreds: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    public var type: String
    public var alg: Int
}



public struct PKAuthenticatorSelection: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    public var userVerification: String
}


public struct PKCredentialAssertionOption: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    public var rp: PKCredentialRP
    public var user: PKCredentialUser
    public var challenge:String
    public var pubKeyCredParams: [PKPublicKeyCreds]
    public var timeout: Int
    public var attestation: String?
    public var authenticatorSelection: PKAuthenticatorSelection?

}

public struct PKCredentialAssertion: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    public var options: PKCredentialAssertionOption
}
