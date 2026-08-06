//
//  FronteggAuth+SocialLoginCallback.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import AuthenticationServices

/// Why a social-login callback could not be turned into a `/oauth/account/social/success` URL.
///
/// `handleSocialLoginCallback` used to return a bare `nil` from seven different
/// places. In the field that collapsed into a single symptom — a misleading
/// "Failed to get extract code" toast ~1.3s later — with nothing in the log to say
/// which precondition had rejected the callback. FR-26132 was reproduced twice
/// without the cause being identifiable from the logs for exactly this reason.
public enum SocialLoginCallbackRejection: String, Error {
    /// The callback URL could not be decomposed at all.
    case malformedCallbackUrl
    /// `baseUrl` is empty or unparsable — the SDK is misconfigured or was used
    /// before initialization completed.
    case unusableBaseUrl
    /// The callback arrived on a host other than the configured Frontegg host.
    case hostMismatch
    /// No bundle identifier is available, so no redirect URI can be generated.
    case emptyBundleIdentifier
    /// The path is neither the hosted redirect prefix nor any redirect URI this
    /// SDK would have generated.
    case unrecognisedCallbackPath
    /// The identity provider reported an error in the callback.
    case providerReportedError
    /// The success URL could not be constructed from the collected parameters.
    case successUrlNotConstructible
}

extension FronteggAuth {

    public func handleSocialLoginCallback(_ url: URL) -> URL? {
        switch resolveSocialLoginCallback(url) {
        case .success(let finalUrl):
            return finalUrl
        case .failure(let rejection):
            // Named so the next field report identifies the failing precondition
            // directly, instead of requiring the guards to be eliminated one by one.
            logger.error("Social login callback rejected: \(rejection.rawValue). Callback path: \(url.path)")
            return nil
        }
    }

    /// The parsing itself, with every rejection reported as a value so each branch
    /// is observable in logs and reachable from tests.
    internal func resolveSocialLoginCallback(
        _ url: URL
    ) -> Result<URL, SocialLoginCallbackRejection> {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.malformedCallbackUrl)
        }

        // 1) Host must match Frontegg base URL host
        guard let allowedHost = URL(string: self.baseUrl)?.host else {
            return .failure(.unusableBaseUrl)
        }

        guard comps.host == allowedHost else {
            return .failure(.hostMismatch)
        }

        let bundleId = currentAppBundleIdentifier()
        guard !bundleId.isEmpty else {
            return .failure(.emptyBundleIdentifier)
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
            return .failure(.unrecognisedCallbackPath)
        }

        // Helpers
        let items = comps.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if q("error") != nil || q("error_description") != nil {
            return .failure(.providerReportedError)
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

        // Build the success URL through URLComponents rather than by interpolating
        // a string into `URL(string:)`.
        //
        // `URLComponents.query` does not percent-encode every character that is
        // illegal in a query component: the identity provider returns `state` as
        // raw JSON, and `{`, `"` and `}` come back intact. Feeding that to
        // `URL(string:)` relies on Apple's compatibility repair, which is not
        // guaranteed. Assigning `queryItems` and reading `.url` encodes them
        // properly and never re-parses the assembled string.
        guard var successComponents = URLComponents(string: self.baseUrl) else {
            return .failure(.unusableBaseUrl)
        }

        // Preserve any path already on the base URL, matching the previous
        // string-concatenation behaviour for tenants served from a sub-path.
        let basePath = successComponents.path.hasSuffix("/")
            ? String(successComponents.path.dropLast())
            : successComponents.path
        successComponents.path = "\(basePath)/oauth/account/social/success"
        successComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let finalUrl = successComponents.url else {
            return .failure(.successUrlNotConstructible)
        }

        return .success(finalUrl)
    }
}
