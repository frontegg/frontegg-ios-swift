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
    private weak var hideLoaderWorkItem: DispatchWorkItem?
    private var logger = getLogger("FronteggWKContentController")
    
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
            self.logger.error("Error decoding JSON: \(error)")
        }
    }
    
    private func resolveMessage(callbackId: String, message: String) {
        webView?.evaluateJavaScript("window.navigator.credentials.helpers.listeners[\"\(callbackId)\"].resolve(\(message)\")")
    }
    
    private var socialLoginHandler: FronteggAuth.CompletionHandler {
        get {
            return { res in
                do {
                    let _ = try res.get()
                    FronteggAuth.shared.loginCompletion?(res)
                } catch(_) {
                    // ignore
                }
            }
        }
    }
    
    private var customSSOHandler: FronteggAuth.CompletionHandler {
        get {
            return { res in
                do {
                    let _ = try res.get()
                    FronteggAuth.shared.loginCompletion?(res)
                } catch(_) {
                    // ignore
                }
            }
        }
    }
    
    
    private func getFromAction() -> SocialLoginAction {
        
        if let url = self.webView?.url,
           url.absoluteString.contains("/oauth/account/sign-up"){
            
            return .signUp
            
        }
        return .login
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
            FronteggAuth.shared.loginWithSSO(email: message.payload, self.socialLoginHandler)
        case "loginWithCustomSSO":
            FronteggAuth.shared.loginWithCustomSSO(ssoUrl: message.payload, self.customSSOHandler)
        case "loginWithSocialLogin":
            FronteggAuth.shared.loginWithSocialLogin(socialLoginUrl: message.payload, self.socialLoginHandler)
        case "loginWithSocialLoginProvider":
            let formAction = self.getFromAction()
            if let config = try? PlistHelper.fronteggConfig(), config.useLegacySocialLoginFlow {
                FronteggAuth.shared.directLoginAction(window: nil,
                                                      type: "social-login",
                                                      data: message.payload,
                                                      ephemeralSession: false,
                                                      _completion: self.socialLoginHandler,
                                                      additionalQueryParams: [
                                                        "prompt":"consent"
                                                      ],
                                                      remainCodeVerifier: true,
                                                      action: formAction
                )
            }else {
                
                FronteggAuth.shared.handleSocialLogin(
                    providerString: message.payload,
                    action: formAction,
                    completion: self.socialLoginHandler,
                )
            }
        case "loginWithCustomSocialLoginProvider":
            let formAction = self.getFromAction()
            FronteggAuth.shared.directLoginAction(window: nil,
                                                  type: "custom-social-login",
                                                  data: message.payload,
                                                  ephemeralSession: false,
                                                  _completion: self.socialLoginHandler,
                                                  additionalQueryParams: [
                                                    "prompt":"consent"
                                                  ],
                                                  remainCodeVerifier: true,
                                                  action: formAction)
        case "suggestSavePassword":
            guard let data = try? JSONSerialization.jsonObject(with: Data(message.payload.utf8), options: []) as? [String: String],
                  let email = data["email"],
                  let password = data["password"] else {
                self.logger.error("Invalid payload for loginWithPassword")
                
                return
            }
            
            if let url = URL(string: FronteggAuth.shared.baseUrl), let domain = url.host {
                FronteggAuth.shared.saveWebCredentials(domain: domain, email: email, password: password) { success, error in
                    if success {
                        self.logger.debug("✅ Credentials saved successfully for \(email)")
                    } else {
                        self.logger.error("❌ Failed to save credentials: \(error?.localizedDescription ?? "Unknown error")")
                    }
                }
            } else {
                self.logger.error("❌ Invalid base URL: \(FronteggAuth.shared.baseUrl)")
            }
        case "setLoading":
            let isLoading = message.payload == "true"
            logger.trace("LoginBox.setLoading, \(isLoading)")
            
            // Cancel any pending hide
            hideLoaderWorkItem?.cancel()
            
            if isLoading {
                // show immediately
                FronteggAuth.shared.loginBoxLoading = true
            } else {
                // schedule hide after 200ms, to avoid flicker
                let workItem = DispatchWorkItem {
                    FronteggAuth.shared.loginBoxLoading = false
                }
                hideLoaderWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
            }
        default:
            return
        }
    }
}
