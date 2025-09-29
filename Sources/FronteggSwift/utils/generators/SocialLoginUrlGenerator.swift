//
//  SocialLoginUrlGenerator.swift
//  FronteggSwift
//
//  Created by David Antoon on 08/09/2025.
//
//  Refactored to use the existing SocialLoginConfig data model.
//  Updated to support custom social logins.
//

import Foundation
import CryptoKit


/// A data structure to hold all provider-specific OAuth configurations that are not fetched from the API.
internal struct ProviderDetails {
    let authorizeEndpoint: String
    let defaultScopes: [String]
    let responseType: String
    let responseMode: String?
    let requiresPKCE: Bool
    let promptValueForConsent: String?

    private static let providerDetails: [SocialLoginProvider: ProviderDetails] = [
        .facebook: .init(
            authorizeEndpoint: "https://www.facebook.com/v10.0/dialog/oauth",
            defaultScopes: ["email"],
            responseType: "code", responseMode: nil, requiresPKCE: false,
            promptValueForConsent: "reauthenticate"
        ),
        .google: .init(
            authorizeEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
            defaultScopes: ["https://www.googleapis.com/auth/userinfo.profile", "https://www.googleapis.com/auth/userinfo.email"],
            responseType: "code", responseMode: nil, requiresPKCE: true,
            promptValueForConsent: "select_account"
        ),
        .github: .init(
            authorizeEndpoint: "https://github.com/login/oauth/authorize",
            defaultScopes: ["read:user", "user:email"],
            responseType: "code", responseMode: nil, requiresPKCE: false,
            promptValueForConsent: "consent"
        ),
        .microsoft: .init(
            authorizeEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            defaultScopes: ["openid", "profile", "email"],
            responseType: "code", responseMode: "query", requiresPKCE: true,
            promptValueForConsent: "select_account"
        ),
        .slack: .init(
            authorizeEndpoint: "https://slack.com/openid/connect/authorize",
            defaultScopes: ["openid", "profile", "email"],
            responseType: "code", responseMode: nil, requiresPKCE: false,
            promptValueForConsent: nil
        ),
        .apple: .init(
            authorizeEndpoint: "https://appleid.apple.com/auth/authorize",
            defaultScopes: ["openid", "name", "email"],
            responseType: "code", responseMode: "form_post", requiresPKCE: false,
            promptValueForConsent: nil
        ),
        .linkedin: .init(
            authorizeEndpoint: "https://www.linkedin.com/oauth/v2/authorization",
            defaultScopes: ["r_liteprofile", "r_emailaddress"],
            responseType: "code", responseMode: nil, requiresPKCE: false,
            promptValueForConsent: nil
        )
    ]
    
    static func `for`(provider: SocialLoginProvider) throws -> ProviderDetails {
        guard let details = providerDetails[provider] else {
            throw FronteggError.configError(.failedToGenerateAuthorizeURL)
        }
        return details
    }
    
    /// Finds a standard provider configuration that matches the given authorization URL.
    /// - Parameter authorizationUrl: The endpoint URL to search for.
    /// - Returns: A tuple containing the matched provider and its details, or `nil` if not found.
    static func find(by authorizationUrl: String) -> (provider: SocialLoginProvider, details: ProviderDetails)? {
        return providerDetails.first { (_, details) in
            return details.authorizeEndpoint == authorizationUrl
        }.map { (key, value) in
            return (provider: key, details: value)
        }
    }
}

// MARK: - Public API

public final class SocialLoginUrlGenerator {
    public static let shared = SocialLoginUrlGenerator()
    
    private var socialLoginConfig: SocialLoginConfig?
    private var customSocialLoginConfigs: [CustomSocialLoginProviderConfig]?
    private let logger = getLogger("SocialLoginUrlGenerator")
    
    
    /// Generates an authorization URL for a standard social login provider.
    public func authorizeURL(
        for provider: SocialLoginProvider,
        action: SocialLoginAction = .login
    ) async throws -> URL? {
        guard let option = await configuration(for: provider), option.active else {
            logger.debug("Provider inactive or config missing: \(provider.rawValue)")
            return nil
        }
        
        if let authURLString = option.authorizationUrl {
            // Check if this is a legacy flow (relative URL starting with /identity/resources/auth/v2/user/sso/default/)
            if authURLString.hasPrefix("/identity/resources/auth/v2/user/sso/default/") {
                logger.debug("Detected legacy social login flow for provider: \(provider.rawValue)")
                return nil // Signal to use legacy flow
            }
            
            if let url = URL(string: authURLString) {
                guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
                if let prompt = provider.details.promptValueForConsent {
                    comps.addOrReplaceQueryItem(name: "prompt", value: prompt)
                }
                return comps.url
            }
        }
        
        return try await buildProviderURL(provider: provider, option: option, action: action)
    }
    
