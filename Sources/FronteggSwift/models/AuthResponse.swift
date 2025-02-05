//
//  AuthResponse.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//


public struct AuthResponse:Decodable, Equatable {
    
    public let token_type: String
    public let refresh_token: String
    public let access_token: String
    public let id_token: String
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.access_token == rhs.access_token && lhs.refresh_token == rhs.refresh_token && lhs.token_type == rhs.token_type && lhs.id_token == rhs.id_token
    }
}


