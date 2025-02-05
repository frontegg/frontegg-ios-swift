//
//  FrontetggAuthentication.swift
//
//  Created by David Frontegg on 26/10/2022.
//

import AuthenticationServices
import UIKit


class WebAuthenticator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    static let shared = WebAuthenticator()
    
    weak var window: UIWindow? = nil
    var session: ASWebAuthenticationSession? = nil
    
    public typealias WebAuthenticationSessionFactory = (_ URL: URL, _ callbackURLScheme: String?, _ completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler) -> ASWebAuthenticationSession
    
    private let storage: FronteggInnerStorage
    private let factory: WebAuthenticationSessionFactory
    
    init(
        storage: FronteggInnerStorage = FronteggInnerStorage.shared,
        factory: @escaping WebAuthenticationSessionFactory = ASWebAuthenticationSession.init
    ) {
        self.storage = storage
        self.factory = factory
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window ?? FronteggAuth.shared.getRootVC()?.view.window ?? ASPresentationAnchor()
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        return true
    }
    
    func start(
        _ websiteURL:URL,
        ephemeralSession: Bool = false,
        window:UIWindow? = nil,
        completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler
    ) {
        if let lastSession = session {
            lastSession.cancel()
            session = nil
        }
        
        let bundleIdentifier = storage.bundleIdentifier
        let webAuthSession = factory(
            websiteURL,
            bundleIdentifier,
            completionHandler
        )
        // Run the session
        webAuthSession.presentationContextProvider = self
        webAuthSession.prefersEphemeralWebBrowserSession = ephemeralSession
        
        self.window = window
        self.session = webAuthSession
        webAuthSession.start()
    }
}
