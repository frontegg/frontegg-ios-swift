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
    private let loginHint: String?

    public init(loginHint: String? = nil) {
        self.loginHint = loginHint
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
        
        
        let conf = WKWebViewConfiguration()
        conf.userContentController = userContentController
        conf.websiteDataStore = WKWebsiteDataStore.default()

        let webView = CustomWebView(frame: .zero, configuration: conf)
        webView.navigationDelegate = webView;
        controller.webView = webView

        
//        if #available(iOS 16.4, *) {
//            webView.isInspectable = true
//        } else {
//            // Fallback on earlier versions
//        }
        
        let url: URL
        let codeVerifier: String;
        if fronteggAuth.pendingAppLink != nil {
            url = fronteggAuth.pendingAppLink!
            codeVerifier = CredentialManager.getCodeVerifier()!
            fronteggAuth.pendingAppLink = nil
        } else {
            (url, codeVerifier) = AuthorizeUrlGenerator().generate(loginHint: loginHint)
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

