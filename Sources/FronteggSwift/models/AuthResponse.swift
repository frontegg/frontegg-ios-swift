//
//  AuthResponse.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//


public struct AuthResponse:Decodable {
    
    public let token_type: String
    public let refresh_token: String
    public let access_token: String
    public let id_token: String
}
