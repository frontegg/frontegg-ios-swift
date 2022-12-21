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
        
        
        if SocialLoginConstansts.oauthUrls.contains(where: { url.absoluteString.starts(with: $0) }) {
            print("Catch oauth url, \(url.absoluteString)")
            return true
        }
    
        return false;
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if var url = navigationAction.request.url {
            if(self.shouldStartLoginTransition(url: url)){
//                print("Starting login transition to: \(url)")
                if #available(iOS 16.0, *) {
                    url.append(queryItems: [URLQueryItem(name: "prompt", value: "select_account")])
                } else {
                    // Fallback on earlier versions
                };
                self.socialLoginAuth.startLoginTransition(url) { url, error in
                    if let query = url?.query {
                        let successUrl = URL(string:"\(self.fronteggAuth!.baseUrl)/oauth/account/social/success?\(query)" )!
                        webView.stopLoading()
                        _ = webView.load((URLRequest(url: successUrl)))
//                        self.fronteggAuth?.isLoading = false
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
                
                if(url.path.hasPrefix("/frontegg/identity/resources") && url.path.hasSuffix("/prelogin")) {
                    let queryItems = [URLQueryItem(name: "redirectUri", value: "frontegg-sso://")]
                    var urlComps = URLComponents(string: url.absoluteString)!
                    
                    if(urlComps.query?.contains("redirectUri") ?? false){
                        
                        return .allow
                    }
                    urlComps.queryItems = (urlComps.queryItems ?? []) + queryItems
                    let newUrl = urlComps.url!;
                    
                    self.fronteggAuth?.isLoading = true
                    _ = webView.load(URLRequest(url: newUrl))
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
            if(webView.url?.path != "/oauth/account/social/success"){
                if(fronteggAuth?.isLoading ?? true){
                    fronteggAuth?.isLoading = false
                }
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
    private var fronteggAuth: FronteggAuth
    
    init(_ fronteggAuth: FronteggAuth) {
        self.fronteggAuth = fronteggAuth;
        
        let preloadJSScript = JSHelper.generatePreloadScript()
        let contextOptionsScript = JSHelper.generateContextOptions(fronteggAuth.baseUrl, fronteggAuth.clientId)
        
        let userContentController: WKUserContentController = WKUserContentController()
        userContentController.addUserScript(contextOptionsScript)
        userContentController.addUserScript(preloadJSScript)
//        userContentController.add(self, name: "fronteggSwiftHandler")
        
        
        let conf = WKWebViewConfiguration()
        conf.userContentController = userContentController
        
        let assetsHandler = FronteggSchemeHandler(fronteggAuth: fronteggAuth)
        
        conf.setURLSchemeHandler(assetsHandler , forURLScheme: "frontegg" )
        conf.websiteDataStore = WKWebsiteDataStore.default()
        
        webView = CustomWebView(frame: .zero, configuration: conf)
        webView.fronteggAuth = fronteggAuth;
        webView.navigationDelegate = webView;
        
    }
    
    func makeUIView(context: Context) -> WKWebView {
        
        let url: URL
        if let appLink = self.fronteggAuth.pendingAppLink {
            print("Loading deep link \(appLink)")
            url = appLink
        } else {
            url = URLConstants.authenticateUrl
        }
        
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)
        webView.load(request)
                
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
