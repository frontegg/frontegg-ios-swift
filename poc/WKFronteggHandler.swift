//
//  WKFronteggHandler.swift
//  poc
//
//  Created by David Frontegg on 26/10/2022.
//

import Foundation
import UniformTypeIdentifiers
import WebKit

protocol SchemeHandler: WKURLSchemeHandler {
    
}

/// extension to add a default HTTPURLResponse in case of error to be used by concrete types
extension SchemeHandler {
    static func responseError(forUrl url: URL?, message: String) -> (HTTPURLResponse, Data) {
        let responseUrl = url ?? URL(string: "error://error")!
        let response = HTTPURLResponse(url: responseUrl,
                                       mimeType: nil,
                                       expectedContentLength: message.count,
                                       textEncodingName: "utf-8")
        let data = message.data(using: .utf8) ?? Data()
        return (response, data)
    }
}

class WkFronteggHandler: NSObject, SchemeHandler {
    
    let fronteggAuth: FronteggAuth
    
    init(fronteggAuth: FronteggAuth) {
        self.fronteggAuth = fronteggAuth
    }
    // frontegg://local/
    // frontegg://auth/ ? token social ? jwt ? refresh token
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        
        if let httpMethod = urlSchemeTask.request.httpMethod,
           let url = urlSchemeTask.request.url,
           httpMethod == "POST" {
            
            var data = ""
            if let httpBody = urlSchemeTask.request.httpBody {
                data = String(bytes: httpBody, encoding: String.Encoding.utf8) ?? ""
            }
            
            if url.absoluteString == "frontegg://oauth/session" {
                self.fronteggAuth.isAuthenticated = true
            }
            print("POST METHOD URL: \(url)")
            print("POST METHOD DATA: \(data)")
        }
        
        guard let url = urlSchemeTask.request.url,
              let fileUrl = fileUrlFromUrl(url),
              let mimeType = mimeType(ofFileAtUrl: fileUrl)
        else {
            return
        }
        
    
        
        let data = try? Data(contentsOf: fileUrl)
        
        let response = HTTPURLResponse(url: url,
                                       mimeType: mimeType,
                                       expectedContentLength: data!.count, textEncodingName: nil)
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data!)
        urlSchemeTask.didFinish()
        
        
    }
    
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        
    }
    
    private func fileUrlFromUrl(_ url: URL) -> URL? {
        print("fileUrlFromUrl: \(url.absoluteString)")
        if url.absoluteString == "frontegg://oauth/authenticate" {
            return Bundle.main.url(forResource: "authenticate", withExtension: "html");
        }else if url.absoluteString.starts(with: "frontegg://oauth/callback")  {
            return Bundle.main.url(forResource: "exchange-token", withExtension: "html");
        }else if url.absoluteString.starts(with: "frontegg://oauth/success/callback")  {
            return Bundle.main.url(forResource: "exchange-token", withExtension: "html");
        } else {
            return nil
        }
    }
    
    private func mimeType(ofFileAtUrl url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return nil
        }
        return type.preferredMIMEType
    }
}
