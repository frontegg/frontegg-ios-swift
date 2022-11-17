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


struct AuthResponse:Decodable {
    
    let token_type: String
    let refresh_token: String
    let access_token: String
    let id_token: String
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
                
                let jsonData = data.data(using: .utf8)!
                let authRes: AuthResponse? = try? JSONDecoder().decode(AuthResponse.self, from: jsonData)

                if let payload = authRes {
                    self.fronteggAuth.setCredentials(accessToken: payload.access_token, refreshToken: payload.refresh_token)
                }
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
//            if !self.fronteggAuth.isLoading {
//                self.fronteggAuth.isLoading = true
//            }
            return Bundle.main.url(forResource: "authenticate", withExtension: "html");
        }else if url.absoluteString.starts(with: "frontegg://oauth/callback")  {
//            if !self.fronteggAuth.isLoading {
//                self.fronteggAuth.isLoading = true
//            }
            return Bundle.main.url(forResource: "exchange-token", withExtension: "html");
        }else if url.absoluteString.starts(with: "frontegg://oauth/success/callback")  {
//            if !self.fronteggAuth.isLoading {
//                self.fronteggAuth.isLoading = true
//            }
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
