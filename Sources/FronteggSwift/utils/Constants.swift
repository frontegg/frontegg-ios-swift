//
//  Constants.swift
//  
//
//  Created by David Frontegg on 21/12/2022.
//

import Foundation


struct URLConstants {
    
    static let authenticateUrl = URL(string: "frontegg://oauth/authenticate")!
    static let exchangeTokenUrl = URL(string: "frontegg://oauth/callback")!
    static let exchangeTokenSuccessUrl = URL(string: "frontegg://oauth/success/callback")!
    
    
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
    
}

struct SchemeConstants {
    static let webAuthenticationCallbackScheme = "https"
}
