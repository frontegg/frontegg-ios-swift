//
//  Constants.swift
//  
//
//  Created by David Frontegg on 21/12/2022.
//

import Foundation


struct URLConstants {
    
    static let oauthUrls = [
        "https://www.facebook.com",
        "https://accounts.google.com",
        "https://github.com/login/oauth/authorize",
        "https://login.microsoftonline.com",
        "https://slack.com/openid/connect/authorize",
        "https://appleid.apple.com",
        "https://www.linkedin.com/oauth/"
    ]
    
    static let successLoginRoutes:[String] = [
        "/oauth/account/social/success",
    ]
    static let loginRoutes:[String] = [
        "/oauth/account/",
    ]
 
    static func generateRedirectUri(_ baseUrl:String) -> String {
        return "\(baseUrl)/mobile/oauth/callback"
    }
    
    static func generateSocialLoginRedirectUri(_ baseUrl:String) -> String {
        return "\(baseUrl)/oauth/account/social/success"
    }
}

struct SchemeConstants {
    static let webAuthenticationCallbackScheme = "https"
}
