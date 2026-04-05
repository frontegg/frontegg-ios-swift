//
//  FronteggAuth+SocialLoginCallback.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import AuthenticationServices

extension FronteggAuth {

    public func handleSocialLoginCallback(_ url: URL) -> URL? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // 1) Host must match Frontegg base URL host
        guard let allowedHost = URL(string: self.baseUrl)?.host else {
            return nil
        }

        guard comps.host == allowedHost else {
            return nil
        }

        let bundleId = currentAppBundleIdentifier()
        guard !bundleId.isEmpty else {
            return nil
        }

        let matchedCallbackRedirectUri = matchedGeneratedRedirectUri(
            url,
            baseUrl: self.baseUrl,
            bundleIdentifier: bundleId
        )

        // 2) Path: /oauth/account/redirect/ios/{bundleId}/{provider}
        let prefix = "/oauth/account/redirect/ios/"
        let path = comps.path
        guard path.hasPrefix(prefix) || matchedCallbackRedirectUri != nil else {
            return nil
        }

        // Helpers
        let items = comps.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if q("error") != nil || q("error_description") != nil {
            return nil
        }

        // Extract supported params
        var queryParams: [String: String] = [:]

        if let code = q("code"), !code.isEmpty {
            queryParams["code"] = code
        }

        if let idToken = q("id_token"), !idToken.isEmpty {
            queryParams["id_token"] = idToken
        }

        let redirectUri = matchedCallbackRedirectUri
            ?? generateRedirectUri(baseUrl: self.baseUrl, bundleIdentifier: bundleId)
        queryParams["redirectUri"] = redirectUri

        // Process state
        if let state = q("state"), !state.isEmpty {
            queryParams["state"] = SocialLoginUrlGenerator.canonicalizeSocialState(state)
        }

        if let s = WebAuthenticator.shared.session {
            s.cancel()
        }

        // Build query string safely
        var compsOut = URLComponents()
        compsOut.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }

        let finalUrl = URL(string: "\(self.baseUrl)/oauth/account/social/success?\(compsOut.query ?? "")")

        return finalUrl
    }
}
