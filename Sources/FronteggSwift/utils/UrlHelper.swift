//
//  UrlHelper.swift
//  
//
//  Created by David Frontegg on 22/06/2023.
//

import Foundation
import CommonCrypto

enum CallbackType {
    case HostedLoginCallback
    case MagicLink
    case Unknown
}
func getCallbackType (_ callbackUrl: URL?) -> CallbackType {
    
    guard let url = callbackUrl else {
        return .Unknown
    }
    
    switch(url.path) {
    case "/oauth/callback": return .HostedLoginCallback
    case "/oauth/magic-link/callback": return .MagicLink
    default:
        return .Unknown
    }
    
    
}

public func getQueryItems(_ urlString: String) -> [String : String]? {
    var queryItems: [String : String] = [:]
    
    guard let components = getURLComonents(urlString) else {
        return nil
    }
    
    for item in components.queryItems ?? [] {
        queryItems[item.name] = item.value?.removingPercentEncoding
    }
    return queryItems
}

public func getURLComonents(_ urlString: String?) -> NSURLComponents? {
    var components: NSURLComponents? = nil
    let linkUrl = URL(string: urlString?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? "")
    if let linkUrl = linkUrl {
        components = NSURLComponents(url: linkUrl, resolvingAgainstBaseURL: true)
    }
    return components
}

public func generateRedirectUri() -> String {

    let baseUrl = FronteggApp.shared.baseUrl
    let bundleIdentifier = FronteggApp.shared.bundleIdentifier
    
    // return "com.frontegg.demo://auth.davidantoon.me/ios/oauth/callback
    
    guard let urlComponents = URLComponents(string: baseUrl) else {
        
        print("Failed to generate redirect uri, baseUrl: \(baseUrl)")
        exit(1)
    }
    
    return "\(bundleIdentifier.lowercased())://\(urlComponents.host!)/ios/oauth/callback"
    
}


enum OverrideUrlType {
    case HostedLoginCallback
    case SocialOauthPreLogin
    case loginRoutes
    case internalRoutes
    case Unknown
}


func isSocialLoginPath(_ string: String) -> Bool {
    let patterns = [
        "^/frontegg/identity/resources/auth/[^/]+/user/sso/default/[^/]+/prelogin$",
        "^/identity/resources/auth/[^/]+/user/sso/default/[^/]+/prelogin$"
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))
            if !matches.isEmpty {
                return true
            }
        }
    }
    
    return false
}
func getOverrideUrlType (url: URL) -> OverrideUrlType {
    
    let urlStr = url.absoluteString
    
    if urlStr.starts(with: FronteggApp.shared.baseUrl) {
        
        if(isSocialLoginPath(url.path)){
            return .SocialOauthPreLogin
        }
        if((URLConstants.successLoginRoutes.first { url.path.hasPrefix($0)}) != nil) {
            return .loginRoutes
        }
        if((URLConstants.loginRoutes.first { url.path.hasPrefix($0)}) != nil) {
            return .loginRoutes
        }
        
        return .internalRoutes
    }
    
    if(url.absoluteString.starts(with: generateRedirectUri())){
        return .HostedLoginCallback
    }
    return .Unknown
    
}
