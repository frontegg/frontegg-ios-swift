//
//  FrontetggAuthentication.swift
//
//  Created by David Frontegg on 26/10/2022.
//

import AuthenticationServices
 

class WebAuthentication: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
    override func responds(to aSelector: Selector!) -> Bool {
        return true
    }
    
    var webAuthSession: ASWebAuthenticationSession?
    
    
    
    func start(_ websiteURL:URL, completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler) -> ASWebAuthenticationSession {
        
        let bundleIdentifier = try! PlistHelper.fronteggConfig().bundleIdentifier
        let webAuthSession = ASWebAuthenticationSession.init(
            url: websiteURL,
            callbackURLScheme: bundleIdentifier,
            completionHandler: completionHandler)
        // Run the session
        webAuthSession.presentationContextProvider = self
        webAuthSession.prefersEphemeralWebBrowserSession = false
        
        webAuthSession.start()
        self.webAuthSession = webAuthSession
        
        return webAuthSession
    }
}
