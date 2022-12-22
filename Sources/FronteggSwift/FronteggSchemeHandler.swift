//
//  WKFronteggHandler.swift
//
//  Created by David Frontegg on 26/10/2022.
//

import Foundation
import UniformTypeIdentifiers
import WebKit

protocol SchemeHandler: WKURLSchemeHandler {
    
}

class FronteggSchemeHandler: NSObject, SchemeHandler {
    
    let fronteggAuth: FronteggAuth
    
    init(fronteggAuth: FronteggAuth) {
        self.fronteggAuth = fronteggAuth
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        
//        if let httpMethod = urlSchemeTask.request.httpMethod,
//           let url = urlSchemeTask.request.url,
//           httpMethod == "POST" {
//
//            var data = ""
//            if let httpBody = urlSchemeTask.request.httpBody {
//                data = String(bytes: httpBody, encoding: String.Encoding.utf8) ?? ""
//            }
//
//            if url.absoluteString == "frontegg://oauth/session" {
//
//                let jsonData = data.data(using: .utf8)!
//                let authRes: AuthResponse? = try? JSONDecoder().decode(AuthResponse.self, from: jsonData)
//
//                if let payload = authRes {
//                    Task{
//                        await self.fronteggAuth.setCredentials(
//                            accessToken: payload.access_token,
//                            refreshToken: payload.refresh_token
//                        )
//                    }
//                }else {
//                    webView.load(URLRequest(url: URLConstants.authenticateUrl))
//                }
//            }
//        }
//
        guard let url = urlSchemeTask.request.url,
              let httpMethod = urlSchemeTask.request.httpMethod,
              httpMethod == "GET",
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
        guard url.scheme == "frontegg", url.host == "oauth" else { return nil }
        
        let resource: String
        
        switch url.path {
        case "/authenticate":
            resource = "authenticate"
        case "/callback", "/success/callback":
            resource = "exchange-token"
        default:
            print("No resource found for \(url.absoluteString)")
            return nil
        }
        
        return Bundle.main.url(forResource: resource, withExtension: "html", subdirectory: "FronteggSwift_FronteggSwift.bundle");
    }
    
    private func mimeType(ofFileAtUrl url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return nil
        }
        return type.preferredMIMEType
    }
}
