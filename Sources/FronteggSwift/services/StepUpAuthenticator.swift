//
//  StepUpAuthenticator.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 10.03.2025.
//


import Foundation

class StepUpAuthenticator {
    private let credentialManager: CredentialManager

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
        let updatedCompletion: FronteggAuth.CompletionHandler = { (result) in
            DispatchQueue.main.async {
                FronteggAuth.shared.isStepUpAuthorization = false
                completion?(result)
            }
        }

        let (authorizeUrl, codeVerifier) = AuthorizeUrlGenerator.shared.generate(
            stepUp: true,
            maxAge: maxAge
        )
        
        CredentialManager.saveCodeVerifier(codeVerifier)
        DispatchQueue.main.async {
            FronteggAuth.shared.isLoading = true
            FronteggAuth.shared.isStepUpAuthorization = true
            let oauthCallback = FronteggAuth.shared.createOauthCallbackHandler(updatedCompletion)
            WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
        }
    }
}
