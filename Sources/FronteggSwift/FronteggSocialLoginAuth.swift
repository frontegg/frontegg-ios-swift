//
//  FronteggSocialLoginAuth.swift
//  poc
//
//  Created by David Frontegg on 26/10/2022.
//

import AuthenticationServices
 
class FronteggSocialLoginAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
    
 
    var webAuthSession: ASWebAuthenticationSession?
    
    override func responds(to aSelector: Selector!) -> Bool {
        return true
    }
    
    func startLoginTransition(_ websiteURL:URL, completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler){
        webAuthSession = ASWebAuthenticationSession.init(
            url: websiteURL,
            callbackURLScheme: SchemeConstants.webAuthenticationCallbackScheme,
            completionHandler: completionHandler
        )

        // Run the session
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = false
        
        DispatchQueue.main.async {
            self.webAuthSession?.start()
        }
    }
}
