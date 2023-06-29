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
    let config = try! PlistHelper.fronteggConfig()
    let baseUrl = config.baseUrl
    let bundleIdentifier = config.bundleIdentifier
    
    // return "com.frontegg.demo://auth.davidantoon.me/ios/oauth/callback
    
    guard let urlComponents = URLComponents(string: baseUrl) else {
        
        print("Failed to generate redirect uri, baseUrl: \(baseUrl)")
        exit(1)
    }
    
        return "\(bundleIdentifier)://\(urlComponents.host!)/ios/oauth/callback"
    
}
