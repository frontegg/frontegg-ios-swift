//
//  File.swift
//  
//
//  Created by David Frontegg on 19/01/2023.
//

import Foundation
import CommonCrypto


enum OverrideUrlType {
    case HostedLoginCallback
    case SocialLoginRedirectToBrowser
    case SocialOauthPreLogin
    case SamlCallback
    case loginRoutes
    case internalRoutes
    case Unknown
}
func getOverrideUrlType (url: URL) -> OverrideUrlType {
    
    let urlStr = url.absoluteString
    
    if urlStr.starts(with: FronteggApp.shared.baseUrl) {
        
        switch(url.path) {
        case "/mobile/oauth/callback": return .HostedLoginCallback
        case "/auth/saml/callback":  return .SamlCallback
        default:
            if(url.path.hasPrefix("/frontegg/identity/resources/auth/v2/user/sso/default") &&
               url.path.hasSuffix("/prelogin")){
                return .SocialOauthPreLogin
            }
            if((URLConstants.successLoginRoutes.first { url.path.hasPrefix($0)}) != nil) {
                return .internalRoutes
            }
            if((URLConstants.loginRoutes.first { url.path.hasPrefix($0)}) != nil) {
                return .loginRoutes
            }
            
            return .internalRoutes
        }
    }
    
    if((URLConstants.oauthUrls.first { urlStr.hasPrefix($0)}) != nil) {
        return .SocialLoginRedirectToBrowser
    }
    
    return .Unknown
    
}

func getQueryItems(_ urlString: String) -> [String : String]? {
    var queryItems: [String : String] = [:]
    
    guard let components = getURLComonents(urlString) else {
        return nil
    }
    
    for item in components.queryItems ?? [] {
        queryItems[item.name] = item.value?.removingPercentEncoding
    }
    return queryItems
}

func getURLComonents(_ urlString: String?) -> NSURLComponents? {
    var components: NSURLComponents? = nil
    let linkUrl = URL(string: urlString?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? "")
    if let linkUrl = linkUrl {
        components = NSURLComponents(url: linkUrl, resolvingAgainstBaseURL: true)
    }
    return components
}
