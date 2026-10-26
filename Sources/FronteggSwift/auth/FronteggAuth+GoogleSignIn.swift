//
//  FronteggAuth+GoogleSignIn.swift
//  FronteggSwift
//

import Foundation
import UIKit

extension FronteggAuth {

    /// Signs in with a Google ID token from `FronteggApp.shared.googleSignIn`, without the hosted login page.
    public func loginWithGoogle(_ completion: FronteggAuth.CompletionHandler? = nil) {
        let mainThreadCompletion = FronteggAuth.onMainThread(completion)
        let done = handleMfaRequired(mainThreadCompletion)
        Task { @MainActor in
            guard !self.isNativeGoogleSignInInProgress else {
                self.logger.info("Native Google sign-in is already running, canceling this call")
                mainThreadCompletion?(.failure(FronteggError.authError(.operationCanceled)))
                return
            }
            guard !self.isStepUpAuthorization else {
                self.logger.info("Native Google sign-in cannot step a session up, canceling this call")
                mainThreadCompletion?(.failure(FronteggError.authError(.operationCanceled)))
                return
            }
            guard FronteggApp.shared.loginOrganizationAlias == nil else {
                self.logger.info("Native Google sign-in cannot carry the login organization alias, canceling this call")
                mainThreadCompletion?(.failure(FronteggError.authError(.operationCanceled)))
                return
            }
            self.isNativeGoogleSignInInProgress = true
            defer { self.isNativeGoogleSignInInProgress = false }
            do {
                let user = try await self.signInWithGoogleIdToken()
                // An open login box completes too, as its own sign-in flows do, so its pending completion isn't left set.
                if self.webview != nil {
                    self.loginCompletion?(.success(user))
                }
                done(.success(user))
            } catch {
                let fronteggError = FronteggError.from(error)
                if case .authError(.mfaRequired(let mfaRequest, let refreshToken)) = fronteggError, self.webview != nil {
                    let completeOnce = self.completeWhenLoginBoxCompletes(mainThreadCompletion)
                    await self.continueMfaInLoginBox(mfaRequest, refreshToken: refreshToken, completion: completeOnce)
                    return
                }
                if fronteggError.category != .mfaRequired && fronteggError.category != .cancelled {
                    self.logger.error("Native Google sign-in failed: \(fronteggError.localizedDescription)")
                    // A missing provider or Google setup is an integration error, not one to show the user.
                    if fronteggError.category != .configuration {
                        self.reportOAuthFailure(error: fronteggError, flow: .socialLogin)
                    }
                }
                done(.failure(fronteggError))
            }
        }
    }

    static let accountActionPaths = [
        "/oauth/account/reset-password",
        "/oauth/account/verify-email",
        "/oauth/account/verify-phone",
        "/oauth/account/accept-invitation",
        "/oauth/account/activate",
        "/oauth/account/invitation/accept",
        "/oauth/account/unlock",
    ]

    func shouldSignInWithGoogleNatively(provider: String, action: SocialLoginAction) -> Bool {
        shouldSignInWithGoogleNatively(provider: provider, action: action, loginBoxURL: webview?.url)
    }

    // Sign-up, activation and invitation pages, step-up and login per account use the browser: the native post-login carries none of them.
    func shouldSignInWithGoogleNatively(provider: String, action: SocialLoginAction, loginBoxURL: URL?) -> Bool {
        let path = loginBoxURL?.path ?? ""
        let isAccountActionPage = Self.accountActionPaths.contains { path.hasSuffix($0) || path.contains($0 + "/") }
        let isNativeFlow = action == .login && !isAccountActionPage
            && !isStepUpAuthorization && FronteggApp.shared.loginOrganizationAlias == nil
        return provider == SocialLoginProvider.google.rawValue && isNativeFlow
            && FronteggGoogleSignInRuntimeSettings.providerBox.value != nil
    }

    func loginWithGoogle(
        presentingFrom window: UIWindow? = nil,
        fallingBackTo browserLogin: @escaping () -> Void,
        completion: @escaping FronteggAuth.CompletionHandler
    ) {
        let done = handleMfaRequired(completion)
        Task { @MainActor in
            guard !self.isNativeGoogleSignInInProgress else {
                self.logger.info("Native Google sign-in is already running, canceling this call")
                completion(.failure(FronteggError.authError(.operationCanceled)))
                return
            }
            self.isNativeGoogleSignInInProgress = true
            defer { self.isNativeGoogleSignInInProgress = false }
            do {
                done(.success(try await self.signInWithGoogleIdToken(presentingFrom: window)))
            } catch {
                let fronteggError = FronteggError.from(error)
                if case .authError(.mfaRequired(let mfaRequest, let refreshToken)) = fronteggError, self.webview != nil {
                    await self.continueMfaInLoginBox(mfaRequest, refreshToken: refreshToken, completion: done)
                    return
                }
                switch fronteggError.category {
                case .cancelled:
                    if self.activeEmbeddedOAuthFlow == .socialLogin {
                        self.activeEmbeddedOAuthFlow = .login
                    }
                    done(.failure(fronteggError))
                case .mfaRequired:
                    done(.failure(fronteggError))
                default:
                    self.logger.warning("Native Google sign-in failed, using the browser: \(fronteggError.localizedDescription)")
                    browserLogin()
                }
            }
        }
    }

