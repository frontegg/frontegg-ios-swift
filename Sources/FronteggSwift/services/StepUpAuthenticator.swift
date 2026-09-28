//
//  StepUpAuthenticator.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 10.03.2025.
//


import Foundation

class StepUpAuthenticator {
    private let credentialManager: CredentialManager
    private var activeStepUpId: UUID?
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
            // Refuse while any embedded login is open so step-up state is never set without an owner to clear it.
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
            FronteggAuth.shared.setIsStepUpAuthorization(true)
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
        }
    }

    /// Makes this the current step-up; only the current step-up clears shared step-up state, so a stale completion cannot close a newer window.
    func makeStepUpCompletion(_ completion: FronteggAuth.CompletionHandler?) -> FronteggAuth.CompletionHandler {
        let stepUpId = UUID()
        activeStepUpId = stepUpId
        return { result in
            DispatchQueue.main.async {
                if self.activeStepUpId == stepUpId {
                    self.activeStepUpId = nil
                    FronteggAuth.shared.setIsStepUpAuthorization(false)
                    FronteggAuth.shared.setIsLoading(false)
                }
                completion?(result)
            }
        }
    }
}
