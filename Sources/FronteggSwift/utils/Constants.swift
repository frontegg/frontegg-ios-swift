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

struct StepUpConstants {
    static let ACR_VALUE = "http://schemas.openid.net/pape/policies/2007/06/multi-factor"
    static let AMR_MFA_VALUE = "mfa"
    static let AMR_ADDITIONAL_VALUE = ["otp", "sms", "hwk"]
    static let STEP_UP_MAX_AGE_PARAM_NAME = "maxAge"
}
