//
//  SwiftUIWebView.swift
//  poc
//
//  Created by David Frontegg on 24/10/2022.
//

import Foundation
import WebKit
import SwiftUI
import AuthenticationServices
 

class CustomWebView: WKWebView, WKNavigationDelegate {
    var accessoryView: UIView?
    var fronteggAuth: FronteggAuth?
    var socialLoginAuth = FronteggSocialLoginAuth()
    
    override var inputAccessoryView: UIView? {
        // remove/replace the default accessory view
        return accessoryView
    }
    
    
    private func shouldStartLoginTransition(url: URL) -> Bool{
        if url.scheme == "frontegg" || url.absoluteString.starts(with: fronteggAuth!.baseUrl) {
            return false;
        }
        if url.absoluteString.contains("google") ||
            url.absoluteString.contains("microsoft") ||
            url.absoluteString.contains("github") ||
            url.absoluteString.contains("facebook") {
            return true;
        }
        
        // Option 1:
        // generate private/public key in ios app
        // login with okta? relayState = publicKey
        // post request to hosted login saml callback + relayState
        // https://{hosted login}/saml/mobile/callback => refresh+access encrypt with public key
        // go to frontegg-auth://saml/success?ecrypyed=sadasdsad
        // privateKey + sadasdsad => refresh token + acccess Token
        
        
        return false;
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url {
            if(self.shouldStartLoginTransition(url: url)){
                print("Starting login transition to: \(url)")
                self.socialLoginAuth.startLoginTransition(url) { url, error in
                    if let query = url?.query {
                        let successUrl = URL(string:"\(self.fronteggAuth!.baseUrl)/oauth/account/social/success?\(query)" )!
                        webView.stopLoading()
                        _ = webView.load((URLRequest(url: successUrl)))
                        self.fronteggAuth?.isLoading = false
                    } else {
                        self.fronteggAuth?.isLoading = true
                        webView.stopLoading()
                        _ = webView.load(URLRequest(url: URL(string:"frontegg://oauth/authenticate")!))
                    }
                }
                return .cancel
            } else {
                if(url.absoluteString.starts(with: "frontegg://oauth/callback")){
                    let query = url.query ?? ""
                    self.fronteggAuth?.isLoading = true
                    _ = webView.load(URLRequest(url: URL(string: "frontegg://oauth/success/callback?\(query)")!))
                    return .cancel
                }
                
                return .allow
            }
        } else {
            self.fronteggAuth?.isLoading = false
            return .allow
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("start load \(webView.url?.absoluteString ?? "")")
        fronteggAuth?.externalLink = webView.url?.absoluteString.contains("okta.com") ?? false
        
        if(!(webView.url?.absoluteString.hasSuffix("/prelogin") ?? false)){
            fronteggAuth?.isLoading = true
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("finish load \(webView.url?.absoluteString ?? "")")
        if (webView.url?.absoluteString.hasPrefix("\(self.fronteggAuth?.baseUrl ?? "")/oauth/account") ?? false) {
            if(fronteggAuth?.isLoading ?? true){
                fronteggAuth?.isLoading = false
            }
        } else if (webView.url?.absoluteString.contains("okta.com") ?? false) {
            if(fronteggAuth?.isLoading ?? true){
                fronteggAuth?.isLoading = false
            }
        }

    }
    
}

struct FronteggWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView
    
    let webView: CustomWebView
    private var httpCookieStore: WKHTTPCookieStore
    private var fronteggAuth: FronteggAuth
    
    init(_ fronteggAuth: FronteggAuth) {
        self.fronteggAuth = fronteggAuth;
        let contextOptionsSource: String = "window.contextOptions = {" +

        "baseUrl: \"\(fronteggAuth.baseUrl)\"," +
        "clientId: \"\(fronteggAuth.clientId)\"}"
        
        let metadataSource:String = "let interval = setInterval(function(){" +
        "   if(document.getElementsByTagName('head').length > 0){" +
        "       clearInterval(interval);" +
        "       var meta = document.createElement('meta');" +
        "       meta.name = 'viewport';" +
        "       meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
        "       var head = document.getElementsByTagName('head')[0];" +
        "       head.appendChild(meta);" +
        "       var style = document.createElement('style');" +
        "       style.innerHTML = 'html {font-size: 16px;}';" +
        "       style.setAttribute('type', 'text/css');" +
        "       document.head.appendChild(style); " +
        "   }" +
        "}, 10);"

        
        let userContentController: WKUserContentController = WKUserContentController()
        userContentController.addUserScript(WKUserScript(source: contextOptionsSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        userContentController.addUserScript(WKUserScript(source: metadataSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        
        let conf = WKWebViewConfiguration()
        conf.userContentController = userContentController
        httpCookieStore = WKWebsiteDataStore.default().httpCookieStore;
        let assetsHandler = FronteggSchemeHandler(fronteggAuth: fronteggAuth)
        
        conf.setURLSchemeHandler(assetsHandler , forURLScheme: "frontegg" )
        conf.websiteDataStore = WKWebsiteDataStore.default()
        
        webView = CustomWebView(frame: .zero, configuration: conf)
        webView.fronteggAuth = fronteggAuth;
        webView.navigationDelegate = webView;
        
    }
    
    func makeUIView(context: Context) -> WKWebView {
        
        if let url = URL(string: self.fronteggAuth.pendingAppLink ?? "frontegg://oauth/authenticate" ) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData)
            webView.load(request)
        }
                
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
    
    
    
    
}


fileprivate final class InputAccessoryHackHelper: NSObject {
    @objc var inputAccessoryView: AnyObject? { return nil }
}

extension WKWebView {
    override open var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