    /// Generates a legacy social login URL for providers that use the old flow.
    public func legacyAuthorizeURL(
        for provider: SocialLoginProvider,
        action: SocialLoginAction = .login
    ) async throws -> String? {
        guard let option = await configuration(for: provider), option.active else {
            logger.debug("Provider inactive or config missing: \(provider.rawValue)")
            return nil
        }
        
        guard let authURLString = option.authorizationUrl,
              authURLString.hasPrefix("/identity/resources/auth/v2/user/sso/default/") else {
            logger.debug("Not a legacy flow for provider: \(provider.rawValue)")
            return nil
        }
        
        // Convert relative URL to absolute
        let fullURL = "\(FronteggAuth.shared.baseUrl)\(authURLString)"
        
        // Add prompt parameter if needed
        guard var urlComponents = URLComponents(string: fullURL) else {
            logger.error("Failed to parse legacy URL: \(fullURL)")
            return fullURL
        }
        
        // Add prompt parameter for legacy flow
        if let prompt = provider.details.promptValueForConsent {
            urlComponents.addOrReplaceQueryItem(name: "prompt", value: prompt)
        }
        
        let finalURL = urlComponents.url?.absoluteString ?? fullURL
        logger.debug("Generated legacy URL for \(provider.rawValue): \(finalURL)")
        return finalURL
    }

    /// Generates an authorization URL for a custom social login provider.
    public func authorizeURL(
        forCustomProvider provider: String,
        action: SocialLoginAction = .login
    ) async throws -> URL? {
        if self.customSocialLoginConfigs == nil {
            await reloadConfigs()
        }

        guard let providerConfig = self.customSocialLoginConfigs?.first(where: { $0.id == provider }) else {
            logger.warning("Custom social login provider with name '\(provider)' not found or not active.")
            return nil
        }

        return try self.buildCustomProviderURL(provider: providerConfig, action: action)
    }
    
    public func reloadConfigs() async {
        logger.info("Reloading social login configurations...")
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    self.socialLoginConfig = try await FronteggAuth.shared.api.getSocialLoginConfig()
                    self.logger.info("Successfully loaded standard social login configs")
                } catch {
                    self.logger.error("Failed to load standard SSO configs: \(error)")
                }
            }
            
            group.addTask {
                do {
                    let response = try await FronteggAuth.shared.api.getCustomSocialLoginConfig()
                    self.customSocialLoginConfigs = response.providers.filter { $0.active }
                    self.logger.info("Successfully loaded custom social login configs. Found \(self.customSocialLoginConfigs?.count ?? 0) active providers.")
                } catch {
                    self.logger.error("Failed to load custom SSO configs: \(error)")
                }
            }
        }
    }
    
    public func configuration(for provider: SocialLoginProvider) async -> SocialLoginOption? {
        if self.socialLoginConfig == nil {
            await reloadConfigs()
        }
        guard let config = self.socialLoginConfig else {
            return nil
        }
        
        switch provider {
        case .facebook: return config.facebook
        case .google: return config.google
        case .microsoft: return config.microsoft
        case .github: return config.github
        case .slack: return config.slack
        case .apple: return config.apple
        case .linkedin: return config.linkedin
        }
    }
}

// MARK: - Provider URL Builder

private extension SocialLoginUrlGenerator {
    
    func buildProviderURL(
        provider: SocialLoginProvider,
        option: SocialLoginOption,
        action: SocialLoginAction
    ) async throws -> URL? {
        let details = provider.details
        guard var comps = URLComponents(string: details.authorizeEndpoint) else { return nil }
        
        var queryItems: [URLQueryItem] = []
        
        if let clientId = option.clientId {
            queryItems.append(URLQueryItem(name: "client_id", value: clientId))
        }
        
        queryItems.append(URLQueryItem(name: "response_type", value: details.responseType))
        if let responseMode = details.responseMode {
            queryItems.append(URLQueryItem(name: "response_mode", value: responseMode))
        }

        let redirectUri = defaultSocialLoginRedirectUri()
        let state = try Self.createState(provider: provider.rawValue,
                                         appId: FronteggAuth.shared.applicationId,
                                         action: action)
        
        queryItems.append(contentsOf: [
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "state", value: state)
        ])
        
        let baseScopes = (provider == .linkedin && !option.additionalScopes.isEmpty) ? [] : details.defaultScopes
        let allScopes = (baseScopes + option.additionalScopes).joined(separator: " ")
        
