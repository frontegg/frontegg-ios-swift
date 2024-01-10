//
//  File.swift
//  
//
//  Created by David Frontegg on 13/09/2023.
//

import Foundation

struct URLConstants {
    
    
    static let successLoginRoutes:[String] = [
        "/oauth/account/social/success",
    ]
    static let loginRoutes:[String] = [
        "/oauth/account/",
    ]
 
    static func generateSocialLoginRedirectUri(_ baseUrl:String) -> String {
        return "\(baseUrl)/oauth/account/social/success"
    }
}