    // MFA ends in the login box, so its completion also completes this sign-in, once.
    @MainActor
    private func completeWhenLoginBoxCompletes(
        _ completion: FronteggAuth.CompletionHandler?
    ) -> FronteggAuth.CompletionHandler {
        var isCompleted = false
        let completeOnce: FronteggAuth.CompletionHandler = { result in
            guard !isCompleted else { return }
            isCompleted = true
            completion?(result)
        }
        let loginBoxCompletion = loginCompletion
        loginCompletion = { [weak self] result in
            self?.loginCompletion = nil
            loginBoxCompletion?(result)
            completeOnce(result)
        }
        return completeOnce
    }

    // The login box is already on screen, so MFA continues in its web view instead of a new one.
    @MainActor
    private func continueMfaInLoginBox(
        _ mfaRequest: [String: Any],
        refreshToken: String?,
        completion: @escaping FronteggAuth.CompletionHandler
    ) async {
        setWebLoading(true)
        do {
            let (authorizeUrl, _) = try await multiFactorAuthenticator.start(mfaRequestData: mfaRequest, refreshToken: refreshToken)
            activeEmbeddedOAuthFlow = .mfa
            guard loadInWebView(authorizeUrl) else {
                failMfaInLoginBox(FronteggError.authError(.couldNotFindRootViewController), completion: completion)
                return
            }
        } catch {
            failMfaInLoginBox(FronteggError.from(error), completion: completion)
        }
    }

    @MainActor
    private func failMfaInLoginBox(_ error: FronteggError, completion: FronteggAuth.CompletionHandler) {
        logger.error("Could not continue Google sign-in MFA in the login box: \(error.localizedDescription)")
        setWebLoading(false)
        activeEmbeddedOAuthFlow = .login
        reportOAuthFailure(error: error, flow: .mfa)
        completion(.failure(error))
    }

    @MainActor
    private func signInWithGoogleIdToken(presentingFrom window: UIWindow? = nil) async throws -> User {
        guard let provider = FronteggGoogleSignInRuntimeSettings.providerBox.value else {
            logger.error("loginWithGoogle needs FronteggApp.shared.googleSignIn to be set")
            throw FronteggError.configError(.socialLoginMissing("Google"))
        }
        let googleConfig = try await nativeGoogleConfig()
        guard let googleConfig, googleConfig.active, let serverClientId = googleConfig.clientId, !serverClientId.isEmpty else {
            logger.error("Google social login is not active or has no client ID in Frontegg")
            throw FronteggError.configError(.socialLoginMissing("Google"))
        }
        // Google issues ID tokens only for a web client in the iOS client's Cloud project, never Frontegg's shared one.
        guard googleConfig.customised else {
            logger.error("Native Google sign-in needs your own Google app credentials configured in Frontegg")
            throw FronteggError.configError(.socialLoginMissing("Google"))
        }
        // The Google sheet must be presented from the controller on top, such as the open login box.
        var topController = window?.rootViewController ?? getRootVC(true)
        while let presented = topController?.presentedViewController, !presented.isBeingDismissed {
            topController = presented
        }
        guard let presenter = topController else {
            logger.error("No view controller to present Google sign-in from")
            throw FronteggError.authError(.couldNotFindRootViewController)
        }

        // A refresh, such as the one when the app becomes active as the sheet closes, must not race the exchange.
        let wasLoginInProgress = isLoginInProgress
        isLoginInProgress = true
        defer { isLoginInProgress = wasLoginInProgress }
        let idToken = try await provider.idToken(serverClientId: serverClientId, presenting: presenter)
        let isLoginBoxOpen = webview != nil
        setGoogleSignInLoading(true, isLoginBoxOpen: isLoginBoxOpen)
        defer { setGoogleSignInLoading(false, isLoginBoxOpen: isLoginBoxOpen) }
        let authResponse = try await api.postloginGoogleNative(idToken: idToken)
        await setCredentials(accessToken: authResponse.access_token, refreshToken: authResponse.refresh_token)
        guard let user = self.user else {
            throw FronteggError.authError(.failedToAuthenticate)
        }
        return user
    }

    // A usable config is reused briefly; an unusable one is never kept, so turning Google on applies at the next tap.
    @MainActor
    private func nativeGoogleConfig() async throws -> SocialLoginOption? {
        let configApi = api
        if let cache = nativeGoogleConfigCache, cache.api === configApi, Date() < cache.expiresAt {
            return cache.option
        }
        let option = try await configApi.getSocialLoginConfig().google
        if let option, option.active, option.customised, !(option.clientId ?? "").isEmpty {
            nativeGoogleConfigCache = NativeGoogleConfigCache(
                option: option,
                api: configApi,
                expiresAt: Date().addingTimeInterval(NativeGoogleConfigCache.lifetime)
            )
        }
        return option
    }

    // isLoading would replace an open login box with a loader and rebuild its web view, losing an MFA page loaded into it.
    @MainActor
    private func setGoogleSignInLoading(_ isLoading: Bool, isLoginBoxOpen: Bool) {
        if isLoginBoxOpen {
            setWebLoading(isLoading)
        } else {
            setIsLoading(isLoading)
        }
    }
}

struct NativeGoogleConfigCache {
    static let lifetime: TimeInterval = 60

    let option: SocialLoginOption
    weak var api: Api?
    let expiresAt: Date
}
