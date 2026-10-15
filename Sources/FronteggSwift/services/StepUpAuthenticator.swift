//
//  StepUpAuthenticator.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 10.03.2025.
//


import Foundation
import UIKit

class StepUpAuthenticator {
    private let credentialManager: CredentialManager
    private let activeStepUpLock = NSRecursiveLock()
    private var activeStepUpId: UUID?
    private weak var stepUpWindow: UIViewController?
    private let logger = getLogger("StepUpAuthenticator")

    init(
        credentialManager: CredentialManager
    ) {
        self.credentialManager = credentialManager
    }

    func isSteppedUp(maxAge: TimeInterval? = nil) -> Bool {
        guard let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) else {
            return false
        }

        guard let jwt = try? JWTHelper.decode(jwtToken: accessToken) else {
            return false
        }

        let authTime = jwt["auth_time"] as? Double
        let acr = jwt["acr"] as? String
        let amr = jwt["amr"] as? [String]

        if let authTime = authTime, let maxAge = maxAge {
            let nowInSeconds = Date().timeIntervalSince1970
            if nowInSeconds - authTime > maxAge {
                return false
            }
        }

        let isACRValid = acr == StepUpConstants.ACR_VALUE
        let isAMRIncludesMFA = amr?.contains(StepUpConstants.AMR_MFA_VALUE) ?? false
        let isAMRIncludesMethod = amr?.contains(where: { StepUpConstants.AMR_ADDITIONAL_VALUE.contains($0) }) ?? false

        return isACRValid && isAMRIncludesMFA && isAMRIncludesMethod
    }
    
    public func stepUp(
        maxAge: TimeInterval? = nil,
        completion: FronteggAuth.CompletionHandler? = nil
    ) {
        DispatchQueue.main.async {
            if FronteggAuth.shared.isEmbeddedLoginInProgress {
                self.logger.warning("stepUp refused: an embedded login window is already on screen; completing with operationCanceled")
                completion?(.failure(.authError(.operationCanceled)))
                return
            }

            let (authorizeUrl, _) = AuthorizeUrlGenerator.shared.generate(
                stepUp: true,
                maxAge: maxAge
            )
            let stepUpCompletion = self.makeStepUpCompletion(completion)
            FronteggAuth.shared.setIsLoading(false)

            // Always present step-up in the embedded bridge webview (like the Admin
            // Portal), regardless of the app's login mode. The embedded webview reuses
            // the existing native session via the getTokens bridge; a system browser
            // (ASWebAuthenticationSession) cannot, which white-pages / forces a second
            // login for hosted-login apps.
            FronteggAuth.shared.activeEmbeddedOAuthFlow = .stepUp
            FronteggAuth.shared.pendingAppLink = authorizeUrl
            FronteggAuth.shared.setWebLoading(true)
            FronteggAuth.shared.embeddedLogin(stepUpCompletion, loginHint: nil)
            self.stepUpWindow = FronteggAuth.shared.presentedEmbeddedLogin
        }
    }

    func makeStepUpCompletion(_ completion: FronteggAuth.CompletionHandler?) -> FronteggAuth.CompletionHandler {
        let stepUpId = UUID()
        activeStepUpLock.withLock {
            activeStepUpId = stepUpId
            FronteggAuth.shared.setIsStepUpAuthorization(true)
        }
        return { result in
            DispatchQueue.main.async {
                guard self.endActiveStepUp(ifCurrent: stepUpId) else {
                    completion?(result)
                    return
                }
                FronteggAuth.shared.setIsLoading(false)
                let ownWindow = self.stepUpWindow
                self.stepUpWindow = nil
                FronteggAuth.shared.dismissEmbeddedLogin(ownWindow) {
                    completion?(result)
                }
            }
        }
    }

    func endActiveStepUp() {
        activeStepUpLock.withLock {
            activeStepUpId = nil
            FronteggAuth.shared.setIsStepUpAuthorization(false)
        }
    }

    private func endActiveStepUp(ifCurrent stepUpId: UUID) -> Bool {
        activeStepUpLock.withLock {
            guard activeStepUpId == stepUpId else { return false }
            activeStepUpId = nil
            FronteggAuth.shared.setIsStepUpAuthorization(false)
            return true
        }
    }
}
