//
//  FronteggAuth+EmbeddedAndDeepLink.swift
//  FronteggSwift
//
//  Embedded login, deep-link handling, and tenant switching.
//

import Foundation
import UIKit
import SwiftUI
import AuthenticationServices

extension FronteggAuth {

    public func embeddedLogin(_ _completion: FronteggAuth.CompletionHandler? = nil, loginHint: String?) {

        if let rootVC = self.getRootVC() {
            FronteggRuntime.testingLog(
                "E2E embeddedLogin rootVC=\(type(of: rootVC)) presented=\(String(describing: rootVC.presentedViewController)) embeddedMode=\(self.embeddedMode)"
            )
            self.loginHint = loginHint
            if self.pendingAppLink == nil {
                self.activeEmbeddedOAuthFlow = .login
            }
            if self.loginCompletion != nil {
                logger.info("Login request ignored, Embedded login already in progress.")
                return
            }
            self.loginCompletion = { result in
                _completion?(result)
                self.loginCompletion = nil
            }
            let loginModal = EmbeddedLoginModal(parentVC: rootVC)
            let hostingController = UIHostingController(rootView: loginModal)
            hostingController.modalPresentationStyle = .fullScreen

            if(rootVC.presentedViewController?.classForCoder == hostingController.classForCoder){
                rootVC.presentedViewController?.dismiss(animated: false)
            }

            rootVC.present(hostingController, animated: false, completion: nil)
            FronteggRuntime.testingLog("E2E embeddedLogin present called")

        } else {
            logger.critical(FronteggError.authError(.couldNotFindRootViewController).localizedDescription)
            exit(500)
        }
    }

