//
//  SwiftUIWebView.swift
//
//  Created by David Frontegg on 24/10/2022.
//

import Foundation
import WebKit
import SwiftUI
import AuthenticationServices
 


struct FronteggWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView
    
    let webView: CustomWebView
    private var fronteggAuth: FronteggAuth
    
    init() {
        self.fronteggAuth = FronteggApp.shared.auth;
        
        let preloadJSScript = JSHelper.generatePreloadScript()
        let contextOptionsScript = JSHelper.generateContextOptions(fronteggAuth.baseUrl, fronteggAuth.clientId)
        
        
        let userContentController: WKUserContentController = WKUserContentController()
        userContentController.addUserScript(contextOptionsScript)
        userContentController.addUserScript(preloadJSScript)
//        userContentController.add(self, name: "fronteggSwiftHandler")
                
        let assetsHandler = FronteggSchemeHandler(fronteggAuth: fronteggAuth)
        
        let conf = WKWebViewConfiguration()
        conf.userContentController = userContentController
        conf.setURLSchemeHandler(assetsHandler , forURLScheme: "frontegg" )
        conf.websiteDataStore = WKWebsiteDataStore.default()
        
        webView = CustomWebView(frame: .zero, configuration: conf)
        webView.fronteggAuth = fronteggAuth;
        webView.navigationDelegate = webView;
        
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let url: URL
        if let appLink = self.fronteggAuth.pendingAppLink {
            url = appLink
        } else {
            url = AuthorizeUrlGenerator().generate()
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
