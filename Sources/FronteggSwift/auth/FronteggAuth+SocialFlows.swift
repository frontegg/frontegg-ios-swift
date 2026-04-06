//
//  FronteggAuth+SocialFlows.swift
//  FronteggSwift
//
//  Social login flows: Apple, OAuth providers, legacy social login.
//

import Foundation
import UIKit
import AuthenticationServices
import WebKit

struct OAuth2SessionStateContext {
    let encodedState: Data
    let pendingOAuthState: String?
}

extension FronteggAuth {

    func completeSocialLoginFailure(
        _ error: FronteggError,
        errorCode: String? = nil,
        errorDescription: String? = nil,
        completion: @escaping FronteggAuth.CompletionHandler
    ) {
        SocialLoginUrlGenerator.shared.clearPendingSocialCodeVerifiers()
        DispatchQueue.main.async {
            self.activeEmbeddedOAuthFlow = .login
            self.reportOAuthFailure(
                error: error,
                flow: .socialLogin,
                errorCode: errorCode,
                errorDescription: errorDescription
            )
            completion(.failure(error))
        }
    }

    func completeSocialLoginFailure(
        _ details: OAuthFailureDetails,
        completion: @escaping FronteggAuth.CompletionHandler
    ) {
        SocialLoginUrlGenerator.shared.clearPendingSocialCodeVerifiers()
        DispatchQueue.main.async {
            self.activeEmbeddedOAuthFlow = .login
            self.reportOAuthFailure(details: details, flow: .socialLogin)
            completion(.failure(details.error))
        }
    }

    internal func handleSocialLoginOAuthCallback(
        providerString: String,
        callbackURL: URL?,
        error: Error?,
        completion: @escaping FronteggAuth.CompletionHandler
    ) {
        if let error {
            self.logger.error("OAuth error: \(String(describing: error))")
            self.completeSocialLoginFailure(
                FronteggError.authError(.other(error)),
                completion: completion
            )
            return
        }

        guard let callbackURL else {
            self.logger.info("OAuth callback invoked with nil URL and no error")
            self.completeSocialLoginFailure(
                FronteggError.authError(.unknown),
                completion: completion
            )
            return
        }

        self.logger.debug("OAuth callback URL: \(callbackURL.absoluteString)")

        let callbackQueryItems = getQueryItems(callbackURL.absoluteString)
        if let queryItems = callbackQueryItems,
           let failureDetails = self.oauthFailureDetails(from: queryItems) {
            self.completeSocialLoginFailure(failureDetails, completion: completion)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard let finalURL = self.handleSocialLoginCallback(callbackURL) else {
                SentryHelper.logMessage(
                    "Social login callback could not be parsed (hosted)",
                    level: .warning,
                    context: [
                        "social_login": [
                            "provider": providerString,
                            "callbackUrl": callbackURL.absoluteString,
                            "baseUrl": FronteggAuth.shared.baseUrl
                        ],
                        "error": [
                            "type": "social_login_callback_unhandled"
                        ]
                    ]
                )
                self.completeSocialLoginFailure(
                    FronteggError.authError(.failedToExtractCode),
                    completion: completion
                )
                return
            }
            // Re-inject code verifier into webview localStorage before loading success URL
            await SocialLoginUrlGenerator.shared.reinjectCodeVerifierIntoWebview(
                for: callbackQueryItems?["state"]
            )
            self.loadInWebView(finalURL)
        }
    }