    public func handleOpenUrl(_ url: URL, _ useAppRootVC: Bool = false, internalHandleUrl:Bool = false) -> Bool {
        logger.info("🔵 [handleOpenUrl] Received URL: \(url.absoluteString)")
        logger.info("🔵 [handleOpenUrl] Base URL: \(self.baseUrl)")
        logger.info("🔵 [handleOpenUrl] URL has prefix baseUrl: \(url.absoluteString.hasPrefix(self.baseUrl))")
        logger.info("🔵 [handleOpenUrl] internalHandleUrl: \(internalHandleUrl)")
        let matchesGeneratedRedirectCallback = matchesGeneratedRedirectUri(url)
        let parsedQueryItems = getQueryItems(url.absoluteString)

        // Log app redirect handling
        SentryHelper.addBreadcrumb(
            "App redirect received (handleOpenUrl)",
            category: "app_redirect",
            level: .info,
            data: [
                "url": url.absoluteString,
                "scheme": url.scheme ?? "nil",
                "host": url.host ?? "nil",
                "path": url.path,
                "query": url.query ?? "nil",
                "baseUrl": self.baseUrl,
                "matchesBaseUrl": url.absoluteString.hasPrefix(self.baseUrl),
                "matchesGeneratedRedirectUri": matchesGeneratedRedirectCallback,
                "internalHandleUrl": internalHandleUrl,
                "embeddedMode": self.embeddedMode
            ]
        )

        let redirectCallbackFailureDetails: OAuthFailureDetails? = {
            guard let parsedQueryItems else { return nil }
            if let failureDetails = self.oauthFailureDetails(from: parsedQueryItems) {
                return failureDetails
            }

            let rawError = parsedQueryItems["error"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDescription = parsedQueryItems["error_description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !(rawError?.isEmpty ?? true) || !(rawDescription?.isEmpty ?? true) else {
                return nil
            }

            return self.oauthFailureDetails(
                errorCode: parsedQueryItems["error"],
                errorDescription: parsedQueryItems["error_description"],
                fallbackError: FronteggError.authError(.failedToExtractCode)
            )
        }()

        if matchesGeneratedRedirectCallback,
           let failureDetails = redirectCallbackFailureDetails {
            logger.info("✅ [handleOpenUrl] Detected generated redirect URI OAuth error callback")
            self.reportOAuthFailure(
                details: failureDetails,
                flow: self.activeEmbeddedOAuthFlow
            )

            if let webView = self.webview {
                let (newUrl, _) = AuthorizeUrlGenerator().generate(remainCodeVerifier: true)
                self.setWebLoading(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    webView.load(URLRequest(url: newUrl, cachePolicy: .reloadRevalidatingCacheData))
                }
            }

            self.activeEmbeddedOAuthFlow = .login
            setAppLink(false)
            return true
        }

        if(!url.absoluteString.hasPrefix(self.baseUrl) && !internalHandleUrl && !matchesGeneratedRedirectCallback){
            // Recovery for system mis-routed OAuth callbacks.
            //
            // Background: when multiple iOS apps from the same TeamID share the
            // same Universal Link associated domain (the multi-app AASA case)
            // iOS may dispatch an ASWebAuthSession callback to the *wrong*
            // app. The receiving app sees a URL whose scheme/host/path don't
            // match the strict redirect URI it generated, so the strict check
            // above misses. If the URL is recognisably OAuth-shaped (custom
            // scheme matches one of our declared `CFBundleURLSchemes` AND
            // carries `code` or `error`), recover instead of silently
            // dropping the OAuth code. Same recognition rule the embedded
            // `CustomWebView` already applies internally.
            if let scheme = url.scheme?.lowercased(),
               appURLSchemes().contains(scheme),
               let queryItems = parsedQueryItems,
               (queryItems["code"] != nil || queryItems["error"] != nil) {
                logger.warning(
                    "⚠️ [handleOpenUrl] OAuth-shaped URL didn't match strict redirect URI but has a recognised scheme — attempting recovery. " +
                    "url=\(url.absoluteString) scheme=\(scheme) host=\(url.host ?? "nil") path=\(url.path)"
                )
                SentryHelper.logMessage(
                    "App redirect URL recovered via custom-scheme parity",
                    level: .warning,
                    context: [
                        "app_redirect": [
                            "url": url.absoluteString,
                            "baseUrl": self.baseUrl,
                            "scheme": scheme,
                            "host": url.host ?? "nil",
                            "path": url.path,
                            "internalHandleUrl": internalHandleUrl,
                            "hasCode": queryItems["code"] != nil,
                            "hasError": queryItems["error"] != nil
                        ],
                        "error": [
                            "type": "redirect_url_recovered_via_scheme"
                        ]
                    ]
                )

                return recoverFromMisroutedOAuthCallback(url: url, queryItems: queryItems)
            }

            // S3 from plan.md: URLs that aren't OAuth-shaped (no `code`/
            // `error`, or scheme not in `appURLSchemes()`) are almost
            // always host-app deep links the SDK shouldn't claim
            // (share-links, push opens). Log at debug level + a Sentry
            // breadcrumb instead of warning-level so they don't pollute
            // Datadog/Sentry alerting with benign noise.
            logger.debug(
                "[handleOpenUrl] URL not handled by SDK (not OAuth-shaped). " +
                "url=\(url.absoluteString) scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil") path=\(url.path)"
            )
            SentryHelper.addBreadcrumb(
                "App redirect URL declined - not OAuth-shaped",
                category: "app_redirect",
                level: .debug,
                data: [
                    "url": url.absoluteString,
                    "baseUrl": self.baseUrl,
                    "internalHandleUrl": internalHandleUrl,
                    "matchesGeneratedRedirectUri": matchesGeneratedRedirectCallback,
                    "scheme": url.scheme ?? "nil",
                    "host": url.host ?? "nil",
                    "path": url.path
                ]
            )
            setAppLink(false)
            return false
        }

        if url.path.contains("/postlogin/verify") {
            logger.info("✅ [handleOpenUrl] Detected /postlogin/verify URL, processing verification")
            SentryHelper.addBreadcrumb(
                "Processing /postlogin/verify URL",
                category: "app_redirect",
                level: .info,
                data: [
                    "url": url.absoluteString,
                    "hasToken": url.query?.contains("token") ?? false
                ]
            )
            var verificationUrl = url
            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var queryItems = urlComponents.queryItems ?? []

                let redirectUri = generateRedirectUri()
                if !queryItems.contains(where: { $0.name == "redirect_uri" }) {
                    queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectUri))
                }

