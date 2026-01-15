//
//  CustomWebView.swift
//  Created by David Frontegg on 24/10/2022.
//

import Foundation
import WebKit
import SwiftUI
import AuthenticationServices


class CustomWebView: WKWebView, WKNavigationDelegate, WKUIDelegate {
    var accessoryView: UIView?
    private let fronteggAuth: FronteggAuth = FronteggAuth.shared
    private let logger = getLogger("CustomWebView")
    private var lastResponseStatusCode: Int? = nil
    private var cachedUrlSchemes: [String]? = nil
    private var magicLinkRedirectUri: String? = nil
    private var previousUrl: URL? = nil
    private var isSocialLoginFlow: Bool = false
    
    
    override var inputAccessoryView: UIView? {
        // remove/replace the default accessory view
        return accessoryView
    }
    
    private static func isCancelledAsAuthenticationLoginError(_ error: Error) -> Bool {
        (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
    
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" {
                    if UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                        return nil
                    }
                }
                
                webView.load(navigationAction.request)
            }
        }
        
        return nil
    }
    
    func webView(_ _webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        weak var webView = _webView
        let url = navigationAction.request.url
        let urlString = url?.absoluteString ?? "no url"

        logger.trace("navigationAction check for \(urlString)")

        if let url = url {
            // Save current URL as previousUrl BEFORE processing, but only if it's not the same as the new URL
            // This ensures we track the URL we came FROM, not the URL we're going TO
            if let currentUrl = webView?.url, currentUrl.absoluteString != url.absoluteString {
                previousUrl = currentUrl
                logger.trace("Updated previousUrl to: \(currentUrl.absoluteString)")
            }
            
            if let host = url.host, (host.contains("localhost") || host.contains("127.0.0.1")) {
                logger.warning("⚠️ Blocking navigation to localhost: \(url.absoluteString)")
                
                if let prevUrl = previousUrl, prevUrl.path.contains("/postlogin/verify") {
                    logger.warning("Detected localhost redirect after /postlogin/verify. Previous URL: \(prevUrl.absoluteString), Current URL: \(url.absoluteString)")

                    if let urlComponents = URLComponents(url: prevUrl, resolvingAgainstBaseURL: false),
                       let queryItems = urlComponents.queryItems,
                       let type = queryItems.first(where: { $0.name == "type" })?.value {
                        logger.info("Retrying social login with provider: \(type) to avoid localhost redirect")
                        DispatchQueue.main.async { [weak self, weak webView] in
                            guard let self = self else { return }
                            self.fronteggAuth.handleSocialLogin(providerString: type, custom: false, action: .login) { result in
                                switch result {
                                case .success(let user):
                                    self.logger.info("✅ Social login completed successfully after blocking localhost redirect")
                                    self.fronteggAuth.loginCompletion?(.success(user))
                                    // Dismiss the webview
                                    if let presentingVC = VCHolder.shared.vc?.presentedViewController ?? VCHolder.shared.vc {
                                        presentingVC.dismiss(animated: true)
                                        VCHolder.shared.vc = nil
                                    }
                                case .failure(let error):
                                    self.logger.error("❌ Social login failed after blocking localhost redirect: \(error.localizedDescription)")
                                    self.fronteggAuth.loginCompletion?(.failure(error))
                                }
                            }
                        }
                        return .cancel
                    }
                }
                
                logger.warning("Blocking localhost navigation: \(url.absoluteString)")
                return .cancel
            }
            
            // Check if this is an external OIDC provider redirect (e.g., Auth0, Okta, Microsoft)
            // This happens when Frontegg server redirects to OIDC provider for SSO
            // We need to allow these external redirects to proceed in the web view
            // This check must be BEFORE custom scheme check to allow OIDC provider navigation
            let urlString = url.absoluteString
            if !urlString.starts(with: fronteggAuth.baseUrl) &&
               !urlString.starts(with: generateRedirectUri()) &&
               (urlString.contains("/authorize") || urlString.contains("/oauth/authorize") || 
                urlString.contains("auth0.com") || urlString.contains("okta.com") || 
                urlString.contains("login.microsoftonline.com") || urlString.contains("accounts.google.com")) {
                logger.info("Detected external OIDC provider redirect, allowing navigation: \(urlString)")
                return .allow
            }
            
            if let scheme = url.scheme, getAppURLSchemes().contains(scheme) {
                let appSchemes = getAppURLSchemes()
                logger.info("🔵 [Social Login Debug] Custom scheme detected: \(scheme)")
                logger.info("🔵 [Social Login Debug] All app URL schemes: \(appSchemes)")
                logger.info("🔵 [Social Login Debug] Custom scheme URL: \(url.absoluteString)")
                
                // Check if this is an OAuth callback with code - handle it directly instead of opening externally
                if let queryItems = getQueryItems(url.absoluteString), queryItems["code"] != nil {
                    logger.info("✅ [Social Login Debug] Detected custom scheme OAuth callback URL with code, handling as HostedLoginCallback")
                    logger.info("✅ [Social Login Debug] This is the expected redirect flow for social login")
                    return self.handleHostedLoginCallback(webView, url)
                } else {
                    logger.warning("⚠️ [Social Login Debug] Custom scheme URL detected but no code parameter found")
                    logger.warning("⚠️ [Social Login Debug] URL: \(url.absoluteString)")
                }
                
                // For other custom scheme URLs (without code), open externally
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:]) { success in
                        if success {
                            if let presentingVC = VCHolder.shared.vc?.presentedViewController ?? VCHolder.shared.vc {
                                presentingVC.dismiss(animated: true)
                                VCHolder.shared.vc = nil
                                FronteggAuth.shared.loginCompletion?(.failure(.authError(.operationCanceled)))
                            }
                        }
                    }
                }

                return .cancel
            }

            // Check if this is an intermediate redirect callback URL (magic link, forget password, unlock account, invite)
            // These flows use /oauth/account/redirect/iOS/{bundleId} or /oauth/account/redirect/iOS/{bundleId}/oauth/callback
            // This URL is detected as .loginRoutes but should be handled as HostedLoginCallback
            if url.path.contains("/oauth/account/redirect/iOS/") {
                logger.info("🔵 [Social Login Debug] Intermediate redirect URL detected: \(url.absoluteString)")
                if let queryItems = getQueryItems(url.absoluteString), queryItems["code"] != nil {
                    logger.info("✅ [Social Login Debug] Intermediate redirect callback URL with code, handling as HostedLoginCallback")
                    return self.handleHostedLoginCallback(webView, url)
                } else {
                    logger.warning("⚠️ [Social Login Debug] Intermediate redirect URL detected but no code parameter found")
                }
            }
            
            // Check if this is an OAuth callback URL with code parameter in /oauth/account/ path
            // This handles other flows that might use different paths
            // These URLs are detected as .loginRoutes but should be handled as HostedLoginCallback
            // EXCEPT for OIDC callback - we need to let the server redirect to custom scheme first
            if url.path.hasPrefix("/oauth/account/") {
                logger.info("🔵 [Social Login Debug] OAuth account path detected: \(url.path)")
                if url.path.contains("/oauth/account/oidc/callback") {
                    logger.info("🔵 [Social Login Debug] OIDC callback URL detected, allowing server to redirect to custom scheme")
                    logger.info("🔵 [Social Login Debug] OIDC callback URL: \(url.absoluteString)")
                    isSocialLoginFlow = true
                    return .allow
                }
                
                if let queryItems = getQueryItems(url.absoluteString), queryItems["code"] != nil {
                    // For other callback URLs (not OIDC), handle them directly
                    if url.path.contains("/callback") || url.path.contains("/redirect/") {
                        logger.info("✅ [Social Login Debug] OAuth callback URL with code in /oauth/account/ path, handling as HostedLoginCallback")
                        return self.handleHostedLoginCallback(webView, url)
                    }
                } else {
                    logger.warning("⚠️ [Social Login Debug] OAuth account path detected but no code parameter found: \(url.absoluteString)")
                }
            }

            // Check if this is a /postlogin/verify URL
            // IMPORTANT: If the URL has a token parameter (from app link), we must preserve it for device verification
            // Add missing redirect_uri and code_verifier_pkce parameters while preserving the token
            if url.path.contains("/postlogin/verify") {
                if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    var queryItems = urlComponents.queryItems ?? []
                    var needsUpdate = false
                    
                    let redirectUri = generateRedirectUri()
                    if !queryItems.contains(where: { $0.name == "redirect_uri" }) {
                        queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectUri))
                        needsUpdate = true
                        logger.info("Added redirect_uri to /postlogin/verify URL: \(redirectUri)")
                    }
                    
                    if let codeVerifier = CredentialManager.getCodeVerifier() {
                        if !queryItems.contains(where: { $0.name == "code_verifier_pkce" }) {
                            queryItems.append(URLQueryItem(name: "code_verifier_pkce", value: codeVerifier))
                            needsUpdate = true
                            logger.info("Added code_verifier_pkce to /postlogin/verify URL")
                        }
                    } else {
                        logger.warning("No code verifier found for /postlogin/verify URL - this may cause verification to fail")
                    }
                    
                    if needsUpdate {
                        urlComponents.queryItems = queryItems
                        if let updatedUrl = urlComponents.url {
                            logger.info("Updating /postlogin/verify URL with required parameters while preserving token: \(updatedUrl.absoluteString)")
                            DispatchQueue.main.async {
                                webView?.load(URLRequest(url: updatedUrl))
                            }
                            return .cancel
                        }
                    }
                }
            }
            
            // Check if this is a redirect to dashboard/tenant selection after social login
            // This happens when user already has an active session in Safari
            // After Google auth, server redirects to dashboard instead of callback URL
            if isSocialLoginFlow || 
               (previousUrl != nil && (
                   previousUrl!.path.contains("/oauth/account/social/success") ||
                   previousUrl!.path.contains("/oauth/account/redirect/ios/") ||
                   previousUrl!.path.contains("/oauth/account/oidc/callback")
               )) {
                // Check if current URL is a dashboard/tenant selection page
                let isDashboardOrTenantSelection = url.path.contains("/dashboard") ||
                                                   url.path.contains("/tenant") ||
                                                   (url.path == "/" && !url.path.contains("/oauth/") && !url.path.contains("/login"))
                
                if isDashboardOrTenantSelection && url.absoluteString.starts(with: fronteggAuth.baseUrl) {
                    logger.info("Detected redirect to dashboard/tenant selection after social login. Previous URL: \(previousUrl?.absoluteString ?? "nil"), Current URL: \(url.absoluteString)")
                    // This means the user is already authenticated, we should complete the login flow
                    // by checking if we have a valid session
                    DispatchQueue.main.async { [weak self, weak webView] in
                        guard let self = self else { return }
                        // Try to get user info to verify authentication
                        Task { [weak self, weak webView] in
                            guard let self = self else { return }
                            // Wait a bit for cookies to be set
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            
                            // First, try to extract cookies from WebView (this handles the case when user has active Safari session)
                            let (refreshTokenCookie, deviceTokenCookie) = await self.extractAuthCookiesFromWebView()
                            
                            if let refreshCookie = refreshTokenCookie {
                                // Extract just the token value from cookie string "name=value"
                                // Handle case where value might contain "=" by splitting only on first "="
                                let cookieParts = refreshCookie.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                                if cookieParts.count == 2 {
                                    let refreshToken = String(cookieParts[1])
                                    
                                    do {
                                        // Use requestAuthorizeAsync which handles token refresh and user loading
                                        // Pass device token cookie if available (extract value the same way)
                                        let deviceToken: String? = {
                                            if let deviceCookie = deviceTokenCookie {
                                                let deviceParts = deviceCookie.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                                                if deviceParts.count == 2 {
                                                    return String(deviceParts[1])
                                                } else {
                                                    self.logger.warning("Invalid device token cookie format: \(deviceCookie)")
                                                    return nil
                                                }
                                            } else {
                                                return nil
                                            }
                                        }()
                                        
                                        let user = try await self.fronteggAuth.requestAuthorizeAsync(refreshToken: refreshToken, deviceTokenCookie: deviceToken)
                                        // User is authenticated, complete login
                                        self.logger.info("User is authenticated after social login redirect using WebView cookies, completing login flow")
                                        await MainActor.run {
                                            self.fronteggAuth.loginCompletion?(.success(user))
                                            // Dismiss the webview
                                            if let presentingVC = VCHolder.shared.vc?.presentedViewController ?? VCHolder.shared.vc {
                                                presentingVC.dismiss(animated: true)
                                                VCHolder.shared.vc = nil
                                            }
                                        }
                                        return
                                    } catch {
                                        self.logger.warning("Authentication failed using WebView cookies: \(error), trying keychain fallback")
                                    }
                                } else {
                                    self.logger.warning("Invalid refresh token cookie format: \(refreshCookie), trying keychain fallback")
                                }
                            }
                            
                            // Fallback: Try to get refresh token from keychain
                            // Check if session per tenant is enabled and retrieve token accordingly
                            let config = try? PlistHelper.fronteggConfig()
                            let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
                            
                            var refreshToken: String? = nil
                            if enableSessionPerTenant {
                                // Try to get tenant-specific token
                                if let tenantId = self.fronteggAuth.credentialManager.getLastActiveTenantId() {
                                    refreshToken = try? self.fronteggAuth.credentialManager.getTokenForTenant(tenantId: tenantId, tokenType: .refreshToken)
                                    if refreshToken != nil {
                                        self.logger.info("Found tenant-specific refresh token for tenant: \(tenantId)")
                                    }
                                } else {
                                    // No tenant ID stored yet, tokens might not be saved - will try legacy lookup as last resort
                                    self.logger.info("No tenant ID stored, trying legacy keychain lookup as fallback")
                                }
                                
                                // If tenant-specific lookup failed, try legacy global key (for backward compatibility during transition)
                                if refreshToken == nil {
                                    refreshToken = try? self.fronteggAuth.credentialManager.get(key: KeychainKeys.refreshToken.rawValue)
                                    if refreshToken != nil {
                                        self.logger.info("Found refresh token in legacy global keychain location")
                                    }
                                }
                            } else {
                                // Legacy behavior: use global key
                                refreshToken = try? self.fronteggAuth.credentialManager.get(key: KeychainKeys.refreshToken.rawValue)
                            }
                            
                            if let refreshToken = refreshToken {
                                do {
                                    // Use requestAuthorizeAsync which handles token refresh and user loading
                                    let user = try await self.fronteggAuth.requestAuthorizeAsync(refreshToken: refreshToken)
                                    // User is authenticated, complete login
                                    self.logger.info("User is authenticated after social login redirect using keychain token, completing login flow")
                                    await MainActor.run {
                                        self.fronteggAuth.loginCompletion?(.success(user))
                                        // Dismiss the webview
                                        if let presentingVC = VCHolder.shared.vc?.presentedViewController ?? VCHolder.shared.vc {
                                            presentingVC.dismiss(animated: true)
                                            VCHolder.shared.vc = nil
                                        }
                                    }
                                } catch {
                                    // Refresh failed, reload login page
                                    self.logger.warning("Token refresh failed after social login redirect: \(error), reloading login page")
                                    let (loginUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                                    CredentialManager.saveCodeVerifier(codeVerifier)
                                    await MainActor.run {
                                        webView?.load(URLRequest(url: loginUrl))
                                    }
                                }
                            } else {
                                // No cookies and no refresh token, reload login page
                                self.logger.warning("No authentication cookies or refresh token found after social login redirect, reloading login page")
                                let (loginUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                                CredentialManager.saveCodeVerifier(codeVerifier)
                                await MainActor.run {
                                    webView?.load(URLRequest(url: loginUrl))
                                }
                            }
                        }
                    }
                    isSocialLoginFlow = false
                    return .cancel
                }
            }
            
            let urlType = getOverrideUrlType(url: url)
            logger.info("urlType: \(urlType)")

            switch urlType {
            case .HostedLoginCallback:
                // Check if this is unlock account flow - custom scheme URL without code after unlock
                // In unlock account flow, after unlock, server redirects to /oauth/account/redirect/iOS/{bundleId}
                // (without code), then redirects to custom scheme URL (also without code)
                // In this case, we should just allow the user to login normally, not treat it as OAuth callback
                let urlScheme = url.scheme ?? ""
                let appSchemes = getAppURLSchemes()
                let isCustomScheme = !urlScheme.isEmpty && (appSchemes.contains(urlScheme) || !urlScheme.hasPrefix("http"))
                let queryItems = getQueryItems(url.absoluteString)
                let hasCode = queryItems?["code"] != nil
                
                logger.info("HostedLoginCallback check - urlScheme: \(urlScheme), appSchemes: \(appSchemes), isCustomScheme: \(isCustomScheme), hasCode: \(hasCode), previousUrl: \(previousUrl?.absoluteString ?? "nil"), magicLinkRedirectUri: \(magicLinkRedirectUri ?? "nil")")
                
                if isCustomScheme && !hasCode {
                    logger.info("Custom scheme URL without code detected. Previous URL: \(previousUrl?.absoluteString ?? "nil"), magicLinkRedirectUri: \(magicLinkRedirectUri ?? "nil")")
                    
                    // Check if magicLinkRedirectUri was set but URL doesn't have code
                    // This indicates unlock account flow or similar flow that doesn't use OAuth callback
                    // We check this FIRST because it's the most reliable indicator
                    if magicLinkRedirectUri != nil {
                        // Also check if previous URL was intermediate redirect without code
                        var shouldIgnore = false
                        if let prevUrl = previousUrl {
                            // If previous URL was intermediate redirect without code, definitely unlock account flow
                            let prevHasCode = getQueryItems(prevUrl.absoluteString)?["code"] != nil
                            shouldIgnore = prevUrl.path.contains("/oauth/account/redirect/iOS/") && !prevHasCode
                            logger.info("Previous URL check - path contains /oauth/account/redirect/iOS/: \(prevUrl.path.contains("/oauth/account/redirect/iOS/")), prevHasCode: \(prevHasCode), shouldIgnore: \(shouldIgnore)")
                        } else {
                            // If no previous URL but magicLinkRedirectUri is set, likely unlock account flow
                            shouldIgnore = true
                            logger.info("No previous URL but magicLinkRedirectUri is set, shouldIgnore: true")
                        }
                        
                        if shouldIgnore {
                            logger.info("Detected unlock account flow completion - custom scheme URL without code after intermediate redirect, allowing normal login")
                            // Clear magicLinkRedirectUri as it's not needed for unlock account flow
                            magicLinkRedirectUri = nil
                            previousUrl = nil
                            // Reset webview to initial state by loading fresh login page
                            // This ensures the app returns to initial state after unlock account flow
                            DispatchQueue.main.async {
                                let (loginUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                                CredentialManager.saveCodeVerifier(codeVerifier)
                                webView?.load(URLRequest(url: loginUrl))
                            }
                            return .cancel
                        }
                    }
                    
                    // Check if we came directly from unlock account flow
                    if let prevUrl = previousUrl, prevUrl.path.contains("/oauth/account/unlock") {
                        logger.info("Detected unlock account flow completion - custom scheme URL without code after unlock, allowing normal login")
                        // Clear magicLinkRedirectUri as it's not needed for unlock account flow
                        magicLinkRedirectUri = nil
                        previousUrl = nil
                        // Reset webview to initial state by loading fresh login page
                        // This ensures the app returns to initial state after unlock account flow
                        DispatchQueue.main.async {
                            let (loginUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                            CredentialManager.saveCodeVerifier(codeVerifier)
                            webView?.load(URLRequest(url: loginUrl))
                        }
                        return .cancel
                    }
                }
                return self.handleHostedLoginCallback(webView, url)
            case .SocialOauthPreLogin:
                isSocialLoginFlow = true
                return self.setSocialLoginRedirectUri(webView, url)
            default:
                return .allow
            }
        } else {
            logger.warning("failed to get url from navigationAction")
            self.fronteggAuth.setWebLoading(false)
            return .allow
        }
    }
    
    private func getAppURLSchemes() -> [String] {
        
        if let schemes = cachedUrlSchemes {
            return schemes
        }
        
        guard
            let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]]
        else {
            cachedUrlSchemes = []
            return []
        }

        cachedUrlSchemes = urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
        return cachedUrlSchemes ?? []
    }
    
    /// Extracts authentication cookies (fe_refresh and fe_device) from WebView's cookie store
    /// Returns tuple of (refreshTokenCookie, deviceTokenCookie) where cookies are in format "name=value"
    private func extractAuthCookiesFromWebView() async -> (String?, String?) {
        guard let webView = self as? WKWebView else {
            logger.warning("Cannot extract cookies: webView is not available")
            return (nil, nil)
        }
        
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let baseUrlHost = URL(string: fronteggAuth.baseUrl)?.host
        
        // Fetch all cookies
        let cookies: [HTTPCookie] = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        
        // Filter cookies for the base URL domain
        // Cookie domain can be in format ".example.com" (with leading dot) or "example.com"
        let relevantCookies = cookies.filter { cookie in
            guard let host = baseUrlHost else { return true }
            let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return cookieDomain == host || host.hasSuffix(".\(cookieDomain)") || cookieDomain.hasSuffix(".\(host)")
        }
        
        // Find fe_refresh cookie (pattern: fe_refresh_*)
        let refreshCookie = relevantCookies.first { cookie in
            cookie.name.hasPrefix("fe_refresh")
        }
        
        // Find fe_device cookie (pattern: fe_device_*)
        let deviceCookie = relevantCookies.first { cookie in
            cookie.name.hasPrefix("fe_device")
        }
        
        let refreshTokenCookie = refreshCookie.map { "\($0.name)=\($0.value)" }
        let deviceTokenCookie = deviceCookie.map { "\($0.name)=\($0.value)" }
        
        if refreshTokenCookie != nil {
            logger.info("Extracted refresh token cookie from WebView: \(refreshCookie!.name)")
        } else {
            logger.warning("No refresh token cookie found in WebView")
        }
        
        if deviceTokenCookie != nil {
            logger.info("Extracted device token cookie from WebView: \(deviceCookie!.name)")
        }
        
        return (refreshTokenCookie, deviceTokenCookie)
    }

    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logger.trace("didStartProvisionalNavigation")
        if let url = webView.url {
            let urlType = getOverrideUrlType(url: url)
            
            logger.info("urlType: \(urlType)")
            
            // Update previousUrl for tracking unlock account flow
            previousUrl = url
            
            if(urlType != .SocialOauthPreLogin &&
               urlType != .Unknown){
                
                if(fronteggAuth.webLoading == false) {
                    fronteggAuth.setWebLoading(true)
                }
            }
        } else {
            logger.warning("failed to get url from didStartProvisionalNavigation()")
            self.fronteggAuth.setWebLoading(false)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.trace("didFinish")
        if let url = webView.url {
            let urlType = getOverrideUrlType(url: url)
            logger.info("urlType: \(urlType), for: \(url.absoluteString)")
            
            // Update previousUrl for tracking unlock account flow
            previousUrl = url
            
            // Track magic link intermediate redirect URL
            // For magic link flow, the server redirects to /oauth/account/redirect/iOS/{bundleId}?code=...
            // We need to use this URL as redirect_uri for token exchange, not the custom scheme
            // BUT: For unlock account flow, the server redirects to /oauth/account/redirect/iOS/{bundleId} WITHOUT code
            // In this case, we should NOT set magicLinkRedirectUri, as it's not an OAuth callback
            if urlType == .loginRoutes && url.path.contains("/oauth/account/redirect/iOS/") {
                // Check if this is unlock account flow (no code parameter) or magic link flow (with code)
                let queryItems = getQueryItems(url.absoluteString)
                let hasCode = queryItems?["code"] != nil
                
                if hasCode {
                    // This is magic link flow - extract redirect_uri from this intermediate URL (without query parameters)
                    if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        var redirectUriComponents = URLComponents()
                        redirectUriComponents.scheme = urlComponents.scheme
                        redirectUriComponents.host = urlComponents.host
                        redirectUriComponents.path = urlComponents.path
                        if let redirectUri = redirectUriComponents.url {
                            self.magicLinkRedirectUri = redirectUri.absoluteString
                            logger.trace("Detected magic link redirect_uri: \(self.magicLinkRedirectUri!)")
                        }
                    }
                } else {
                    // This is unlock account flow - clear any existing magicLinkRedirectUri and reset state
                    // After unlock account, the user should be able to login normally, so we clear state
                    logger.info("Detected unlock account flow intermediate redirect (no code) - clearing state to allow normal login")
                    self.magicLinkRedirectUri = nil
                    // Don't clear previousUrl here - we need it to detect unlock account flow in decidePolicyFor
                }
            }
            
            if(urlType == .internalRoutes ) {
                if url.path.contains("/postlogin/verify") {
                    let redirectUri = generateRedirectUri()
                    if url.absoluteString.starts(with: redirectUri) {
                        return
                    }
                    
                   webView.evaluateJavaScript("""
                        (function() {
                            // Check for meta refresh redirect
                            var metaRefresh = document.querySelector('meta[http-equiv="refresh"]');
                            if (metaRefresh) {
                                var content = metaRefresh.getAttribute('content');
                                if (content) {
                                    var match = content.match(/url=(.+)/i);
                                    if (match) return 'META_REDIRECT:' + match[1];
                                }
                            }
                            // Check for window.location redirect
                            if (window.location.href !== '\(url.absoluteString)') {
                                return 'JS_REDIRECT:' + window.location.href;
                            }
                            return null;
                        })()
                    """) { [weak self] result, error in
                        if let redirectInfo = result as? String {
                            self?.logger.info("🔐 Detected redirect in verification page: \(redirectInfo)")
                            print("🔐 Frontegg Verification page redirect: \(redirectInfo)")
                        }
                    }
                }
                
                logger.trace("hiding Loader screen after 300ms")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // usually internal routes are redirects
                    // this 500ms will prevent loader blinking
                    self.fronteggAuth.setWebLoading(false)
                }

            }
            if urlType == .loginRoutes || urlType == .Unknown {
                logger.info("hiding Loader screen")
                if(fronteggAuth.webLoading) {
                    fronteggAuth.setWebLoading(false)
                }
            } else if let statusCode = self.lastResponseStatusCode {
                self.lastResponseStatusCode = nil;
                self.fronteggAuth.setWebLoading(false)
                
                if(url.absoluteString.starts(with: "\(fronteggAuth.baseUrl)/oauth/authorize")){
                    self.fronteggAuth.setWebLoading(false)
                    let encodedUrl = url.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
                    let reloadScript = "setTimeout(()=>window.location.href=\"\(encodedUrl)\", 4000)"
                    let jsCode = "(function(){\n" +
                            "                var script = document.createElement('script');\n" +
                            "                script.innerHTML=`\(reloadScript)`;" +
                            "                document.body.appendChild(script)\n" +
                            "            })()"
                    webView.evaluateJavaScript(jsCode)
                    logger.error("Failed to load page \(encodedUrl), status: \(statusCode)")
                    
                    return
                }
                
                // Try to extract error message from response body
                webView.evaluateJavaScript("""
                    (function() {
                        try {
                            var bodyText = document.body.innerText || document.body.textContent || '';
                            if (bodyText) {
                                try {
                                    var json = JSON.parse(bodyText);
                                    if (json.errors && Array.isArray(json.errors)) {
                                        return json.errors.join('\\n');
                                    }
                                    if (json.error) {
                                        return json.error;
                                    }
                                    if (json.message) {
                                        return json.message;
                                    }
                                } catch(e) {
                                    // Not JSON, return raw text
                                    return bodyText.substring(0, 500);
                                }
                            }
                            return 'Unknown error occured';
                        } catch(e) {
                            return 'Unknown error occured';
                        }
                    })()
                """) { [self] res, err in
                    let errorMessage = res as? String ?? "Unknown error occured"
                    
                    self.fronteggAuth.setWebLoading(false)
                    let content = generateErrorPage(message: errorMessage, url: url.absoluteString, status: statusCode);
                    webView.loadHTMLString(content, baseURL: nil);
                }
            }
        } else {
            logger.warning("failed to get url from didFinishNavigation()")
            self.fronteggAuth.setWebLoading(false)
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        
        if let response = navigationResponse.response as? HTTPURLResponse {
            if response.statusCode >= 400 && response.statusCode != 500, let url = response.url {
                let urlType = getOverrideUrlType(url: url)
                logger.info("urlType: \(urlType), for: \(url.absoluteString)")
                
                if(urlType == .internalRoutes){
                    self.lastResponseStatusCode = response.statusCode
                    decisionHandler(.allow)
                    return
                }
            }
        }
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError _error: Error) {
        let error = _error as NSError
        let statusCode = error.code
        if(statusCode==102){
            // interrupted by frontegg webview
            return;
        }
        
        let errorMessage = error.localizedDescription;
        let url = "\(error.userInfo["NSErrorFailingURLKey"] ?? "")"
        logger.error("Failed to load page: \(errorMessage), status: \(statusCode), \(error)")
        
        
        self.fronteggAuth.setWebLoading(false)
        let content = generateErrorPage(message: errorMessage, url: url, status: statusCode);
        webView.loadHTMLString(content, baseURL: nil);
        
    }
    
    
    private func handleHostedLoginCallback(_ webView: WKWebView?, _ url: URL) -> WKNavigationActionPolicy {
        let expectedRedirectUri = generateRedirectUri()
        logger.info("🔵 [Social Login Debug] Received URL: \(url.absoluteString)")
        logger.info("🔵 [Social Login Debug] Expected redirect_uri: \(expectedRedirectUri)")
        logger.info("🔵 [Social Login Debug] URL scheme: \(url.scheme ?? "nil")")
        logger.info("🔵 [Social Login Debug] URL host: \(url.host ?? "nil")")
        logger.info("🔵 [Social Login Debug] URL path: \(url.path)")
        logger.info("🔵 [Social Login Debug] URL query: \(url.query ?? "nil")")
        logger.info("🔵 [Social Login Debug] Previous URL: \(previousUrl?.absoluteString ?? "nil")")
        logger.info("🔵 [Social Login Debug] Magic link redirect URI: \(magicLinkRedirectUri ?? "nil")")
        logger.info("🔵 [Social Login Debug] App URL schemes: \(getAppURLSchemes())")
        logger.info("🔵 [Social Login Debug] Is custom scheme match: \(getAppURLSchemes().contains(url.scheme ?? ""))")
        logger.info("🔵 [Social Login Debug] URL matches expected redirect URI: \(url.absoluteString.starts(with: expectedRedirectUri))")
        
        let queryItems = getQueryItems(url.absoluteString)
        let code = queryItems?["code"]
        guard let code = code else {
            logger.error("❌ [Social Login Debug] Failed to extract code from callback URL")
            logger.error("❌ [Social Login Debug] URL without code parameter. Full URL: \(url.absoluteString)")
            logger.warning("URL without code parameter detected. Previous URL: \(previousUrl?.absoluteString ?? "nil"), magicLinkRedirectUri: \(magicLinkRedirectUri ?? "nil")")

            let keys = Array((queryItems ?? [:]).keys).sorted()
            SentryHelper.logMessage(
                "OAuth callback without code detected (embedded webview)",
                level: .warning,
                context: [
                    "oauth": [
                        "stage": "handleHostedLoginCallback",
                        "url": url.absoluteString,
                        "expectedRedirectUri": expectedRedirectUri,
                        "previousUrl": previousUrl?.absoluteString ?? "nil",
                        "magicLinkRedirectUri": magicLinkRedirectUri ?? "nil",
                        "queryKeys": keys
                    ],
                    "error": [
                        "type": "oauth_missing_code"
                    ]
                ]
            )

            logger.info("Restarting the process by generating a new authorize url")
            let (url, codeVerifier) = AuthorizeUrlGenerator().generate()
            CredentialManager.saveCodeVerifier(codeVerifier)
            _ = webView?.load(URLRequest(url: url))
            return .cancel
        }
        
        // For magic link and similar flows (forget password, unlock account, invite), the server uses 
        // an intermediate redirect URL (/oauth/account/redirect/iOS/{bundleId} or /oauth/account/redirect/iOS/{bundleId}/oauth/callback)
        // We need to use this intermediate URL as redirect_uri for token exchange, not the custom scheme
        // Check if this is an intermediate redirect callback by examining the URL path
        var redirectUri: String
        var isMagicLink: Bool
        
        // Check if URL contains /oauth/account/redirect/iOS/ - this indicates an intermediate redirect
        // (used for magic link, forget password, unlock account, invite flows)
        if url.path.contains("/oauth/account/redirect/iOS/") {
            logger.info("🔵 [Social Login Debug] Detected intermediate redirect URL (magic link flow)")
            // This is an intermediate redirect callback - extract redirect_uri from the URL itself (without query parameters)
            isMagicLink = true
            if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var redirectUriComponents = URLComponents()
                redirectUriComponents.scheme = urlComponents.scheme
                redirectUriComponents.host = urlComponents.host
                redirectUriComponents.path = urlComponents.path
                if let extractedRedirectUri = redirectUriComponents.url {
                    redirectUri = extractedRedirectUri.absoluteString
                    logger.info("🔵 [Social Login Debug] Extracted intermediate redirect_uri: \(redirectUri)")
                } else {
                    // Fallback to cached value or default
                    redirectUri = magicLinkRedirectUri ?? generateRedirectUri()
                    logger.warning("⚠️ [Social Login Debug] Failed to extract redirect_uri from URL, using fallback: \(redirectUri)")
                }
            } else {
                redirectUri = magicLinkRedirectUri ?? generateRedirectUri()
                logger.warning("⚠️ [Social Login Debug] Failed to parse URL components, using fallback: \(redirectUri)")
            }
        } else if url.path.contains("/oauth/account/oidc/callback") {
            logger.info("🔵 [Social Login Debug] Detected OIDC callback URL")
            // OIDC callback - use standard redirect_uri (custom scheme) for token exchange
            // In hosted mode, ASWebAuthenticationSession callback comes through custom scheme URL
            // In embedded mode, callback comes through HTTPS URL, but we still need to use standard redirect_uri
            // The OIDC callback URL is an intermediate redirect from OIDC provider back to Frontegg,
            // but for token exchange we need to use the original redirect_uri from the authorize request to Frontegg
            // (the same redirect_uri that was used in the initial authorize request, not the OIDC provider's redirect_uri)
            isMagicLink = false
            redirectUri = generateRedirectUri()
            logger.info("🔵 [Social Login Debug] Using standard redirect_uri for OIDC token exchange: \(redirectUri)")
        } else {
            logger.info("🔵 [Social Login Debug] Detected regular OAuth callback URL")
            // Regular OAuth callback - use cached magic link redirect_uri if available, otherwise use standard one
            redirectUri = magicLinkRedirectUri ?? generateRedirectUri()
            isMagicLink = magicLinkRedirectUri != nil
            logger.info("🔵 [Social Login Debug] Regular OAuth callback - using redirect_uri: \(redirectUri), isMagicLink: \(isMagicLink)")
        }
        
        // For magic link flow, the server generates code without PKCE, so we shouldn't send code_verifier
        // For regular OAuth flow, we need code_verifier for PKCE
        // For social SSO flows, the verifier is stored in webview localStorage, not CredentialManager
        // Note: We check isMagicLink first (line 819), so magic link flows won't be misidentified as social login
        // Social login is detected by: isSocialLoginFlow flag OR OIDC callback path
        // We don't check for general /oauth/account/ paths to avoid false positives with magic link flows
        let isSocialLogin = isSocialLoginFlow || url.path.contains("/oauth/account/oidc/callback")
        
        logger.info("🔵 [Social Login Debug] Final redirect_uri for token exchange: \(redirectUri)")
        logger.info("🔵 [Social Login Debug] Is magic link flow: \(isMagicLink)")
        logger.info("🔵 [Social Login Debug] Is social login flow: \(isSocialLogin)")
        
        // Clear the magic link redirect_uri after using it
        magicLinkRedirectUri = nil
        
        self.fronteggAuth.setWebLoading(true)
        DispatchQueue.global(qos: .userInitiated).async {
            Task { @MainActor in
                // Retrieve code_verifier based on flow type
                let codeVerifier: String?
                if isMagicLink {
                    codeVerifier = nil
                } else if isSocialLogin {
                    // For social SSO flows, read verifier from webview localStorage
                    // The verifier is generated and stored by the hosted login page in localStorage
                    // and is NOT saved to CredentialManager (to avoid conflicts with main OAuth flow)
                    do {
                        let verifier = try await SocialLoginUrlGenerator.getCodeVerifierFromWebview()
                        self.logger.info("🔵 [Social Login Debug] Retrieved code_verifier from webview localStorage for social login (length: \(verifier.count))")
                        codeVerifier = verifier
                    } catch {
                        self.logger.warning("⚠️ [Social Login Debug] Failed to get code_verifier from webview for social login: \(error). Falling back to CredentialManager.")
                        codeVerifier = CredentialManager.getCodeVerifier()
                    }
                } else {
                    // For regular OAuth flow, use CredentialManager
                    codeVerifier = CredentialManager.getCodeVerifier()
                }
                
                self.logger.info("🔵 [Social Login Debug] Code verifier present: \(codeVerifier != nil ? "yes" : "no")")
                self.logger.trace("Using redirect_uri: \(redirectUri), isMagicLink: \(isMagicLink), codeVerifier: \(codeVerifier != nil ? "provided" : "nil")")
                
                FronteggAuth.shared.handleHostedLoginCallback(code, codeVerifier, redirectUri: redirectUri) { res in
                    switch (res) {
                    case .success(_):
                        let logger = getLogger("CustomWebView")
                        logger.info("Authentication succeeded")
                        self.isSocialLoginFlow = false
                        
                    case .failure(let error):
                        print("Error \(error)")
                        self.isSocialLoginFlow = false
                        let (url, codeVerifier)  = AuthorizeUrlGenerator().generate()
                        CredentialManager.saveCodeVerifier(codeVerifier)
                        DispatchQueue.main.async {
                            _ = webView?.load(URLRequest(url: url))
                        }
                    }
                    FronteggAuth.shared.loginCompletion?(res)
                }
            }
        }
        return .cancel
    }
    
    
    private func setSocialLoginRedirectUri(_ _webView:WKWebView?, _ url:URL) -> WKNavigationActionPolicy {
        
        weak var webView = _webView
        let expectedRedirectUri = generateRedirectUri()
        logger.info("🔵 [Social Login Debug] setSocialLoginRedirectUri called")
        logger.info("🔵 [Social Login Debug] Social login pre-auth URL: \(url.absoluteString)")
        logger.info("🔵 [Social Login Debug] Expected redirect URI to be added: \(expectedRedirectUri)")
        
        let queryItems = [
            URLQueryItem(name: "redirectUri", value: generateRedirectUri())
        ]
        var urlComps = URLComponents(string: url.absoluteString)!
        
        let filteredQueryItems = urlComps.queryItems?.filter {
            $0.name == "redirectUri"
        } ?? []
        
        
        urlComps.queryItems = filteredQueryItems + queryItems
        
        let finalUrl = urlComps.url!
        logger.info("🔵 [Social Login Debug] Added redirectUri to social login auth URL")
        logger.info("🔵 [Social Login Debug] Final social login URL with redirect_uri: \(finalUrl.absoluteString)")
        logger.trace("added redirectUri to socialLogin auth url \(finalUrl)")
        
        let followUrl = finalUrl
        DispatchQueue.global(qos: .userInitiated).sync {
            
            var request = URLRequest(url: followUrl)
            request.httpMethod = "GET"
            
            let noRedirectDelegate = NoRedirectSessionDelegate()
            let noRedirectSession = URLSession(configuration: .default, delegate: noRedirectDelegate, delegateQueue: nil)
            
            let task = noRedirectSession.dataTask(with: request) { (data, response, error) in
                // Check for errors
                if let error = error {
                    return
                }
                
                // Check for valid HTTP response
                if let httpResponse = response as? HTTPURLResponse {
                    if let location = httpResponse.value(forHTTPHeaderField: "Location"),
                       let socialLoginUrl = URL(string: location) {
                        if socialLoginUrl.host == "appleid.apple.com" || socialLoginUrl.absoluteString.contains("appleid.apple.com") {
                            // Check if this is form_post (Apple login specific)
                            if socialLoginUrl.absoluteString.contains("response_mode=form_post") {
                                // For form_post, Apple sends POST to backend, so we need to load URL in WebView
                                // to allow backend to process the POST and redirect properly
                                DispatchQueue.main.async {
                                    _ = webView?.load(URLRequest(url: socialLoginUrl))
                                }
                            } else {
                                self.handleSocialLoginRedirectToBrowser(webView, socialLoginUrl)
                            }
                        } else {
                            // Not Apple URL, use normal flow
                            self.handleSocialLoginRedirectToBrowser(webView, socialLoginUrl)
                        }
                    }
                }
            }
            task.resume()
        }
        
        return .cancel
    }
    
    private func startExternalBrowser(_ _webView:WKWebView?, _ url:URL, _ ephemeralSession:Bool = true) -> Void {
        
        weak var webView = _webView
        
        WebAuthenticator.shared.start(url, ephemeralSession: ephemeralSession, window: self.window) { callbackUrl, error  in
            if(error != nil){
                if(CustomWebView.isCancelledAsAuthenticationLoginError(error!)){
                    // Social login authentication canceled
                }else {
                    SentryHelper.logError(error!, context: [
                        "social_login": [
                            "url": url.absoluteString,
                            "ephemeralSession": ephemeralSession,
                            "embeddedMode": FronteggApp.shared.embeddedMode,
                            "stage": "external_browser_callback"
                        ],
                        "error": [
                            "type": "social_login_error"
                        ]
                    ])
                    
                    let (newUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                    CredentialManager.saveCodeVerifier(codeVerifier)
                    _ = webView?.load(URLRequest(url: newUrl))
                }
            }else if (callbackUrl == nil){
                // Critical: callback URL is nil - redirect failed
                SentryHelper.logMessage(
                    "Google Login fails to redirect to app in embeddedMode when Safari session exists - callbackUrl is nil",
                    level: .error,
                    context: [
                        "social_login": [
                            "url": url.absoluteString,
                            "ephemeralSession": ephemeralSession,
                            "embeddedMode": FronteggApp.shared.embeddedMode,
                            "stage": "external_browser_callback",
                            "callbackUrl": "nil"
                        ],
                        "error": [
                            "type": "social_login_redirect_failed",
                            "description": "Callback URL is nil in startExternalBrowser - redirect to app failed"
                        ]
                    ]
                )
                
                let (newUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                CredentialManager.saveCodeVerifier(codeVerifier)
                _ = webView?.load(URLRequest(url: newUrl))
                
            }else {
                if let callbackUrl = callbackUrl {
                    let queryItems = getQueryItems(callbackUrl.absoluteString)
                    let hasCode = queryItems?["code"] != nil
                    let hasError = queryItems?["error"] != nil
                    if !hasCode && !hasError {
                        let keys = Array((queryItems ?? [:]).keys).sorted()
                        SentryHelper.logMessage(
                            "Social login callback returned without code (embedded external browser)",
                            level: .warning,
                            context: [
                                "social_login": [
                                    "url": url.absoluteString,
                                    "embeddedMode": FronteggApp.shared.embeddedMode,
                                    "ephemeralSession": ephemeralSession,
                                    "stage": "external_browser_callback",
                                    "callbackUrl": callbackUrl.absoluteString,
                                    "callbackQueryKeys": keys
                                ],
                                "error": [
                                    "type": "social_login_missing_code"
                                ]
                            ]
                        )
                    }
                }

                if let socialLoginUrl = FronteggAuth.shared.handleSocialLoginCallback(callbackUrl!) {
                    _ = webView?.load(URLRequest(url: socialLoginUrl))
                } else {
                    let components = URLComponents(url: callbackUrl!, resolvingAgainstBaseURL: false)!
                    if let query = components.query, !query.isEmpty {
                        let resultUrl = URL(string: "\(FronteggAuth.shared.baseUrl)/oauth/account/social/success?\(query)")!
                        _ = webView?.load(URLRequest(url: resultUrl))
                    }
                }
            }
        }
    }
    
    private func handleSocialLoginRedirectToBrowser(_ _webView:WKWebView?, _ socialLoginUrl:URL) -> Void {
        
        weak var webView = _webView
        logger.trace("handleSocialLoginRedirectToBrowser()")
        
        let queryItems = [
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        var urlComps = URLComponents(string: socialLoginUrl.absoluteString)!
        urlComps.queryItems = (urlComps.queryItems ?? []) + queryItems
        
        let url = urlComps.url!
        
        // Use async dispatch to avoid deadlock if already on main thread
        if Thread.isMainThread {
            self.startExternalBrowser(webView, url)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startExternalBrowser(webView, url)
            }
        }
    }
    
    
    
    private func openExternalBrowser(_ _webView:WKWebView?, _ url:URL) -> WKNavigationActionPolicy {
        weak var webView = _webView
        self.startExternalBrowser(webView, url, true)
        return .cancel
    }
    
    override open var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
