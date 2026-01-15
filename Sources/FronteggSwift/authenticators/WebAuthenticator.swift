//
//  FrontetggAuthentication.swift
//
//  Created by David Frontegg on 26/10/2022.
//

import AuthenticationServices
import UIKit


class WebAuthenticator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    static let shared = WebAuthenticator()
    
    weak var window: UIWindow? = nil
    var session: ASWebAuthenticationSession? = nil
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
       if Thread.isMainThread {
            return window ?? FronteggAuth.shared.getRootVC()?.view.window ?? ASPresentationAnchor()
        } else {
            var anchor: ASPresentationAnchor = ASPresentationAnchor()
            DispatchQueue.main.sync {
                anchor = window ?? FronteggAuth.shared.getRootVC()?.view.window ?? ASPresentationAnchor()
            }
            return anchor
        }
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        return true
    }
    
    
    var webAuthSession: ASWebAuthenticationSession?
    
    func start(_ websiteURL:URL, ephemeralSession: Bool = false, window:UIWindow? = nil, completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler) {
        if let lastSession = session {
            lastSession.cancel()
            session = nil
        }
        
        let bundleIdentifier = FronteggApp.shared.bundleIdentifier
        
        // Add breadcrumb for social login start
        SentryHelper.addBreadcrumb(
            "Starting ASWebAuthenticationSession for social login",
            category: "social_login",
            level: .info,
            data: [
                "url": websiteURL.absoluteString,
                "callbackScheme": bundleIdentifier,
                "ephemeralSession": ephemeralSession,
                "embeddedMode": FronteggApp.shared.embeddedMode
            ]
        )
        
        let webAuthSession = ASWebAuthenticationSession.init(
            url: websiteURL,
            callbackURLScheme: bundleIdentifier,
            completionHandler: { callbackUrl, error in
                // Log completion result
                if let error = error {
                    let nsError = error as NSError
                    if nsError.code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        SentryHelper.logError(error, context: [
                            "social_login": [
                                "url": websiteURL.absoluteString,
                                "callbackScheme": bundleIdentifier,
                                "ephemeralSession": ephemeralSession,
                                "embeddedMode": FronteggApp.shared.embeddedMode,
                                "errorCode": nsError.code,
                                "errorDomain": nsError.domain
                            ],
                            "error": [
                                "type": "social_login_redirect_failed"
                            ]
                        ])
                    }
                } else if callbackUrl == nil {
                    // This is the critical case: redirect failed but no error
                    SentryHelper.logMessage(
                        "Google Login fails to redirect to app in embeddedMode when Safari session exists",
                        level: .error,
                        context: [
                            "social_login": [
                                "url": websiteURL.absoluteString,
                                "callbackScheme": bundleIdentifier,
                                "ephemeralSession": ephemeralSession,
                                "embeddedMode": FronteggApp.shared.embeddedMode,
                                "callbackUrl": "nil"
                            ],
                            "error": [
                                "type": "social_login_redirect_failed",
                                "description": "Callback URL is nil - redirect to app failed"
                            ]
                        ]
                    )
                } else if let callbackUrl = callbackUrl {
                    // Callback happened, check if it contains code/error
                    let queryItems = getQueryItems(callbackUrl.absoluteString)
                    let queryKeys = Array((queryItems ?? [:]).keys).sorted()
                    let hasCode = queryItems?["code"] != nil
                    let hasError = queryItems?["error"] != nil
                    let allQueryParams = queryItems?.mapValues { $0 } ?? [:]
                    
                    // Log all callback details for debugging (not just errors)
                    let logger = getLogger("WebAuthenticator")
                    logger.info("🔍 [ASWebAuth] Callback URL received: \(callbackUrl.absoluteString)")
                    logger.info("🔍 [ASWebAuth] Callback scheme: \(callbackUrl.scheme ?? "nil"), host: \(callbackUrl.host ?? "nil"), path: \(callbackUrl.path)")
                    logger.info("🔍 [ASWebAuth] Query parameters: \(queryKeys.isEmpty ? "none" : queryKeys.joined(separator: ", "))")
                    logger.info("🔍 [ASWebAuth] Has code: \(hasCode), Has error: \(hasError)")
                    
                    // Log all query parameter values (with length info for sensitive data)
                    for (key, value) in allQueryParams {
                        let valueLength = value.count
                        let valuePreview = valueLength > 50 ? String(value.prefix(50)) + "..." : value
                        logger.info("🔍 [ASWebAuth]   - \(key): \(valuePreview) (length: \(valueLength))")
                    }
                    
                    if !hasCode && !hasError {
                        // Warning: callback URL exists but missing code/error (can cause silent loop back to login)
                        logger.warning("⚠️ [ASWebAuth] Callback URL exists but missing code/error parameters")
                        SentryHelper.logMessage(
                            "OAuth callback received without code (hosted)",
                            level: .warning,
                            context: [
                                "oauth": [
                                    "stage": "ASWebAuthenticationSession_completion",
                                    "url": websiteURL.absoluteString,
                                    "callbackScheme": bundleIdentifier,
                                    "ephemeralSession": ephemeralSession,
                                    "embeddedMode": FronteggApp.shared.embeddedMode,
                                    "callbackUrl": callbackUrl.absoluteString,
                                    "callbackQueryKeys": queryKeys,
                                    "queryParamCount": allQueryParams.count
                                ],
                                "error": [
                                    "type": "oauth_missing_code"
                                ]
                            ]
                        )
                    } else {
                        // Success - callback URL exists and has code or error parameter
                        logger.info("✅ [ASWebAuth] Callback URL contains \(hasCode ? "code" : "error") parameter")
                        SentryHelper.addBreadcrumb(
                            "Social login redirect successful",
                            category: "social_login",
                            level: .info,
                            data: [
                                "callbackUrl": callbackUrl.absoluteString,
                                "callbackScheme": callbackUrl.scheme ?? "nil",
                                "callbackHost": callbackUrl.host ?? "nil",
                                "callbackPath": callbackUrl.path,
                                "hasCode": hasCode,
                                "hasError": hasError,
                                "queryKeys": queryKeys,
                                "queryParamCount": allQueryParams.count,
                                "codeLength": queryItems?["code"]?.count ?? 0,
                                "errorValue": queryItems?["error"] ?? "nil"
                            ]
                        )
                    }
                }
                
                // Call original completion handler
                completionHandler(callbackUrl, error)
            })
        // Run the session
        webAuthSession.presentationContextProvider = self
        webAuthSession.prefersEphemeralWebBrowserSession = ephemeralSession
        
        
        self.window = window
        self.session = webAuthSession
        webAuthSession.start()
        
    }
    
}
