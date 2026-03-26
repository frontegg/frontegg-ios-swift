//
//  FrontetggAuthentication.swift
//
//  Created by David Frontegg on 26/10/2022.
//

import AuthenticationServices
import UIKit
import WebKit


class WebAuthenticator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    static let shared = WebAuthenticator()
    
    weak var window: UIWindow? = nil
    var session: ASWebAuthenticationSession? = nil
#if DEBUG
    private var testingSession: TestingWebAuthenticationSession?
#endif
    
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
#if DEBUG
        testingSession?.cancel()
        testingSession = nil
#endif
        
        let bundleIdentifier = FronteggApp.shared.bundleIdentifier

        #if DEBUG
        if FronteggRuntime.allowsTestingWebAuthenticationTransport {
            self.window = window
            let testingSession = TestingWebAuthenticationSession(
                websiteURL: websiteURL,
                callbackURLScheme: bundleIdentifier,
                presenter: resolvedPresenter(window: window),
                ephemeralSession: ephemeralSession
            ) { [weak self] callbackUrl, error in
                self?.testingSession = nil
                completionHandler(callbackUrl, error)
            }
            self.testingSession = testingSession
            testingSession.start()
            return
        }
        #endif
        
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
        let didStart = webAuthSession.start()
        let logger = getLogger("WebAuthenticator")
        FronteggRuntime.testingLog(
            "WebAuthenticator.start url=\(websiteURL.absoluteString) didStart=\(didStart) hasWindow=\(window != nil) hasRootWindow=\(FronteggAuth.shared.getRootVC()?.view.window != nil)"
        )
        logger.info("ASWebAuthenticationSession start result: \(didStart), hasWindow: \(window != nil), hasRootWindow: \(FronteggAuth.shared.getRootVC()?.view.window != nil)")
        if !didStart {
            self.session = nil
            completionHandler(
                nil,
                NSError(
                    domain: "WebAuthenticator",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "ASWebAuthenticationSession failed to start",
                    ]
                )
            )
        }
        
    }

    private func resolvedPresenter(window: UIWindow?) -> UIViewController? {
        if let root = window?.rootViewController {
            return root.presentedViewController ?? root
        }
        if let root = FronteggAuth.shared.getRootVC(true) {
            return root.presentedViewController ?? root
        }
        if let root = FronteggAuth.shared.getRootVC() {
            return root.presentedViewController ?? root
        }
        return nil
    }
    
}

#if DEBUG
private final class TestingWebAuthenticationSession: NSObject, WKNavigationDelegate {
    private let websiteURL: URL
    private let callbackURLScheme: String
    private weak var presenter: UIViewController?
    private let ephemeralSession: Bool
    private let completionHandler: ASWebAuthenticationSession.CompletionHandler

    private var hostViewController: UIViewController?
    private var webView: WKWebView?
    private var finished = false

    init(
        websiteURL: URL,
        callbackURLScheme: String,
        presenter: UIViewController?,
        ephemeralSession: Bool,
        completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler
    ) {
        self.websiteURL = websiteURL
        self.callbackURLScheme = callbackURLScheme
        self.presenter = presenter
        self.ephemeralSession = ephemeralSession
        self.completionHandler = completionHandler
    }

    func start() {
        DispatchQueue.main.async {
            guard let presenter = self.presenter else {
                self.finish(
                    callbackUrl: nil,
                    error: NSError(
                        domain: "WebAuthenticator",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Missing presenter for testing web auth"]
                    )
                )
                return
            }

            let config = WKWebViewConfiguration()
            if self.ephemeralSession {
                config.websiteDataStore = .nonPersistent()
            }

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            webView.accessibilityIdentifier = "TestingWebAuthWebView"

            let viewController = UIViewController()
            viewController.modalPresentationStyle = .fullScreen
            viewController.view.backgroundColor = .systemBackground
            viewController.view.addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
                webView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            ])

            self.hostViewController = viewController
            self.webView = webView

            presenter.present(viewController, animated: false) {
                webView.load(URLRequest(url: self.websiteURL))
            }
        }
    }

    func cancel() {
        finish(
            callbackUrl: nil,
            error: NSError(
                domain: ASWebAuthenticationSessionError.errorDomain,
                code: ASWebAuthenticationSessionError.canceledLogin.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Testing web auth cancelled"]
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           url.scheme == callbackURLScheme {
            decisionHandler(.cancel)
            finish(callbackUrl: url, error: nil)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isCancellation(error) else { return }
        finish(callbackUrl: nil, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isCancellation(error) else { return }
        finish(callbackUrl: nil, error: error)
    }

    private func finish(callbackUrl: URL?, error: Error?) {
        DispatchQueue.main.async {
            guard !self.finished else { return }
            self.finished = true

            let complete = {
                self.hostViewController = nil
                self.webView = nil
                self.completionHandler(callbackUrl, error)
            }

            if let host = self.hostViewController, host.presentingViewController != nil {
                host.dismiss(animated: false, completion: complete)
            } else {
                complete()
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as NSError).domain == NSURLErrorDomain &&
        (error as NSError).code == URLError.cancelled.rawValue
    }
}
#endif
