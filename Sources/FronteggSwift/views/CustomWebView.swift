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
    private let fronteggAuth: FronteggAuth = FronteggAuth.shared
    
    override var inputAccessoryView: UIView? {
        // remove/replace the default accessory view
        return accessoryView
    }
    
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url {
            let urlType = getOverrideUrlType(url: url)
            
            switch(urlType){
                
            case .SocialLoginRedirectToBrowser: do {
                let opened = await UIApplication.shared.open(url)
                if !opened {
                    let url = AuthorizeUrlGenerator().generate()
                    _ = webView.load(URLRequest(url: url))
                }
                return .cancel
            }
            case .HostedLoginCallback: do {
                return self.handleHostedLoginCallback(webView, url)
            }
            case .SamlCallback: do {
                return .allow
            }
            case .SocialOauthPreLogin: do {
                return self.setSocialLoginRedirectUri(webView, url)
            }
            default:
                return .allow
            }
        } else {
            self.fronteggAuth.isLoading = false
            return .allow
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("start load \(webView.url?.absoluteString ?? "")")
        fronteggAuth.externalLink = webView.url?.absoluteString.contains("okta.com") ?? false
        
        if(!(webView.url?.absoluteString.hasSuffix("/prelogin") ?? false)){
            fronteggAuth.isLoading = true
        }
        
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("finish load \(webView.url?.absoluteString ?? "")")
        if let url = webView.url {
            
            if (url.absoluteString.hasPrefix("\(self.fronteggAuth.baseUrl)/oauth/account") ) {
                if(webView.url?.path != "/oauth/account/social/success"){
                    if(fronteggAuth.isLoading){
                        fronteggAuth.isLoading = false
                    }
                }
            }
        }
        if(fronteggAuth.isLoading){
            fronteggAuth.isLoading = false
        }
        
    }

    private func handleHostedLoginCallback(_ webView: WKWebView, _ url: URL) -> WKNavigationActionPolicy {
        
        guard let queryItems = getQueryItems(url.absoluteString), let code = queryItems["code"] else {
            
            let url = AuthorizeUrlGenerator().generate()
            _ = webView.load(URLRequest(url: url))
            return .cancel
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
    
    
    private func setSocialLoginRedirectUri(_ webView:WKWebView, _ url:URL) -> WKNavigationActionPolicy {
        
        let queryItems = [URLQueryItem(name: "redirectUri", value: URLConstants.generateSocialLoginRedirectUri(fronteggAuth.baseUrl))]
        var urlComps = URLComponents(string: url.absoluteString)!

        if(urlComps.query?.contains("redirectUri") ?? false){
            return .allow
        }
        urlComps.queryItems = (urlComps.queryItems ?? []) + queryItems
     
        self.fronteggAuth.isLoading = true
        _ = webView.load(URLRequest(url: urlComps.url!))
        return .cancel
    }
    
}

