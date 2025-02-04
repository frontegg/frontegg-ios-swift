//
//  AppleAuthenticator.swift
//
//
//  Created by David Antoon on 27/10/2024.
//

import Foundation
import AuthenticationServices

public typealias AppleSignInAuthenticationDelegate = (Result<String, FronteggError>) -> Void

public protocol AppleIDCredential {
    var authorizationCode: Data? { get }
}

extension ASAuthorizationAppleIDCredential: AppleIDCredential {}


@available(iOS 15.0, *)
class AppleAuthenticator: NSObject, ASAuthorizationControllerPresentationContextProviding, ASAuthorizationControllerDelegate {
    private var logger = getLogger("AppleAuthenticator")
    
    public typealias ControllerFactory = (_ requests: [ASAuthorizationRequest]) -> ASAuthorizationController
    
    private let delegate: AppleSignInAuthenticationDelegate
    private let factory: ControllerFactory
    
    init(
        delegate: @escaping AppleSignInAuthenticationDelegate,
        factory: @escaping ControllerFactory = ASAuthorizationController.init,
        completionHandler: FronteggAuth.CompletionHandler? = nil
    ) {
        self.delegate = delegate
        self.factory = factory
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return FronteggAuth.shared.getRootVC()?.view.window ?? ASPresentationAnchor()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credentials = authorization.credential as? AppleIDCredential else {
            logger.error("Failed to authenticate with AppleId provider")
            delegate(.failure (FronteggError.authError(.unknown)))
            return
        }
        completeWith(credential: credentials)
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if let err = error as? ASAuthorizationError, err.code == ASAuthorizationError.canceled{
            logger.info("Sign in with Apple canceled by user")
            delegate(.failure (FronteggError.authError(.operationCanceled)))
        } else {
            logger.error("Failed to authenticate with apple \(error.localizedDescription)")
            delegate(.failure (FronteggError.authError(.other(error))))
        }
    }
    
    func completeWith(credential: AppleIDCredential) {
        if let authorizationCode = credential.authorizationCode,
           let code = String(data: authorizationCode, encoding: .utf8) {
            delegate(.success(code))
        } else {
            logger.error("Failed to authenticate with AppleId provider")
            delegate(.failure (FronteggError.authError(.unknown)))
        }
    }
    
    func start() {
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        
        request.requestedScopes = [.fullName, .email]
        request.requestedOperation = .operationLogin
        
        
        let authorizationController = factory([request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
}
