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
        
        let controller: FronteggWKContentController = FronteggWKContentController()
        let userContentController: WKUserContentController = WKUserContentController()
        userContentController.add(controller, name: "FronteggNativeBridge")


        let fronteggApp = FronteggApp.shared
        let jsObject = String(data: try! JSONSerialization.data(withJSONObject: [
            "loginWithSocialLogin": fronteggApp.handleLoginWithSocialLogin,
            "loginWithSSO": fronteggApp.handleLoginWithSSO,
            "shouldPromptSocialLoginConsent": fronteggApp.shouldPromptSocialLoginConsent
        ]), encoding: .utf8)
        
        let jsScript = WKUserScript(source: "window.FronteggNativeBridgeFunctions = \(jsObject ?? "{}");", injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(jsScript)
        
        
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
        conf.userContentController = userContentController
        conf.websiteDataStore = WKWebsiteDataStore.default()

        let webView = CustomWebView(frame: .zero, configuration: conf)
        webView.navigationDelegate = webView;
        controller.webView = webView

#if compiler(>=5.8) && os(iOS) && DEBUG
if #available(iOS 16.4, *) {
    webView.isInspectable = true
}
#endif

        
        let url: URL
        let codeVerifier: String;
        if fronteggAuth.pendingAppLink != nil {
            url = fronteggAuth.pendingAppLink!
            codeVerifier = CredentialManager.getCodeVerifier()!
            fronteggAuth.pendingAppLink = nil
        } else {
            (url, codeVerifier) = AuthorizeUrlGenerator().generate(loginHint: fronteggAuth.loginHint)
            fronteggAuth.loginHint = nil
            CredentialManager.saveCodeVerifier(codeVerifier)
        }

        
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)
        webView.load(request)

        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
}


fileprivate final class InputAccessoryHackHelper: NSObject {
    @objc var inputAccessoryView: AnyObject? { return nil }
}

