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
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url,
           let scheme = url.scheme {
            if(scheme != "frontegg" && !url.absoluteString.starts(with: fronteggAuth!.baseUrl)){
                self.socialLoginAuth.startLoginTransition(url) { url, error in
                    if let query = url?.query {
//                        self.fronteggAuth?.isLoading = true
                        let successUrl = URL(string:"\(self.fronteggAuth!.baseUrl)/oauth/account/social/success?\(query)" )!
                        webView.load(URLRequest(url: successUrl))
                    }
                }
                return .cancel
            } else {
                if(url.absoluteString.starts(with: "frontegg://oauth/callback")){
                    let query = url.query ?? ""
                    self.fronteggAuth?.isLoading = true
                    webView.load(URLRequest(url: URL(string: "frontegg://oauth/success/callback?\(query)")!))
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
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("finish load \(webView.url?.absoluteString ?? "")")
        if(webView.url?.absoluteString.hasSuffix("/oauth/account/login") ?? false && fronteggAuth?.isLoading ?? true){
            fronteggAuth?.isLoading = false
        }
    }
    
}

struct FronteggWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView
    let webView: CustomWebView
    private var httpCookieStore: WKHTTPCookieStore
    private var fronteggAuth: FronteggAuth
    
    init(fronteggAuth: FronteggAuth) {
        self.fronteggAuth = fronteggAuth;
        let atDocumentStartSource: String = "window.contextOptions = {" +
        "baseUrl: \"\(fronteggAuth.baseUrl)\"," +
        "clientId: \"\(fronteggAuth.clientId)\"}"
        
        let atDocumentEndSource: String = "var meta = document.createElement('meta');" +
        "meta.name = 'viewport';" +
        "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
        "var head = document.getElementsByTagName('head')[0];" +
        "head.appendChild(meta);"
        
        let atDocumentStartScript: WKUserScript = WKUserScript(source: atDocumentStartSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let atDocumentEndScript: WKUserScript = WKUserScript(source: atDocumentEndSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let userContentController: WKUserContentController = WKUserContentController()
        let conf = WKWebViewConfiguration()
        conf.userContentController = userContentController
        userContentController.addUserScript(atDocumentStartScript)
        userContentController.addUserScript(atDocumentEndScript)
        
//        let preferences = WKPreferences()
//        conf.preferences = preferences

        
        httpCookieStore = WKWebsiteDataStore.default().httpCookieStore;
        let assetsHandler = FronteggSchemeHandler(fronteggAuth: fronteggAuth)
        
        conf.setURLSchemeHandler(assetsHandler , forURLScheme: "frontegg" )
        conf.websiteDataStore = WKWebsiteDataStore.default()
        
        webView = CustomWebView(frame: .zero, configuration: conf)
        webView.fronteggAuth = fronteggAuth;
        webView.navigationDelegate = webView;
        
        

        
    }
    
    func makeUIView(context: Context) -> WKWebView {
        
        if let url = URL(string: "frontegg://oauth/authenticate" ) {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
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
