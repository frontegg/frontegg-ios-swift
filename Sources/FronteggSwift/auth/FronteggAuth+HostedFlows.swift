//
//  FronteggAuth+HostedFlows.swift
//  FronteggSwift
//
//  Hosted login flows: popup, direct actions, SSO.
//

import Foundation
import UIKit
import AuthenticationServices

extension FronteggAuth {

    public func login(_ _completion: FronteggAuth.CompletionHandler? = nil, loginHint: String? = nil) {

        if(self.embeddedMode){
            self.embeddedLogin(_completion, loginHint: loginHint)
            return
        }

        let completion = _completion ?? { res in

        }

        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: loginHint)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .login
        )


        WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
    }


    func saveWebCredentials(domain: String, email: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        let domainString = domain
        let account = email

        SecAddSharedWebCredential(domainString as CFString, account as CFString, password as CFString) { error in
            if let error = error {
                self.logger.error("Failed to save shared web credentials: \(error.localizedDescription)")
                completion(false, error)
            } else {
                self.logger.info("Shared web credentials saved successfully")
                completion(true, nil)
            }
        }
    }



    public func loginWithPopup(window: UIWindow?, ephemeralSession: Bool? = true, loginHint: String? = nil, loginAction: String? = nil, _completion: FronteggAuth.CompletionHandler? = nil) {

        let completion = _completion ?? { res in

        }

        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: loginHint, loginAction: loginAction)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: loginAction != nil,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .login
        )
        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: ephemeralSession ?? true, window:window,  completionHandler: oauthCallback)
    }

    public func directLoginAction(
        window: UIWindow?,
        type: String,
        data: String,
        ephemeralSession: Bool? = true,
        _completion: FronteggAuth.CompletionHandler? = nil,
        additionalQueryParams: [String: Any]? = nil,
        remainCodeVerifier: Bool = false,
        action: SocialLoginAction = SocialLoginAction.login
    ) {

        let completion = _completion ?? { res in

        }

        if(type == "social-login" && data == "apple") {
            self.loginWithApple(completion)
            return
        }


        var directLogin = [
            "type": type,
            "data": data,

        ] as [String : Any]

        if let queryParams = additionalQueryParams {
            directLogin["additionalQueryParams"] = queryParams
        }

        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: remainCodeVerifier)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: remainCodeVerifier)
        }

        let (authorizeUrl, codeVerifier) = generatedUrl
        let oauthFlow: FronteggOAuthFlow
        switch type {
        case "social-login", "custom-social-login":
            oauthFlow = .socialLogin
        case "direct" where data.contains("/user/sso/") || data.contains("appleid.apple.com"):
            oauthFlow = .socialLogin
        default:
            oauthFlow = .login
        }
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: oauthFlow
        )

        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: ephemeralSession ?? true, window: window ?? getRootVC()?.view.window, completionHandler: oauthCallback)
    }


    internal func getRootVC(_ useAppRootVC: Bool = false) -> UIViewController? {


        if let appDelegate = UIApplication.shared.delegate,
           let window = appDelegate.window,
           let rootVC = window?.rootViewController {

            if(useAppRootVC){
                return rootVC
            }else {
                if let presented = rootVC.presentedViewController {
                    return presented
                }else {
                    return rootVC
                }
            }
        }

        if let rootVC = UIWindow.key?.rootViewController {
            return rootVC
        }
        if let lastWindow = UIApplication.shared.windows.last,
           let rootVC = lastWindow.rootViewController {
            return rootVC
        }


        return nil
    }


    public func loginWithSSO(email: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in

        }
        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(loginHint: email, remainCodeVerifier: true)
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .sso
        )

        WebAuthenticator.shared.start(authorizeUrl, ephemeralSession: true, window: getRootVC()?.view.window, completionHandler: oauthCallback)
    }

    public func loginWithCustomSSO(ssoUrl: String, _ _completion: FronteggAuth.CompletionHandler? = nil) {
        let completion = _completion ?? self.loginCompletion ?? { res in

        }

        let directLogin: [String: Any] = [
            "type": "direct",
            "data": ssoUrl,
        ]
        var generatedUrl: (URL, String)
        if let jsonData = try? JSONSerialization.data(withJSONObject: directLogin, options: []) {
            let jsonString = jsonData.base64EncodedString()
            generatedUrl = AuthorizeUrlGenerator.shared.generate(loginAction: jsonString, remainCodeVerifier: true)
        } else {
            generatedUrl = AuthorizeUrlGenerator.shared.generate(remainCodeVerifier: true)
        }

        let (authorizeUrl, codeVerifier) = generatedUrl
        let oauthCallback = createOauthCallbackHandler(
            completion,
            allowLastCodeVerifierFallback: true,
            pendingOAuthState: pendingOAuthState(from: authorizeUrl),
            flow: .customSSO
        )
        FronteggRuntime.testingLog("loginWithCustomSSO authorizeUrl: \(authorizeUrl.absoluteString)")

        WebAuthenticator.shared.start(
            authorizeUrl,
            ephemeralSession: true,
            window: getRootVC()?.view.window,
            completionHandler: oauthCallback
        )
    }
}
