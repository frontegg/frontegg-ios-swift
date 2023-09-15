//
//  CustomWebView.swift
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
    private let logger = getLogger("CustomWebView")
    private var lastResponseStatusCode: Int? = nil
    var codeVerifier: String? = nil
    
    override var inputAccessoryView: UIView? {
        // remove/replace the default accessory view
        return accessoryView
    }
    
    private func isCancelledAsAuthenticationLoginError(_ error: Error) -> Bool {
        (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        logger.trace("navigationAction check for \(navigationAction.request.url?.absoluteString ?? "no Url")")
        if let url = navigationAction.request.url {
            let urlType = getOverrideUrlType(url: url)
            
            logger.info("urlType: \(urlType)")
            switch(urlType){
                
            case .SocialLoginRedirectToBrowser: do {
                
                return self.handleSocialLoginRedirectToBrowser(webView, url)
            }
            case .HostedLoginCallback: do {
                return self.handleHostedLoginCallback(webView, url)
            }
            case .SocialOauthPreLogin: do {
                return self.setSocialLoginRedirectUri(webView, url)
            }
            default:
                return .allow
            }
        } else {
            logger.warning("failed to get url from navigationAction")
            self.fronteggAuth.webLoading = false
            return .allow
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logger.trace("didStartProvisionalNavigation")
        if let url = webView.url {
            let urlType = getOverrideUrlType(url: url)
            
            logger.info("urlType: \(urlType)")
            
            let isUnknown = (urlType == .Unknown)
            if(fronteggAuth.externalLink != isUnknown) {
                fronteggAuth.externalLink = isUnknown
            }
            
            if(urlType != .SocialLoginRedirectToBrowser &&
               urlType != .SocialOauthPreLogin){
                
                if(fronteggAuth.webLoading == false) {
                    fronteggAuth.webLoading = true
                }
            }
            
            logger.info("startProvisionalNavigation webLoading = \(fronteggAuth.webLoading)")
            logger.info("isExternalLink = \(fronteggAuth.externalLink)")
        } else {
            logger.warning("failed to get url from didStartProvisionalNavigation()")
            self.fronteggAuth.webLoading = false
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.trace("didFinish")
        if let url = webView.url {
            let urlType = getOverrideUrlType(url: url)
            logger.info("urlType: \(urlType), for: \(url.absoluteString)")
            
            
            if urlType == .loginRoutes || urlType == .Unknown {
                logger.info("hiding Loader screen")
                if(fronteggAuth.webLoading) {
                    fronteggAuth.webLoading = false
                }
            } else if let statusCode = self.lastResponseStatusCode {
                self.lastResponseStatusCode = nil;
                self.fronteggAuth.webLoading = false
                
                
                webView.evaluateJavaScript("JSON.parse(document.body.innerText).errors.join('\\n')") { [self] res, err in
                    let errorMessage = res as? String ?? "Unknown error occured"
                    
                    logger.error("Failed to load page: \(errorMessage), status: \(statusCode)")
                    self.fronteggAuth.webLoading = false
                    let content = generateErrorPage(message: errorMessage, url: url.absoluteString,status: statusCode);
                    webView.loadHTMLString(content, baseURL: nil);
                }
            }
        } else {
            logger.warning("failed to get url from didFinishNavigation()")
            self.fronteggAuth.webLoading = false
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        
        if let response = navigationResponse.response as? HTTPURLResponse {
            if response.statusCode >= 400 && response.statusCode != 500, let url = response.url {
                let urlType = getOverrideUrlType(url: url)
                logger.info("urlType: \(urlType), for: \(url.absoluteString)")
                
                if(urlType == .internalRoutes && response.mimeType == "application/json"){
                    self.lastResponseStatusCode = response.statusCode
                    decisionHandler(.allow)
                    return
                }
            }
        }
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError _error: Error) {
        let error = _error as NSError
        let statusCode = error.code
        if(statusCode==102){
            // interrupted by frontegg webview
            return;
        }
        
        let errorMessage = error.localizedDescription;
        let url = "\(error.userInfo["NSErrorFailingURLKey"] ?? error.userInfo)"
        logger.error("Failed to load page: \(errorMessage), status: \(statusCode), \(error)")
        self.fronteggAuth.webLoading = false
        let content = generateErrorPage(message: errorMessage, url: url, status: statusCode);
        webView.loadHTMLString(content, baseURL: nil);
    }
    
    
    private func handleHostedLoginCallback(_ webView: WKWebView, _ url: URL) -> WKNavigationActionPolicy {
        logger.trace("handleHostedLoginCallback, url: \(url)")
        guard let queryItems = getQueryItems(url.absoluteString),
              let code = queryItems["code"],
              let savedCodeVerifier =  self.codeVerifier else {
            logger.error("failed to get extract code from hostedLoginCallback url")
            logger.info("Restast the process by generating a new authorize url")
            let (url, codeVerifier) = AuthorizeUrlGenerator().generate()
            self.codeVerifier = codeVerifier
            _ = webView.load(URLRequest(url: url))
            return .cancel
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                FronteggAuth.shared.handleHostedLoginCallback(code, savedCodeVerifier ) { res in
                    switch (res) {
                        case .success(let user):
                            print("User \(user.id)")
                        
                        case .failure(let error):
                            print("Error \(error)")
                            let (url, codeVerifier)  = AuthorizeUrlGenerator().generate()
                            self.codeVerifier = codeVerifier
                            _ = webView.load(URLRequest(url: url))
                    }
                }
            }
        }
        return .cancel
    }
    
    
    private func setSocialLoginRedirectUri(_ webView:WKWebView, _ url:URL) -> WKNavigationActionPolicy {
        
        logger.trace("setSocialLoginRedirectUri()")
        let queryItems = [
            URLQueryItem(name: "redirectUri", value: generateRedirectUri()),
        ]
        var urlComps = URLComponents(string: url.absoluteString)!
        
        if(urlComps.query?.contains("redirectUri") ?? false){
            logger.trace("redirectUri exist, forward navigation to webView")
            return .allow
        }
        
        urlComps.queryItems = (urlComps.queryItems ?? []) + queryItems
        
        
        logger.trace("added redirectUri to socialLogin auth url \(urlComps.url!)")
        _ = webView.load(URLRequest(url: urlComps.url!))
        return .cancel
    }
 
    private func handleSocialLoginRedirectToBrowser(_ webView:WKWebView, _ socialLoginUrl:URL) -> WKNavigationActionPolicy{
        
        logger.trace("handleSocialLoginRedirectToBrowser()")
        let queryItems = [
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        var urlComps = URLComponents(string: socialLoginUrl.absoluteString)!
        urlComps.queryItems = (urlComps.queryItems ?? []) + queryItems
        
        let url = urlComps.url!
        
        fronteggAuth.webLoading = false
        fronteggAuth.webAuthentication.webAuthSession?.cancel()

        
        fronteggAuth.webAuthentication.start(url) { callbackUrl, error  in

            if(error != nil){
                if(self.isCancelledAsAuthenticationLoginError(error!)){
                    print("Social login authentication canceled")
                }else {
                    print("Failed to login with social login \(error?.localizedDescription ?? "unknown error")")
                    let (newUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                    self.codeVerifier = codeVerifier
                    _ = webView.load(URLRequest(url: newUrl))
                }
            }else if (callbackUrl == nil){
                print("Failed to login with social login \(error?.localizedDescription ?? "unknown error")")
                let (newUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                self.codeVerifier = codeVerifier
                _ = webView.load(URLRequest(url: newUrl))
            }else {
                let components = URLComponents(url: callbackUrl!, resolvingAgainstBaseURL: false)!
                let query = components.query!
                let resultUrl = URL(string:
                                        "\(self.fronteggAuth.baseUrl)/oauth/account/social/success?\(query)")!
                _ = webView.load(URLRequest(url: resultUrl))
                
                
            }
        }
        
        
        return .cancel
    }
}
