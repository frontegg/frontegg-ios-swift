//
//  SwiftUIWebView.swift
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
    var socialLoginAuth = ExternalWebAuthentication()
    
    
    override var inputAccessoryView: UIView? {
        // remove/replace the default accessory view
        return accessoryView
    }
    
    
    private func shouldStartLoginTransition(url: URL) -> Bool{
        if url.scheme == "frontegg" || url.absoluteString.starts(with: fronteggAuth!.baseUrl) {
            return false;
        }
        
        
        if URLConstants.oauthUrls.contains(where: { url.absoluteString.starts(with: $0) }) {
            return true
        }
        
        return false;
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url {
            let urlType = getOverrideUrlType(url: url)
            
            switch(urlType){
                
            case .SocialLoginRedirectToBrowser: do {
                let opened = await UIApplication.shared.open(url)
                if(!opened){
                    _ = webView.load(URLRequest(url: URLConstants.authenticateUrl))
                }
                return .cancel
            }
            case .HostedLoginCallback: do {
                return self.handleHostedLoginCallback(webView, url)
            }
            case .SocialLoginCallback: do {
                return self.handleSocialLoginCallback(webView, url)
            }
            case .SamlCallback: do {
                return .allow
            }
            default:
                return .allow
            }
            //            if(self.shouldStartLoginTransition(url: url)){
            //
            //                let opened = await UIApplication.shared.open(url)
            //                if(!opened){
            //                    _ = webView.load(URLRequest(url: URLConstants.authenticateUrl))
            //                }
            //                return .cancel
            //            } else {
            ////                if(url.absoluteString.starts(with: URLConstants.exchangeTokenUrl.absoluteString)){
            ////                    let query = url.query ?? ""
            ////                    self.fronteggAuth?.isLoading = true
            ////                    _ = webView.load(URLRequest(url: URL(string: "\(URLConstants.exchangeTokenSuccessUrl.absoluteString)?\(query)")!))
            ////                    return .cancel
            ////                }
            //
            ////                if(url.path.hasPrefix("/frontegg/identity/resources") && url.path.hasSuffix("/prelogin")) {
            //////                    let queryItems = [URLQueryItem(name: "redirectUri", value: "frontegg-sso://")]
            //////                    var urlComps = URLComponents(string: url.absoluteString)!
            ////
            //////                    if(urlComps.query?.contains("redirectUri") ?? false){
            //////
            //////                        return .allow
            //////                    }
            //////                    urlComps.queryItems = (urlComps.queryItems ?? []) + queryItems
            //////                    let newUrl = urlComps.url!;
            ////
            ////                    self.fronteggAuth?.isLoading = true
            ////                    _ = webView.load(URLRequest(url: url))
            ////                    return .cancel
            ////                }
            //
            //                if(url.path.hasPrefix("/mobile/oauth/callback")){
            //
            //                    return .cancel
            //                }
            //                return .allow
            //            }
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
        if let url = webView.url {
            
            if (url.absoluteString.hasPrefix("\(self.fronteggAuth?.baseUrl ?? "")/oauth/account") ) {
                if(webView.url?.path != "/oauth/account/social/success"){
                    if(fronteggAuth?.isLoading ?? true){
                        fronteggAuth?.isLoading = false
                    }
                }
            } else {
                if !(self.shouldStartLoginTransition(url: url) ||
                     url.absoluteString.hasPrefix(self.fronteggAuth?.baseUrl ?? "") ||
                     url.absoluteString.hasPrefix("frontegg://")
                ){
                    if(fronteggAuth?.isLoading ?? true){
                        fronteggAuth?.isLoading = false
                    }
                }
                
            }
        }
        
    }
    
    
    private func handleSocialLoginCallback(_ webView: WKWebView, _ url: URL) -> WKNavigationActionPolicy {
        
        
        print("handleSocialLoginCallback, url: \(url)")
        return .cancel
    }
    
    private func handleHostedLoginCallback(_ webView: WKWebView, _ url: URL) -> WKNavigationActionPolicy {
        
        guard let queryItems = getQueryItems(url.absoluteString),
              let code = queryItems["code"] else {
            
            print("handleHostedLoginCallback failed of nullable query")
            
            
            return .allow
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                let success = await FronteggAuth.shared.handleHostedLoginCallback(code)
                
                if(!success){
                        let url = AuthorizeUrlGenerator().generate()
                        _ = webView.load(URLRequest(url: url))
                }
            }
            
        }
        return .cancel
    }
    
    
}

