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
}
