//
//  FronteggWebView.swift
//
//  Created by David Frontegg on 24/10/2022.
//

import Foundation
import WebKit
import SwiftUI
import AuthenticationServices



public struct FronteggWebView: UIViewRepresentable {
    public typealias UIViewType = WKWebView
    private var fronteggAuth: FronteggAuth
    private var logger = getLogger("FronteggWebView")
    public init() {
        self.fronteggAuth = FronteggApp.shared.auth;
    }

    public func makeUIView(context: Context) -> WKWebView {
        logger.trace("FronteggWebView::makeUIView::start")
        let controller: FronteggWKContentController = FronteggWKContentController()
        let userContentController: WKUserContentController = WKUserContentController()
        userContentController.add(controller, name: "FronteggNativeBridge")

        let fronteggApp = FronteggApp.shared
        let jsObject: String
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: [
                "loginWithSocialLogin": fronteggApp.handleLoginWithSocialLogin,
                "loginWithCustomSocialLoginProvider": fronteggApp.handleLoginWithCustomSocialLoginProvider,
                "loginWithSocialLoginProvider": fronteggApp.handleLoginWithSocialProvider,
                "loginWithSSO": fronteggApp.handleLoginWithSSO,
                "shouldPromptSocialLoginConsent": fronteggApp.shouldPromptSocialLoginConsent,
                "suggestSavePassword": fronteggApp.shouldSuggestSavePassword,
                "useNativeLoader": true,
            ])
            jsObject = String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed to serialize JSON: \(error)")
            jsObject = "{}"
        }
        
        
    
        let jsScript = WKUserScript(source: "window.FronteggNativeBridgeFunctions = \(jsObject);", injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(jsScript)
        
        let labelFixScript = """
            // Inject this at document start (e.g. via WKUserScript atDocumentStart)
            (function() {
              // Fixes aria-labels inside a given root (light DOM or shadowRoot)
              function fixLabels(root) {
                root.querySelectorAll('[data-test-id]').forEach(el => {
                  if (!el.hasAttribute('aria-label')) {
                    el.setAttribute('aria-label', el.getAttribute('data-test-id'));
                  }
                });
              }

              // Attaches a MutationObserver to a shadowRoot
              function attachShadowObserver(shadowRoot) {
                // Run once immediately
                fixLabels(shadowRoot);

                // Then watch for changes inside the shadow DOM
                const innerObserver = new MutationObserver(() => fixLabels(shadowRoot));
                innerObserver.observe(shadowRoot, { childList: true, subtree: true });
              }

              // Observe the light DOM for when the host element appears
              const outerObserver = new MutationObserver(() => {
                const host = document.querySelector('#frontegg-login-box-container-default');
                if (host && host.shadowRoot && !host.__shadowObserverAttached) {
                  host.__shadowObserverAttached = true;
                  attachShadowObserver(host.shadowRoot);
                }
              });
              outerObserver.observe(document.documentElement, { childList: true, subtree: true });

              // Also attempt once on initial DOMContentLoaded
              document.addEventListener('DOMContentLoaded', () => {
                const host = document.querySelector('#frontegg-login-box-container-default');
                if (host && host.shadowRoot) {
                  attachShadowObserver(host.shadowRoot);
                }
              });
            })();
        """
        let accessabilityScript = WKUserScript(source: labelFixScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(accessabilityScript)
        
        
        if #available(iOS 16, *) {
            // Passkeys avaialble in webview
        } else {
            if #available(iOS 15.0, *) {
                logger.debug("Adding javascript hook to support passkeys in iOS 15")
                userContentController.addUserScript(
                    WKUserScript(source: PasskeysAuthenticator.ios15PasskeysHook, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
                )
            } else {
                logger.debug("Passkeys not supported below ios 15")
            }
        }
        
        let conf = WKWebViewConfiguration()
        conf.processPool = WebViewShared.processPool
        conf.userContentController = userContentController
        conf.websiteDataStore = .default()

        let webView = CustomWebView(frame: .zero, configuration: conf)
        webView.navigationDelegate = webView;
        webView.uiDelegate = webView
        controller.webView = webView
        webView.backgroundColor = FronteggApp.shared.backgroundColor

#if compiler(>=5.8) && os(iOS) && DEBUG
if #available(iOS 16.4, *) {
    webView.isInspectable = true
}
#endif

        
        var url: URL
        var codeVerifier: String;
        if let pendingAppLink = fronteggAuth.pendingAppLink {
            url = pendingAppLink
            if let existingCodeVerifier = CredentialManager.getCodeVerifier() {
                codeVerifier = existingCodeVerifier
            } else {
                logger.info("No existing code verifier found, creating a new one")
                codeVerifier = createRandomString()
                CredentialManager.saveCodeVerifier(codeVerifier)
            }
            fronteggAuth.pendingAppLink = nil
        } else {
            (url, codeVerifier) = AuthorizeUrlGenerator().generate(loginHint: fronteggAuth.loginHint)
            fronteggAuth.loginHint = nil
            CredentialManager.saveCodeVerifier(codeVerifier)
        }

        
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
        webView.load(request)

        logger.trace("FronteggWebView::makeUIView::end")
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
    
}


fileprivate final class InputAccessoryHackHelper: NSObject {
    @objc var inputAccessoryView: AnyObject? { return nil }
}


class WebViewShared {
  static let processPool = WKProcessPool()
}
