//
//  CustomWebView.swift
//  Created by David Frontegg on 24/10/2022.
//

import Foundation
import WebKit
import SwiftUI
import AuthenticationServices


class CustomWebView: WKWebView, WKNavigationDelegate, WKUIDelegate {
    var accessoryView: UIView?
    private let fronteggAuth: FronteggAuth = FronteggAuth.shared
    private let logger = getLogger("CustomWebView")
    private var lastResponseStatusCode: Int? = nil
    private var cachedUrlSchemes: [String]? = nil
    
    
    override var inputAccessoryView: UIView? {
        // remove/replace the default accessory view
        return accessoryView
    }
    
    private static func isCancelledAsAuthenticationLoginError(_ error: Error) -> Bool {
        (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
    
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" {
                    if UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                        return nil
                    }
                }
                
                webView.load(navigationAction.request)
            }
        }
        
        return nil
    }
    
    func webView(_ _webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        weak var webView = _webView
        let url = navigationAction.request.url
        let urlString = url?.absoluteString ?? "no url"

        logger.trace("navigationAction check for \(urlString)")

        if let url = url {
            if let scheme = url.scheme, getAppURLSchemes().contains(scheme) {
                logger.info("Detected deep link (\(scheme)), opening externally: \(url.absoluteString)")

                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:]) { success in
                        if success {
                            self.logger.info("✅ Deep link opened, dismissing login modal via VCHolder")
                            if let presentingVC = VCHolder.shared.vc?.presentedViewController ?? VCHolder.shared.vc {
                                presentingVC.dismiss(animated: true)
                                VCHolder.shared.vc = nil
                                FronteggAuth.shared.loginCompletion?(.failure(.authError(.operationCanceled)))
                            } else {
                                self.logger.warning("⚠️ No VC to dismiss in VCHolder.")
                            }
                        } else {
                            self.logger.error("❌ Failed to open deep link: \(url.absoluteString)")
                        }
                    }
                }

                return .cancel
            }

            let urlType = getOverrideUrlType(url: url)
            logger.info("urlType: \(urlType)")

            switch urlType {
            case .HostedLoginCallback:
                return self.handleHostedLoginCallback(webView, url)
            case .SocialOauthPreLogin:
                return self.setSocialLoginRedirectUri(webView, url)
            default:
                return .allow
            }
        } else {
            logger.warning("failed to get url from navigationAction")
            self.fronteggAuth.setWebLoading(false)
            return .allow
        }
    }
    
    private func getAppURLSchemes() -> [String] {
        
        if let schemes = cachedUrlSchemes {
            return schemes
        }
        
        guard
            let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]]
        else {
            cachedUrlSchemes = []
            return []
        }

        cachedUrlSchemes = urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
        return cachedUrlSchemes ?? []
    }

    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logger.trace("didStartProvisionalNavigation")
        if let url = webView.url {
            let urlType = getOverrideUrlType(url: url)
            
            logger.info("urlType: \(urlType)")
            
            if(urlType != .SocialOauthPreLogin &&
               urlType != .Unknown){
                
                if(fronteggAuth.webLoading == false) {
                    fronteggAuth.setWebLoading(true)
                }
            }
        } else {
            logger.warning("failed to get url from didStartProvisionalNavigation()")
            self.fronteggAuth.setWebLoading(false)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.trace("didFinish")
        if let url = webView.url {
            let urlType = getOverrideUrlType(url: url)
            logger.info("urlType: \(urlType), for: \(url.absoluteString)")
            
            
            if(urlType == .internalRoutes ) {
                logger.trace("hiding Loader screen after 300ms")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // usually internal routes are redirects
                    // this 500ms will prevent loader blinking
                    self.fronteggAuth.setWebLoading(false)
                }

            }
            if urlType == .loginRoutes || urlType == .Unknown {
                logger.info("hiding Loader screen")
                if(fronteggAuth.webLoading) {
                    fronteggAuth.setWebLoading(false)
                }
            } else if let statusCode = self.lastResponseStatusCode {
                self.lastResponseStatusCode = nil;
                self.fronteggAuth.setWebLoading(false)
                
                if(url.absoluteString.starts(with: "\(fronteggAuth.baseUrl)/oauth/authorize")){
                    self.fronteggAuth.setWebLoading(false)
                    let encodedUrl = url.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
                    let reloadScript = "setTimeout(()=>window.location.href=\"\(encodedUrl)\", 4000)"
                    let jsCode = "(function(){\n" +
                            "                var script = document.createElement('script');\n" +
                            "                script.innerHTML=`\(reloadScript)`;" +
                            "                document.body.appendChild(script)\n" +
                            "            })()"
                    webView.evaluateJavaScript(jsCode)
                    logger.error("Failed to load page \(encodedUrl), status: \(statusCode)")
                    
                    return
                }
                
                webView.evaluateJavaScript("JSON.parse(document.body.innerText).errors.join('\\n')") { [self] res, err in
                    let errorMessage = res as? String ?? "Unknown error occured"
                    
                    logger.error("Failed to load page: \(errorMessage), status: \(statusCode)")
                    self.fronteggAuth.setWebLoading(false)
                    let content = generateErrorPage(message: errorMessage, url: url.absoluteString, status: statusCode);
                    webView.loadHTMLString(content, baseURL: nil);
                }
            }
        } else {
            logger.warning("failed to get url from didFinishNavigation()")
            self.fronteggAuth.setWebLoading(false)
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        
        if let response = navigationResponse.response as? HTTPURLResponse {
            if response.statusCode >= 400 && response.statusCode != 500, let url = response.url {
                let urlType = getOverrideUrlType(url: url)
                logger.info("urlType: \(urlType), for: \(url.absoluteString)")
                
                if(urlType == .internalRoutes){
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
        let url = "\(error.userInfo["NSErrorFailingURLKey"] ?? "")"
        logger.error("Failed to load page: \(errorMessage), status: \(statusCode), \(error)")
        
        
        self.fronteggAuth.setWebLoading(false)
        let content = generateErrorPage(message: errorMessage, url: url, status: statusCode);
        webView.loadHTMLString(content, baseURL: nil);
        
    }
    
    
    private func handleHostedLoginCallback(_ webView: WKWebView?, _ url: URL) -> WKNavigationActionPolicy {
        logger.trace("handleHostedLoginCallback, url: \(url)")
        guard let queryItems = getQueryItems(url.absoluteString),
              let code = queryItems["code"],
              let savedCodeVerifier =  CredentialManager.getCodeVerifier() else {
            logger.error("failed to get extract code from hostedLoginCallback url")
            logger.info("Restast the process by generating a new authorize url")
            let (url, codeVerifier) = AuthorizeUrlGenerator().generate()
            CredentialManager.saveCodeVerifier(codeVerifier)
            _ = webView?.load(URLRequest(url: url))
            return .cancel
        }
        self.fronteggAuth.setWebLoading(true)
        DispatchQueue.global(qos: .userInitiated).async {
            Task { @MainActor in
                FronteggAuth.shared.handleHostedLoginCallback(code, savedCodeVerifier ) { res in
                    switch (res) {
                    case .success(_):
                        let logger = getLogger("CustomWebView")
                        logger.info("Authentication succeeded")
                        
                    case .failure(let error):
                        print("Error \(error)")
                        let (url, codeVerifier)  = AuthorizeUrlGenerator().generate()
                        CredentialManager.saveCodeVerifier(codeVerifier)
                        DispatchQueue.main.async {
                            _ = webView?.load(URLRequest(url: url))
                        }
                    }
                    FronteggAuth.shared.loginCompletion?(res)
                }
            }
        }
        return .cancel
    }
    
    
    private func setSocialLoginRedirectUri(_ _webView:WKWebView?, _ url:URL) -> WKNavigationActionPolicy {
        
        weak var webView = _webView
        logger.trace("setSocialLoginRedirectUri()")
        let queryItems = [
            URLQueryItem(name: "redirectUri", value: generateRedirectUri())
        ]
        var urlComps = URLComponents(string: url.absoluteString)!
        
        let filteredQueryItems = urlComps.queryItems?.filter {
            $0.name == "redirectUri"
        } ?? []
        
        
        urlComps.queryItems = filteredQueryItems + queryItems
        
        logger.trace("added redirectUri to socialLogin auth url \(urlComps.url!)")
        
        let followUrl = urlComps.url!
        DispatchQueue.global(qos: .userInitiated).sync {
            
            var request = URLRequest(url: followUrl)
            request.httpMethod = "GET"
            
            let noRedirectDelegate = NoRedirectSessionDelegate()
            let noRedirectSession = URLSession(configuration: .default, delegate: noRedirectDelegate, delegateQueue: nil)
            
            let task = noRedirectSession.dataTask(with: request) { (data, response, error) in
                // Check for errors
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    return
                }
                
                // Check for valid HTTP response
                if let httpResponse = response as? HTTPURLResponse {
                    
                    if let location = httpResponse.value(forHTTPHeaderField: "Location"),
                       let socialLoginUrl = URL(string: location) {
                        
                        self.handleSocialLoginRedirectToBrowser(webView, socialLoginUrl)
                    }
                    
                }
            }
            task.resume()
        }
        
        return .cancel
    }
    
    private func startExternalBrowser(_ _webView:WKWebView?, _ url:URL, _ ephemeralSession:Bool = false) -> Void {
        
        weak var webView = _webView
        
        WebAuthenticator.shared.start(url, ephemeralSession: ephemeralSession, window: self.window) { callbackUrl, error  in
            print("Social login authentication canceled")
            if(error != nil){
                if(CustomWebView.isCancelledAsAuthenticationLoginError(error!)){
                    print("Social login authentication canceled")
                }else {
                    print("Failed to login with social login \(error?.localizedDescription ?? "unknown error")")
                    let (newUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                    CredentialManager.saveCodeVerifier(codeVerifier)
                    _ = webView?.load(URLRequest(url: newUrl))
                }
            }else if (callbackUrl == nil){
                print("Failed to login with social login \(error?.localizedDescription ?? "unknown error")")
                let (newUrl, codeVerifier) = AuthorizeUrlGenerator().generate()
                CredentialManager.saveCodeVerifier(codeVerifier)
                _ = webView?.load(URLRequest(url: newUrl))
                
            }else {
                let components = URLComponents(url: callbackUrl!, resolvingAgainstBaseURL: false)!
                let query = components.query!
                let resultUrl = URL(string:
                                        "\(FronteggAuth.shared.baseUrl)/oauth/account/social/success?\(query)")!
                _ = webView?.load(URLRequest(url: resultUrl))
                
                
            }
        }
    }
    
    private func handleSocialLoginRedirectToBrowser(_ _webView:WKWebView?, _ socialLoginUrl:URL) -> Void {
        
        weak var webView = _webView
        logger.trace("handleSocialLoginRedirectToBrowser()")
        let queryItems = [
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        var urlComps = URLComponents(string: socialLoginUrl.absoluteString)!
        urlComps.queryItems = (urlComps.queryItems ?? []) + queryItems
        
        let url = urlComps.url!
        
        DispatchQueue.main.sync {
            self.startExternalBrowser(webView, url)
        }
    }
    
    
    
    private func openExternalBrowser(_ _webView:WKWebView?, _ url:URL) -> WKNavigationActionPolicy {
        weak var webView = _webView
        self.startExternalBrowser(webView, url, true)
        return .cancel
    }
    
    override open var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
