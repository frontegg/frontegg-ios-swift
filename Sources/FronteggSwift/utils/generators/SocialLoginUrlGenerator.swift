//
//  SocialLoginUrlGenerator.swift
//  FronteggSwift
//
//  Created by David Antoon on 08/09/2025.
//
//  Refactored to use the existing SocialLoginConfig data model.
//

import Foundation
import CryptoKit

// MARK: - Provider Definition & Details

public enum SocialLoginProvider: String, Codable, CaseIterable {
    case facebook = "facebook"
    case google = "google"
    case microsoft = "microsoft"
    case github = "github"
    case slack = "slack"
    case apple = "apple"
    case linkedin = "linkedin"
    
    // Internal helper to access static, provider-specific details.
    internal var details: ProviderDetails { ProviderDetails.for(provider: self) }
}


public enum SocialLoginAction:String, Codable, CaseIterable {
    case login = "login"
    case signUp = "signUp"
    
}

/// A data structure to hold all provider-specific OAuth configurations that are not fetched from the API.
internal struct ProviderDetails {
    let authorizeEndpoint: String
    let defaultScopes: [String]
    let responseType: String
    let responseMode: String?
    let requiresPKCE: Bool
    let promptValueForConsent: String?

    /// Centralized, data-driven configuration eliminates repetitive switch statements.
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
    
    static func `for`(provider: SocialLoginProvider) -> ProviderDetails {
        guard let details = providerDetails[provider] else {
            fatalError("ProviderDetails not configured for \(provider.rawValue)")
        }
        return details
    }
}

// MARK: - Public API

public final class SocialLoginUrlGenerator {
    public static let shared = SocialLoginUrlGenerator()
    
    // Use the SocialLoginConfig struct to store configurations.
    private var socialLoginConfig: SocialLoginConfig?
    private let logger = getLogger("SocialLoginUrlGenerator")
    
    
    public func authorizeURL(
        for provider: SocialLoginProvider,
        action: SocialLoginAction = .login
    ) async throws -> URL? {
        guard let option = await configuration(for: provider), option.active else {
            logger.debug("Provider inactive or config missing: \(provider.rawValue)")
            return nil
        }
        
        // Handle tenant-specific authorization URL if available.
        if let authURLString = option.authorizationUrl, let url = URL(string: authURLString) {
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            if let prompt = provider.details.promptValueForConsent {
                comps.addOrReplaceQueryItem(name: "prompt", value: prompt)
            }
            return comps.url
        }
        
        return try await buildProviderURL(provider: provider, option: option, action: action)
    }
    
    @discardableResult
    public func reloadConfigs() async -> Bool {
        do {
            // Fetch the configuration using the existing API method.
            let config = try await FronteggAuth.shared.api.getSocialLoginConfig()
            self.socialLoginConfig = config
            self.logger.info("Loaded social login configs")
            return true
        } catch {
            self.logger.error("Failed to load SSO configs: \(error)")
            return false
        }
    }
    
    /// Retrieves the configuration for a specific provider from the stored `SocialLoginConfig`.
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
        
        // 1. Client ID
        if let clientId = option.clientId {
            queryItems.append(URLQueryItem(name: "client_id", value: clientId))
        }
        
        // 2. Response Type & Mode
        queryItems.append(URLQueryItem(name: "response_type", value: details.responseType))
        if let responseMode = details.responseMode {
            queryItems.append(URLQueryItem(name: "response_mode", value: responseMode))
        }

        // 3. Redirect URI and State
        let redirectUri = defaultSocialLoginRedirectUri()
        let state = try Self.createState(provider: provider,
                                     appId: FronteggAuth.shared.applicationId,
                                     action: action)
        
        queryItems.append(contentsOf: [
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "state", value: state)
        ])
        
        // 4. Scopes
        let baseScopes = (provider == .linkedin && !option.additionalScopes.isEmpty) ? [] : details.defaultScopes
        let allScopes = (baseScopes + option.additionalScopes).joined(separator: " ")
        
        if !allScopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: allScopes))
        }
        
        // 5. PKCE Challenge
        if details.requiresPKCE && FronteggAuth.shared.featureFlags.isOn("identity-sso-force-pkce") {
            let verifier: String = try await Self.getCodeVerifierFromWebview()
            queryItems.append(contentsOf: [
                URLQueryItem(name: "code_challenge", value: verifier.s256CodeChallenge()),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ])
        }
        
        // 6. Prompt for consent
        if let prompt = details.promptValueForConsent {
            let promptKey = (provider == .facebook) ? "auth_type" : "prompt"
            queryItems.append(URLQueryItem(name: promptKey, value: prompt))
        }

        // 7. Provider-specific extras
        if provider == .google || provider == .linkedin {
            queryItems.append(URLQueryItem(name: "include_granted_scopes", value: "true"))
        }

        comps.queryItems = queryItems
        let url = comps.url
        logger.trace("Built URL for \(provider.rawValue): \(url?.absoluteString ?? "nil")")
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
        let stateObject = OAuthState(
            provider: provider.rawValue,
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

    public func defaultSocialLoginRedirectUri() -> String {
        let base = FronteggAuth.shared.baseUrl
        let bundleId = FronteggApp.shared.bundleIdentifier
        let baseRedirectUri = "\(base)/oauth/account/social/success"
        
        guard let encodedRedirectUri = baseRedirectUri
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return baseRedirectUri
        }
        return encodedRedirectUri
    }
    
    public func defaultRedirectUri() -> String {
        let base = FronteggAuth.shared.baseUrl
        let bundleId = FronteggApp.shared.bundleIdentifier
        let baseRedirectUri = "\(base)/oauth/account/redirect/ios/\(bundleId)"
        
        guard let encodedRedirectUri = baseRedirectUri
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return baseRedirectUri
        }
        return encodedRedirectUri
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
            let data = Data(self.utf8)                            // UTF-8 bytes (same as TextEncoder)
            let hash = SHA256.hash(data: data)                    // SHA-256 digest
            let b64 = Data(hash).base64EncodedString()            // Standard Base64 with padding
            // Convert to Base64URL without padding to match the TS implementation
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
        if let index = queryItems.firstIndex(where: { $0.name == name }) {
            queryItems.remove(at: index)
        }
        queryItems.append(URLQueryItem(name: name, value: value))
        self.queryItems = queryItems
    }
}