        if !allScopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: allScopes))
        }
        
        if details.requiresPKCE && FronteggAuth.shared.featureFlags.isOn("identity-sso-force-pkce") {
            let verifier: String = try await Self.getCodeVerifierFromWebview()
            queryItems.append(contentsOf: [
                URLQueryItem(name: "code_challenge", value: verifier.s256CodeChallenge()),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ])
        }
        
        if let prompt = details.promptValueForConsent {
            let promptKey = (provider == .facebook) ? "auth_type" : "prompt"
            queryItems.append(URLQueryItem(name: promptKey, value: prompt))
        }

        if provider == .google || provider == .linkedin {
            queryItems.append(URLQueryItem(name: "include_granted_scopes", value: "true"))
        }

        comps.queryItems = queryItems
        return comps.url
    }
    
    func buildCustomProviderURL(
        provider: CustomSocialLoginProviderConfig,
        action: SocialLoginAction
    ) throws -> URL? {
        // This will correctly parse the URL and its existing query items.
        guard var comps = URLComponents(string: provider.authorizationUrl) else {
            logger.error("Invalid authorizationUrl for custom provider \(provider.displayName)")
            return nil
        }
        
        let state = try Self.createState(
            provider: provider.displayName,
            appId: FronteggAuth.shared.applicationId,
            action: action
        )
        
        // Use the helper to add/replace our required params, preserving any others.
        comps.addOrReplaceQueryItem(name: "client_id", value: provider.clientId)
        comps.addOrReplaceQueryItem(name: "scope", value: provider.scopes)
        comps.addOrReplaceQueryItem(name: "redirect_uri", value: provider.redirectUrl)
        comps.addOrReplaceQueryItem(name: "response_type", value: "code")
        comps.addOrReplaceQueryItem(name: "state", value: state)
        
        
        // Create a clean base URL (scheme + host + path) for matching.
        let baseUrlString = "\(comps.scheme ?? "")://\(comps.host ?? "")\(comps.path)"
        
        // Match against the base URL to see if we should add a consent prompt.
        if let (matchedProvider, matchedDetails) = ProviderDetails.find(by: baseUrlString),
           let promptValue = matchedDetails.promptValueForConsent {
            
            let promptKey = (matchedProvider == .facebook) ? "auth_type" : "prompt"
            comps.addOrReplaceQueryItem(name: promptKey, value: promptValue)
            logger.trace("Adding consent prompt for custom provider matching \(matchedProvider.rawValue)")
        }
        
        let url = comps.url
        logger.trace("Built URL for custom provider \(provider.displayName): \(url?.absoluteString ?? "nil")")
        return url
    }
}

// MARK: - Helpers & Extensions

public extension SocialLoginUrlGenerator {
    
    struct OAuthState: Codable {
        let provider: String
        let appId: String
        let action: String
        let bundleId: String
        let platform: String
    }
    
    static func createState(provider: SocialLoginProvider, appId: String?, action: SocialLoginAction) throws -> String {
        return try createState(provider: provider.rawValue, appId: appId, action: action)
    }

    static func createState(provider: String, appId: String?, action: SocialLoginAction) throws -> String {
        let stateObject = OAuthState(
            provider: provider,
            appId: appId ?? "",
            action: action.rawValue,
            bundleId: FronteggApp.shared.bundleIdentifier,
            platform: "ios"
        )
        let data = try JSONEncoder().encode(stateObject)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func getCodeVerifierFromWebview() async throws -> String {
        guard let webview = FronteggAuth.shared.webview else {
            throw FronteggError.configError(.failedToGenerateAuthorizeURL)
        }
        
        guard let codeVerifier = try? await webview.evaluateJavaScript("window.localStorage['FRONTEGG_CODE_VERIFIER']") as? String else {
            throw FronteggError.configError(.failedToGenerateAuthorizeURL)
        }
        return codeVerifier
    }

    func defaultSocialLoginRedirectUri() -> String {
        let base = FronteggAuth.shared.baseUrl
        let baseRedirectUri = "\(base)/oauth/account/social/success"
        
        return baseRedirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? baseRedirectUri
    }
    
    func defaultRedirectUri() -> String {
        let base = FronteggAuth.shared.baseUrl
        let bundleId = FronteggApp.shared.bundleIdentifier
        let baseRedirectUri = "\(base)/oauth/account/redirect/ios/\(bundleId)"
        
        return baseRedirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? baseRedirectUri
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    func s256CodeChallenge() -> String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        let b64 = Data(hash).base64EncodedString()
        let b64url = b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return b64url
    }
}

private extension URLComponents {
    mutating func addOrReplaceQueryItem(name: String, value: String?) {
        var queryItems = self.queryItems ?? []
        // Remove existing item with the same name, if any.
        if let index = queryItems.firstIndex(where: { $0.name == name }) {
            queryItems.remove(at: index)
        }
        // Add the new item.
        queryItems.append(URLQueryItem(name: name, value: value))
        self.queryItems = queryItems
    }
}
