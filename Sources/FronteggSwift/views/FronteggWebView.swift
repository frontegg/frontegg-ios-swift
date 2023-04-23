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

        let userContentController: WKUserContentController = WKUserContentController()

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

        userContentController.addUserScript(WKUserScript(source: metadataSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        let conf = WKWebViewConfiguration()
        conf.userContentController = userContentController
        conf.websiteDataStore = WKWebsiteDataStore.default()

        webView = CustomWebView(frame: .zero, configuration: conf)
        webView.navigationDelegate = webView;

    }

    func makeUIView(context: Context) -> WKWebView {
        let url: URL
        if let appLink = fronteggAuth.appLink {
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