    /// Starts a social login flow.
    ///
    /// - Parameters:
    ///   - providerString: The social provider raw value (e.g., "google", "facebook", "apple").
    ///   - action: The social login action to perform (default: `.login`).
    ///   - completion: Optional completion handler. A no-op is used if nil.
    public func handleSocialLogin(
        providerString: String,
        custom:Bool,
        action: SocialLoginAction = .login,
        completion: FronteggAuth.CompletionHandler? = nil
    ) {
        FronteggRuntime.testingLog(
            "E2E handleSocialLogin start provider=\(providerString) custom=\(custom) action=\(action.rawValue)"
        )
        let done = completion ?? { _ in }

        // Special-case Apple to keep branching explicit and fast.
        if providerString == "apple" {
            loginWithApple(done)
            return
        }

        // Social login flows are single-flight. Drop any stale verifier state from a
        // previous abandoned attempt before generating the next authorize URL.
        SocialLoginUrlGenerator.shared.clearPendingSocialCodeVerifiers()

        let oauthCallback: (URL?, Error?) -> Void = { [weak self] callbackURL, error in
            guard let self else { return }
            self.handleSocialLoginOAuthCallback(
                providerString: providerString,
                callbackURL: callbackURL,
                error: error,
                completion: done
            )
        }

        Task { [weak self] in
            guard let self else { return }

            let generatedAuthUrl: URL? = if(custom){
                try? await SocialLoginUrlGenerator.shared
                    .authorizeURL(forCustomProvider: providerString, action: action)
            } else if let provider = SocialLoginProvider(rawValue: providerString) {
                try? await SocialLoginUrlGenerator.shared
                    .authorizeURL(for: provider, action: action)
            }else {
                nil
            }
            FronteggRuntime.testingLog(
                "E2E handleSocialLogin generatedAuthUrl provider=\(providerString) url=\(generatedAuthUrl?.absoluteString ?? "nil")"
            )

            // Check if we need to use legacy flow
            if generatedAuthUrl == nil && !custom {
                if let provider = SocialLoginProvider(rawValue: providerString),
                   let legacyUrl = try? await SocialLoginUrlGenerator.shared.legacyAuthorizeURL(for: provider, action: action) {
                    logger.debug("Using legacy social login flow for provider: \(providerString)")
                    self.loginWithSocialLogin(socialLoginUrl: legacyUrl, done)
                    return
                }
            }

            guard let authURL = generatedAuthUrl else {
                self.logger.error("Failed to generate auth URL for \(providerString)")
                self.completeSocialLoginFailure(
                    FronteggError.authError(.unknown),
                    completion: done
                )
                return
            }

            self.logger.debug("Auth URL: \(authURL.absoluteString)")

             let window: UIWindow? = await MainActor.run {
                return self.getRootVC()?.view.window
            }

            let useEphemeral = false

            await MainActor.run {
                FronteggRuntime.testingLog(
                    "E2E handleSocialLogin starting WebAuthenticator url=\(authURL.absoluteString)"
                )
                WebAuthenticator.shared.start(
                    authURL,
                    ephemeralSession: useEphemeral,
                    window: window,
                    completionHandler: oauthCallback
                )
            }
        }
    }

    func loadInWebView(_ url: URL) {
        guard let webView = webview else { return }
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
        webView.load(request)
    }

