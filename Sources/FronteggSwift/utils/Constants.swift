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
    
}

struct SchemeConstants {
    static let webAuthenticationCallbackScheme = "frontegg-sso"
}


struct SocialLoginConstansts {
    
static let oauthUrls = ["https://www.facebook.com",
        "https://accounts.google.com",
        "https://github.com/login/oauth/authorize",
        "https://login.microsoftonline.com",
        "https://slack.com/openid/connect/authorize",
        "https://appleid.apple.com"]
}


