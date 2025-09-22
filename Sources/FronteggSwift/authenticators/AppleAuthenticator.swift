//
//  AppleAuthenticator.swift
//
//
//  Created by David Antoon on 27/10/2024.
//

import Foundation
import AuthenticationServices



@available(iOS 15.0, *)
class AppleAuthenticator: NSObject, ASAuthorizationControllerPresentationContextProviding, ASAuthorizationControllerDelegate {
    
    static let shared = AppleAuthenticator()
    
    var logger = getLogger("AppleAuthenticator")
    var completionHandler: FronteggAuth.CompletionHandler? = nil
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return  FronteggAuth.shared.getRootVC()?.view.window ?? ASPresentationAnchor()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
           let authorizationCode = appleIDCredential.authorizationCode,
            let code  = String(data: authorizationCode, encoding: .utf8) {
            
            
            self.sendApplePostLogin(code)
        } else {
            logger.error("Failed to authenticate with AppleId provider")
            completionHandler?(.failure(FronteggError.authError(.unknown)))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        
        if let err = error as? ASAuthorizationError, err.code == ASAuthorizationError.canceled{
            logger.info("Sign in with Apple canceled by user")
            completionHandler?(.failure(FronteggError.authError(.operationCanceled)))
        }else {
            logger.error("Failed to authenticate with apple \(error.localizedDescription)")
            completionHandler?(.failure(FronteggError.authError(.other(error))))
        }
        completionHandler = nil
    }
    
    
    func sendApplePostLogin(_ code:String) {
        logger.info("Send apple post login request to obtain session")
        
        DispatchQueue.main.async {
            FronteggAuth.shared.isLoading = true
        }
        
        DispatchQueue.global(qos: .background).async {
            Task {
                do {
                    let authResponse = try await FronteggAuth.shared.api.postloginAppleNative(code)
                    
                    await FronteggAuth.shared.setCredentials(accessToken: authResponse.access_token, refreshToken: authResponse.refresh_token)
                    
                } catch {
                    if error is FronteggError {
                        await self.completionHandler?(.failure(error as! FronteggError))
                    }else {
                        await self.logger.error("Failed to authenticate with apple \(error.localizedDescription)")
                        await self.completionHandler?(.failure(.authError(.failedToAuthenticate)))
                    }
                    
                }
            }
        }
        
    }
    
    func start(completionHandler: @escaping FronteggAuth.CompletionHandler) {
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        
        request.requestedScopes = [.fullName, .email]
        request.requestedOperation = .operationLogin
        
        
        self.completionHandler = completionHandler
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
}

