//
//  FronteggWKContentController.swift
//  
//
//  Created by David Frontegg on 15/09/2023.
//

import Foundation
import WebKit

struct FronteggMessage: Codable {
    let action: String
    let payload: String
}

class FronteggWKContentController: NSObject, WKScriptMessageHandler {
    
    weak var webView: CustomWebView? = nil
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        
        if message.name == "FronteggNativeBridge" {
            if let jsonString = message.body as? String {
                self.handleJsonMessage(jsonString: jsonString)
            }
        }
    }
    
    private func handleJsonMessage(jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(FronteggMessage.self, from: jsonData)
            handleAction(action: message.action, payload: message.payload)
        } catch {
            print("Error decoding JSON: \(error)")
        }
    }
    
    private func handleAction(action: String, payload: String) {
        switch (action) {
            
        case "loginWithSSO":
            FronteggAuth.shared.loginWithSSO(email: payload)
        case "loginWithSocialLogin":
            FronteggAuth.shared.loginWithSocialLogin(socialLoginUrl: payload)
        case "showLoader":
            FronteggAuth.shared.webLoading = true
        case "hideLoader":
            FronteggAuth.shared.webLoading = false
        default:
            return
        }
    }
}