    internal func loginWithApple(_ _completion: @escaping FronteggAuth.CompletionHandler)  {
        let completion = handleMfaRequired(_completion)
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do{
                    let config = try PlistHelper.fronteggConfig()
                    let socialConfig =  try await self.api.getSocialLoginConfig()

                    if let appleConfig = socialConfig.apple, appleConfig.active {
                        if #available(iOS 15.0, *), appleConfig.customised, !config.useAsWebAuthenticationForAppleLogin {
                            await AppleAuthenticator.shared.start(completionHandler: completion)
                        }else {
                            let generatedAuth = try await self.generateAppleAuthorizeUrl(config: appleConfig)
                            let oauthCallback = self.createOauthCallbackHandler(
                                completion,
                                allowLastCodeVerifierFallback: true,
                                pendingOAuthState: generatedAuth.pendingOAuthState,
                                flow: .apple
                            )
                            await WebAuthenticator.shared.start(generatedAuth.url, ephemeralSession: true, completionHandler: oauthCallback)
                        }
                    } else {
                        throw FronteggError.configError(.socialLoginMissing("Apple"))
                    }
                } catch {
                    if error is FronteggError {
                        completion(.failure(error as! FronteggError))
                    }else {
                        self.logger.error(error.localizedDescription)
                        completion(.failure(FronteggError.authError(.unknown)))
                    }

                }
            }

        }
    }

    func createOauth2SessionState() async throws -> OAuth2SessionStateContext {
        let (url, codeVerifier)  = AuthorizeUrlGenerator.shared.generate()
        let pendingOAuthState = pendingOAuthState(from: url)

        let (_, authorizeResponse) = try await FronteggAuth.shared.api.getRequest(path: url.absoluteString, accessToken: nil, additionalHeaders: ["Accept":"text/html"])

        guard let authorizeResponseUrl = authorizeResponse.url,
              let authorizeComponent = URLComponents(string: authorizeResponseUrl.absoluteString),
              let sessionState = authorizeComponent.queryItems?.first(where: { q in
                  q.name == "state"
              })?.value else {
            throw FronteggError.authError(.failedToAuthenticate)
        }

        let redirectUri = generateRedirectUri()

        let oauthStateDic = [
            "FRONTEGG_OAUTH_REDIRECT_AFTER_LOGIN": redirectUri,
            "FRONTEGG_OAUTH_STATE_AFTER_LOGIN": sessionState,
        ]

        guard let oauthStateJson = try? JSONSerialization.data(withJSONObject: oauthStateDic, options: .withoutEscapingSlashes) else {
            throw FronteggError.authError(.failedToAuthenticate)
        }

        return OAuth2SessionStateContext(
            encodedState: oauthStateJson,
            pendingOAuthState: pendingOAuthState
        )
    }

    func generateAppleAuthorizeUrl(config: SocialLoginOption) async throws -> (url: URL, pendingOAuthState: String?) {
        let sessionState = try await createOauth2SessionState()

        let scope = ["openid", "name", "email"] + config.additionalScopes
        let appId = FronteggAuth.shared.applicationId ?? ""

        let stateDict = [
            "oauthState": sessionState.encodedState.base64EncodedString(),
            "appId": appId,
            "provider": "apple",
            "action": "login",
        ]

        guard let stateJson = try? JSONSerialization.data(withJSONObject: stateDict, options: .withoutEscapingSlashes),
              let state = String(data: stateJson, encoding: .utf8) else {
            throw FronteggError.authError(.failedToAuthenticate)
        }

        var urlComponent = URLComponents(string: "https://appleid.apple.com/auth/authorize")!
        urlComponent.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "response_mode", value: "form_post"),
            URLQueryItem(name: "redirect_uri", value: config.backendRedirectUrl),
            URLQueryItem(name: "scope", value: scope.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "client_id", value: config.clientId)
        ]

        let finalUrl = urlComponent.url!

        return (finalUrl, sessionState.pendingOAuthState)
    }

    func loginWithSocialLogin(socialLoginUrl: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in


        }

        // Log social login initiation
        let isMicrosoft = socialLoginUrl.contains("microsoft") || socialLoginUrl.contains("login.microsoftonline.com")
        // Use shared session (non-ephemeral) for all providers to show saved accounts
        let useEphemeral = false

        SentryHelper.addBreadcrumb(
            "Social login initiated (loginWithSocialLogin)",
            category: "social_login",
            level: .info,
            data: [
                "socialLoginUrl": socialLoginUrl,
                "isMicrosoft": isMicrosoft,
                "useEphemeral": useEphemeral,
                "embeddedMode": self.embeddedMode,
                "baseUrl": self.baseUrl
            ]
        )

        let directLogin: [String: Any] = [
            "type": "direct",
            "data": socialLoginUrl,
        ]
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: true)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: true)
        }

        let (authorizeUrl, codeVerifier) = generatedUrl
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .socialLogin
        )

        logger.info("🔵 [Social Login] Starting social login flow")
        logger.info("🔵 [Social Login] Authorize URL: \(authorizeUrl.absoluteString)")
        logger.info("🔵 [Social Login] Use ephemeral session: \(useEphemeral)")

       let window: UIWindow?
        if Thread.isMainThread {
            window = getRootVC()?.view.window
        } else {
            var mainWindow: UIWindow?
            DispatchQueue.main.sync {
                mainWindow = getRootVC()?.view.window
            }
            window = mainWindow
        }

         if Thread.isMainThread {
            WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: useEphemeral, window: window, completionHandler: oauthCallback)
        } else {
            DispatchQueue.main.async {
                WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: useEphemeral, window: window, completionHandler: oauthCallback)
            }
        }
    }
}
