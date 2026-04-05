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
        guard let value = item.value else {
            queryItems[item.name] = nil
            continue
        }

        queryItems[item.name] = value.removingPercentEncoding ?? value
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

func normalizedBasePath(_ path: String) -> String {
    guard !path.isEmpty, path != "/" else {
        return ""
    }

    var normalized = path
    if !normalized.hasPrefix("/") {
        normalized = "/\(normalized)"
    }

    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }

    return normalized
}

func currentAppBundleIdentifier() -> String {
    if !FronteggApp.shared.bundleIdentifier.isEmpty {
        return FronteggApp.shared.bundleIdentifier.lowercased()
    }

    return Bundle.main.bundleIdentifier?.lowercased() ?? ""
}

func routedAppPath(
    _ url: URL,
    baseUrl: String = FronteggApp.shared.baseUrl
) -> String {
    let actualPath = normalizedBasePath(url.path)

    guard
        let baseComponents = URLComponents(string: baseUrl),
        let baseHost = baseComponents.host?.lowercased(),
        let urlHost = url.host?.lowercased(),
        baseHost == urlHost
    else {
        return actualPath.isEmpty ? "/" : actualPath
    }

    let basePath = normalizedBasePath(baseComponents.path)
    guard !basePath.isEmpty else {
        return actualPath.isEmpty ? "/" : actualPath
    }

    if actualPath == basePath {
        return "/"
    }

    if actualPath.hasPrefix(basePath + "/") {
        let strippedPath = String(actualPath.dropFirst(basePath.count))
        return strippedPath.isEmpty ? "/" : strippedPath
    }

    return actualPath.isEmpty ? "/" : actualPath
}

func supportedGeneratedRedirectUris(
    baseUrl: String = FronteggApp.shared.baseUrl,
    bundleIdentifier: String = currentAppBundleIdentifier()
) -> [String] {
    guard
        let urlComponents = URLComponents(string: baseUrl),
        let host = urlComponents.host
    else {
        return []
    }

    let scheme = bundleIdentifier.lowercased()
    let basePath = normalizedBasePath(urlComponents.path)
    let callbackPath = "/ios/oauth/callback"
    let candidatePaths = basePath.isEmpty
        ? [callbackPath]
        : ["\(basePath)\(callbackPath)", callbackPath]

    var seen = Set<String>()
    var uris: [String] = []

    for path in candidatePaths {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path

        guard let uri = components.url?.absoluteString else {
            continue
        }

        if seen.insert(uri).inserted {
            uris.append(uri)
        }
    }

    return uris
}

func matchedGeneratedRedirectUri(
    _ url: URL,
    baseUrl: String = FronteggApp.shared.baseUrl,
    bundleIdentifier: String = currentAppBundleIdentifier()
) -> String? {
    guard
        let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let actualScheme = actual.scheme?.lowercased(),
        let actualHost = actual.host?.lowercased()
    else {
        return nil
    }

    let actualPath = normalizedBasePath(actual.path)

    for candidateUri in supportedGeneratedRedirectUris(
        baseUrl: baseUrl,
        bundleIdentifier: bundleIdentifier
    ) {
        guard let expected = URLComponents(string: candidateUri) else {
            continue
        }

        if actualScheme == expected.scheme?.lowercased(),
           actualHost == expected.host?.lowercased(),
           actualPath == normalizedBasePath(expected.path) {
            var matched = URLComponents()
            matched.scheme = actualScheme
            matched.host = actual.host
            matched.path = actualPath
            return matched.url?.absoluteString
        }
    }

    return nil
}

func matchedGeneratedRedirectUri(
    _ redirectUri: String,
    baseUrl: String = FronteggApp.shared.baseUrl,
    bundleIdentifier: String = currentAppBundleIdentifier()
) -> String? {
    guard let url = URL(string: redirectUri) else {
        return nil
    }

    return matchedGeneratedRedirectUri(
        url,
        baseUrl: baseUrl,
        bundleIdentifier: bundleIdentifier
    )
}

func generateRedirectUri(
    baseUrl: String,
    bundleIdentifier: String
) -> String {
    guard let redirectUri = supportedGeneratedRedirectUris(
        baseUrl: baseUrl,
        bundleIdentifier: bundleIdentifier
    ).first else {
        print("Failed to generate redirect uri, baseUrl: \(baseUrl)")
        exit(1)
    }

    return redirectUri
}

public func generateRedirectUri() -> String {

    let baseUrl = FronteggApp.shared.baseUrl
    let bundleIdentifier = currentAppBundleIdentifier()

    let redirectUri = generateRedirectUri(
        baseUrl: baseUrl,
        bundleIdentifier: bundleIdentifier
    )
    let urlComponents = URLComponents(string: baseUrl)
    let path = normalizedBasePath(urlComponents?.path ?? "")
    let supportedRedirectUris = supportedGeneratedRedirectUris(
        baseUrl: baseUrl,
        bundleIdentifier: bundleIdentifier
    )
    let logger = getLogger("UrlHelper")
    logger.info("🔵 [Social Login Debug] Generated redirect URI: \(redirectUri)")
    logger.info("🔵 [Social Login Debug]   - Base URL: \(baseUrl)")
    logger.info("🔵 [Social Login Debug]   - Bundle ID: \(bundleIdentifier)")
    logger.info("🔵 [Social Login Debug]   - URL host: \(urlComponents?.host ?? "nil")")
    logger.info("🔵 [Social Login Debug]   - URL path: \(path)")
    if supportedRedirectUris.count > 1 {
        logger.info("🔵 [Social Login Debug]   - Supported callback aliases: \(supportedRedirectUris.joined(separator: ", "))")
    }
    
    return redirectUri
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
    let routedPath = routedAppPath(url)
    
    if urlStr.starts(with: FronteggApp.shared.baseUrl) {
        
        if(isSocialLoginPath(routedPath)){
            return .SocialOauthPreLogin
        }
        
        if((URLConstants.successLoginRoutes.first { routedPath.hasPrefix($0)}) != nil) {
            return .loginRoutes
        }
        if((URLConstants.loginRoutes.first { routedPath.hasPrefix($0)}) != nil) {
            return .loginRoutes
        }
        
        return .internalRoutes
    }
    
    if matchedGeneratedRedirectUri(url) != nil {
        return .HostedLoginCallback
    }
    return .Unknown
    
}
