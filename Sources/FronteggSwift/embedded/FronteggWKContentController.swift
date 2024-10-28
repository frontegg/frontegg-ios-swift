//
//  FronteggWKContentController.swift
//  
//
//  Created by David Frontegg on 15/09/2023.
//

import Foundation
import WebKit

struct HostedLoginMessage: Codable {
    let action: String
    let callbackId: String?
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
            let message = try JSONDecoder().decode(HostedLoginMessage.self, from: jsonData)
            handleAction(message)
        } catch {
            print("Error decoding JSON: \(error)")
        }
    }
    
    private func resolveMessage(callbackId: String, message: String) {
        webView?.evaluateJavaScript("window.navigator.credentials.helpers.listeners[\"\(callbackId)\"].resolve(\(message)\")")
    }
    
    private func handleAction(_ message: HostedLoginMessage) {
        switch (message.action) {
        
        case "getPasskey" , "createPasskey":
            guard let callbackId = message.callbackId else {
                return
            }
            guard let webView = self.webView, #available(iOS 15.0, *) else {
                webView?.evaluateJavaScript("window.navigator.credentials.helpers.listeners[\"\(callbackId)\"].reject(\"Passkeys not supported\")")
                return
            }
            do {
                try PasskeysAuthenticator.shared.handleHostedLoginRequest(message) { data, error in
                    if let dicData = data,
                       let jsonData = try? JSONSerialization.data(withJSONObject: dicData, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        webView.evaluateJavaScript("window.navigator.credentials.helpers.listeners.get(\"\(callbackId)\").resolve(\(jsonString))")
                    } else {
                        webView.evaluateJavaScript("window.navigator.credentials.helpers.listeners.get(\"\(callbackId)\").reject(\"\(error?.localizedDescription ?? "Unknown error occorred")\")")
                    }
                }
            } catch {
                webView.evaluateJavaScript("window.navigator.credentials.helpers.listeners.get(\"\(callbackId)\").reject(\"\(error.localizedDescription)\")")
            }
            
        case "loginWithSSO":
            FronteggAuth.shared.loginWithSSO(email: message.payload)
        case "loginWithSocialLogin":
            FronteggAuth.shared.loginWithSocialLogin(socialLoginUrl: message.payload)
        case "showLoader":
            FronteggAuth.shared.webLoading = true
        case "hideLoader":
            FronteggAuth.shared.webLoading = false
        default:
            return
        }
    }
}