                if let codeVerifier = CredentialManager.getCodeVerifier() {
                     if !queryItems.contains(where: { $0.name == "code_verifier_pkce" }) {
                        queryItems.append(URLQueryItem(name: "code_verifier_pkce", value: codeVerifier))
                        logger.info("Added code_verifier_pkce to verification URL")
                    }
                } else {
                    logger.warning("No code verifier found for verification URL - this may cause verification to fail")
                }

                urlComponents.queryItems = queryItems
                if let updatedUrl = urlComponents.url {
                    verificationUrl = updatedUrl
                }
            }

            let completion: FronteggAuth.CompletionHandler
            if let existingCompletion = self.loginCompletion {
                completion = existingCompletion
            } else {
                completion = { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let user):
                        self.logger.info("✅ Email verification completed successfully. User logged in: \(user.email)")
                        // Login is complete, no need to do anything else
                    case .failure(let error):
                        self.logger.error("❌ Email verification failed: \(error.localizedDescription)")
                    }
                }
            }

            let oauthCallback = createOauthCallbackHandler(
                completion,
                allowLastCodeVerifierFallback: true,
                pendingOAuthState: pendingOAuthState(from: verificationUrl),
                flow: .verification
            )

            var callbackReceived = false
            var sessionRef: ASWebAuthenticationSession? = nil

            let wrappedCallback: (URL?, Error?) -> Void = { [weak self] callbackUrl, error in
                guard let self = self else { return }
                callbackReceived = true

                // Cancel the session immediately to prevent showing localhost
                if let session = sessionRef {
                    session.cancel()
                    sessionRef = nil
                }

                if let url = callbackUrl, let host = url.host, (host.contains("localhost") || host.contains("127.0.0.1")) {
                    self.logger.warning("⚠️ Detected localhost redirect in verification callback, retrying social login immediately")
                    // Retry immediately without delay
                    if let urlComponents = URLComponents(url: verificationUrl, resolvingAgainstBaseURL: false),
                       let queryItems = urlComponents.queryItems,
                       let type = queryItems.first(where: { $0.name == "type" })?.value {
                        self.handleSocialLogin(providerString: type, custom: false, action: .login) { result in
                            switch result {
                            case .success(let user):
                                completion(.success(user))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    } else {
                        completion(.failure(FronteggError.authError(.unknown)))
                    }
                    return
                }


                oauthCallback(callbackUrl, error)
            }

            // Reduce timeout to 3 seconds to minimize localhost visibility
            // If verification takes longer, it likely redirected to localhost
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, !callbackReceived else { return }

                // Cancel the session to stop showing localhost
                if let session = sessionRef {
                    session.cancel()
                    sessionRef = nil
                }

                self.logger.info("🔄 Verification timeout - retrying social login to avoid localhost redirect")
                if let urlComponents = URLComponents(url: verificationUrl, resolvingAgainstBaseURL: false),
                   let queryItems = urlComponents.queryItems,
                   let type = queryItems.first(where: { $0.name == "type" })?.value {
                    self.handleSocialLogin(providerString: type, custom: false, action: .login) { result in
                        switch result {
                        case .success(let user):
                            self.logger.info("✅ Login completed successfully after verification timeout")
                            completion(.success(user))
                        case .failure(let error):
                            self.logger.error("❌ Login failed after verification timeout: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    }
                } else {
                    completion(.failure(FronteggError.authError(.unknown)))
                }
            }

            let window: UIWindow?
            if Thread.isMainThread {
                window = getRootVC(useAppRootVC)?.view.window
            } else {
                var mainWindow: UIWindow?
                DispatchQueue.main.sync {
                    mainWindow = getRootVC(useAppRootVC)?.view.window
                }
                window = mainWindow
            }

            if Thread.isMainThread {
                WebAuthenticator.shared.start(verificationUrl, ephemeralSession: false, window: window, completionHandler: wrappedCallback)
                sessionRef = WebAuthenticator.shared.session
            } else {
                DispatchQueue.main.async {
                    WebAuthenticator.shared.start(verificationUrl, ephemeralSession: false, window: window, completionHandler: wrappedCallback)
                    sessionRef = WebAuthenticator.shared.session
                }
            }
            return true
        }

        guard let rootVC = self.getRootVC(useAppRootVC) else {
            self.logger.error(FronteggError.authError(.couldNotFindRootViewController).localizedDescription)
            return false;
        }

        if let socialLoginUrl = handleSocialLoginCallback(url){
            self.activeEmbeddedOAuthFlow = .socialLogin
            if let webView = self.webview {
                let request = URLRequest(url: socialLoginUrl, cachePolicy: .reloadRevalidatingCacheData)
                webView.load(request)
                return true
            }else {
                self.pendingAppLink = socialLoginUrl
            }
        }else {
            self.activeEmbeddedOAuthFlow = .login
            self.pendingAppLink = url
        }
        setWebLoading(true)

        // Cancel any active ASWebAuthenticationSession before presenting EmbeddedLoginModal
        // This prevents the magic link deep link from opening Internal WebView on top of Custom Tab
        // which would break the session context. Suppress the synthetic
        // canceledLogin so the WebView-side completion isn't masked.
        if let activeSession = WebAuthenticator.shared.session {
            WebAuthenticator.shared.cancelSuppressingCanceledLogin(activeSession)
        }

        let loginModal = EmbeddedLoginModal(parentVC: rootVC)
        let hostingController = UIHostingController(rootView: loginModal)
        hostingController.modalPresentationStyle = .fullScreen

        let presented = rootVC.presentedViewController
        if presented is UIHostingController<EmbeddedLoginModal> {
            rootVC.presentedViewController?.dismiss(animated: false)
        }
        rootVC.present(hostingController, animated: false, completion: nil)

        return true
    }

    public func  switchTenant(tenantId:String,_ completion: FronteggAuth.CompletionHandler? = nil) {

        self.logger.info("Switching tenant to: \(tenantId)")
        if let currentUser = self.user {
            self.logger.info("Current tenant: \(currentUser.activeTenant.name) (ID: \(currentUser.activeTenant.id), tenantId: \(currentUser.activeTenant.tenantId))")
        }

        self.setIsLoading(true)

        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                let config = try? PlistHelper.fronteggConfig()
                let enableSessionPerTenant = config?.enableSessionPerTenant ?? false


                if enableSessionPerTenant {
                    self.credentialManager.saveLastActiveTenantId(tenantId)
                    self.logger.info("Saved new tenant ID (\(tenantId)) as last active tenant before switching")

                    if let currentUser = self.user {
                        let currentTenantId = currentUser.activeTenant.id
                        if let currentRefreshToken = self.refreshToken,
                           let currentAccessToken = self.accessToken {
                            do {
                                try self.credentialManager.saveTokenForTenant(currentRefreshToken, tenantId: currentTenantId, tokenType: .refreshToken)
                                try self.credentialManager.saveTokenForTenant(currentAccessToken, tenantId: currentTenantId, tokenType: .accessToken)
                                self.logger.info("Saved tokens for tenant \(currentTenantId) before switching")
                            } catch {
                                self.logger.warning("Failed to save tokens for tenant \(currentTenantId): \(error)")
                            }
                        }
                    }
                    if let newRefreshToken = try? self.credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken),
                       let newAccessToken = try? self.credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .accessToken) {
                        // Load existing tokens for the new tenant
                        await MainActor.run {
                            self.setRefreshToken(newRefreshToken)
                            self.setAccessToken(newAccessToken)
                        }
                        self.logger.info("Loaded existing tokens for tenant \(tenantId) from local storage")

                        do {
                            let data = try await self.api.refreshToken(
                                refreshToken: newRefreshToken,
                                tenantId: tenantId
                            )
                            await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)

                            if let user = self.user {
                                self.logger.info("Tenant switch completed using existing tokens (no server-side API call). New active tenant: \(user.activeTenant.name) (ID: \(user.activeTenant.id))")
                                await MainActor.run {
                                    self.setIsLoading(false)
                                }
                    completion?(.success(user))
                                return
                            }
                        } catch {
                            self.logger.warning("Refresh with tenantId failed, trying standard OAuth refresh: \(error)")
                            do {
                                let data = try await self.api.refreshToken(
                                    refreshToken: newRefreshToken,
                                    tenantId: nil
                                )
                                await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)

                                if let user = self.user {
                                    if user.activeTenant.id == tenantId {
                                        self.logger.info("Tenant switch completed using existing tokens (standard OAuth refresh). New active tenant: \(user.activeTenant.name) (ID: \(user.activeTenant.id))")
                                        await MainActor.run {
                                            self.setIsLoading(false)
                                        }
                                        completion?(.success(user))
                                        return
                } else {
                                        self.logger.warning("Standard OAuth refresh returned wrong tenant (\(user.activeTenant.id) instead of \(tenantId)), will use server-side API")
                                    }
                                }
                            } catch {
                                self.logger.warning("Both refresh methods failed for tenant \(tenantId), will create new tokens: \(error)")
                            }
                        }
                    } else {
                        self.logger.info("No existing tokens found for tenant \(tenantId) in local storage")
                    }
                    self.logger.info("No existing tokens found for tenant \(tenantId), creating new tokens via server-side API")
                }

                guard let currentAccessToken = self.accessToken else {
                    self.logger.error("No access token available for tenant switch")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    return
                }

                self.logger.info("Calling server-side API to switch tenant to: \(tenantId) (access token length: \(currentAccessToken.count))")

                do {
                    try await self.api.switchTenant(tenantId: tenantId, accessToken: currentAccessToken)
                    self.logger.info("Successfully switched tenant via API to: \(tenantId)")
                } catch {
                    self.logger.error("Failed to switch tenant via API: \(error)")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    return
                }

                guard let refreshToken = self.refreshToken else {
                    self.logger.error("No refresh token available for tenant switch")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    return
                }

                self.logger.info("Using refresh token for tenant switch (token length: \(refreshToken.count))")

                // Refresh tokens to get updated user data with new tenant
                do {
                    self.logger.info("Refreshing token after tenant switch to: \(tenantId)")
                    var data: AuthResponse

                    if enableSessionPerTenant {
                        // After a server-side tenant switch, we MUST use standard OAuth refresh first
                        // to get a new refresh token that's valid for the new tenant.
                        // The old refresh token is still associated with the old tenant, so
                        // tenant-specific refresh will fail until we get new tokens.
                        self.logger.info("Using standard OAuth refresh after server-side tenant switch to get new tokens for tenant: \(tenantId)")
                        data = try await self.api.refreshToken(
                            refreshToken: refreshToken,
                            tenantId: nil
                        )
                        self.logger.info("Standard OAuth refresh successful after tenant switch. New tokens will be saved with tenant ID: \(tenantId)")
                    } else {
                        data = try await self.api.refreshToken(
                            refreshToken: refreshToken,
                            tenantId: nil
                        )
                    }

                    self.logger.info("Token refresh successful, updating credentials")
                    await self.setCredentials(accessToken: data.access_token, refreshToken: data.refresh_token)
                    if let user = self.user {
                        let newTenantId = user.activeTenant.id
                        if newTenantId != tenantId {
                            self.logger.warning("Tenant switch returned different tenant ID (\(newTenantId)) than expected (\(tenantId)). Updating stored tenant ID.")
                            self.credentialManager.saveLastActiveTenantId(newTenantId)
                        }
                        self.logger.info("Tenant switch completed. New active tenant: \(user.activeTenant.name) (ID: \(newTenantId), tenantId: \(user.activeTenant.tenantId))")

                        if newTenantId != tenantId && user.activeTenant.tenantId != tenantId {
                            self.logger.warning("Tenant switch may have failed - expected \(tenantId) but got \(newTenantId)")
                        }

                        await MainActor.run {
                            self.setIsLoading(false)
                        }
                        completion?(.success(user))
                    } else {
                        self.logger.error("User is nil after tenant switch and refresh")
                        await MainActor.run {
                            self.setIsLoading(false)
                        }
                        completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                    }
                } catch {
                    self.logger.error("Failed to refresh token after tenant switch: \(error)")
                    await MainActor.run {
                        self.setIsLoading(false)
                    }
                    completion?(.failure(FronteggError.authError(.failedToSwitchTenant)))
                }

            }
        }
    }

    /// Recover an OAuth callback whose scheme matches one of our declared
    /// `CFBundleURLSchemes` but whose host/path don't match the generated
    /// redirect URI (e.g. iOS dispatched a sibling app's Universal Link
    /// callback to us, or the hosted page issued a custom-scheme redirect
    /// using a non-canonical path). Returns `true` to signal the URL was
    /// consumed.
    @discardableResult
    func recoverFromMisroutedOAuthCallback(url: URL, queryItems: [String: String]) -> Bool {
        // Cancel any in-flight ASWebAuthSession so the system Safari dismisses;
        // suppress the synthetic canceledLogin so it doesn't race a successful
        // token exchange below.
        if let activeSession = WebAuthenticator.shared.session {
            WebAuthenticator.shared.cancelSuppressingCanceledLogin(activeSession)
        }

        let oauthState = queryItems["state"]

        // Match the precedence used by createOauthCallbackHandler and the
        // strict-redirect branch above: if the callback carries an `error`,
        // report it and stop — even if a stray `code` is also present (a
        // non-spec response we shouldn't try to silently exchange).
        if let failureDetails = self.oauthFailureDetails(from: queryItems) {
            logger.error("❌ [handleOpenUrl recovery] OAuth error in mis-routed callback: \(failureDetails.error.localizedDescription)")
            self.reportOAuthFailure(details: failureDetails, flow: self.activeEmbeddedOAuthFlow)
            self.setWebLoading(false)
            self.setIsLoading(false)
            self.activeEmbeddedOAuthFlow = .login
            setAppLink(false)
            return true
        }

        guard let code = queryItems["code"], !code.isEmpty else {
            logger.error("❌ [handleOpenUrl recovery] No code in mis-routed callback URL")
            self.reportOAuthFailure(
                error: FronteggError.authError(.failedToExtractCode),
                flow: self.activeEmbeddedOAuthFlow
            )
            self.setWebLoading(false)
            self.setIsLoading(false)
            self.activeEmbeddedOAuthFlow = .login
            setAppLink(false)
            return true
        }

        let redirectUri = generateRedirectUri(
            baseUrl: self.baseUrl,
            bundleIdentifier: currentAppBundleIdentifier()
        )

        let resolvedVerifier = CredentialManager.resolveCodeVerifier(
            for: oauthState,
            allowFallback: true
        )

        // Mirror the precedence in `createOauthCallbackHandler`: a missing
        // verifier means the token exchange would deterministically fail
        // with an opaque server error. Surface the consistent SDK error
        // (`codeVerifierNotFound` / `invalidOAuthState`) up front instead.
        guard resolvedVerifier.verifier != nil else {
            let authError = self.oauthCodeVerifierError(
                for: oauthState,
                resolution: resolvedVerifier
            )
            logger.error(
                "❌ [handleOpenUrl recovery] Missing code verifier for mis-routed callback " +
                "(state=\(oauthState ?? "nil"), hasPending=\(resolvedVerifier.hasPendingOAuthStates))"
            )
            self.reportOAuthFailure(
                error: FronteggError.authError(authError),
                flow: self.activeEmbeddedOAuthFlow
            )
            self.setWebLoading(false)
            self.setIsLoading(false)
            self.activeEmbeddedOAuthFlow = .login
            setAppLink(false)
            return true
        }

        logger.info(
            "🟢 [handleOpenUrl recovery] Exchanging mis-routed OAuth code via hosted login callback " +
            "(state=\(oauthState ?? "nil"), source=\(resolvedVerifier.source.rawValue), " +
            "hasVerifier=\(resolvedVerifier.verifier != nil))"
        )

        let completion: FronteggAuth.CompletionHandler = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let user):
                self.logger.info("✅ [handleOpenUrl recovery] Mis-routed OAuth callback exchanged successfully for user \(user.email)")
            case .failure(let error):
                self.logger.error("❌ [handleOpenUrl recovery] Mis-routed OAuth callback exchange failed: \(error.localizedDescription)")
            }
            if let existing = self.loginCompletion {
                self.loginCompletion = nil
                existing(result)
            }
            self.setAppLink(false)
        }

        self.handleHostedLoginCallback(
            code,
            resolvedVerifier.verifier,
            oauthState: oauthState,
            redirectUri: redirectUri,
            flow: self.activeEmbeddedOAuthFlow,
            completePendingFlowOnSuccess: true,
            matchedPendingOAuthState: resolvedVerifier.source == .stateMatch,
            completion: completion
        )

        return true
    }
}
